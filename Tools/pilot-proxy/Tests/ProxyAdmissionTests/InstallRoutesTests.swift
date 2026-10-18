import Crypto
import Foundation
import XCTest

@testable import ProxyAdmission

final class InstallRoutesTests: XCTestCase {
    private static let pilotToken = "pilot-token-for-tests"
    private static let pixel = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR42mNgAAAAAgAB5Sfe/AAAAABJRU5ErkJggg=="
    )!
    private static let bundle = "edu.bowdoin.margin"
    private static let product = "lemmanotesai.premium.yearly"

    /// A running proxy in miniature: a real router over an in-memory install store and a temporary spend ledger.
    private struct Rig {
        let router: PilotRouter
        let store: InMemoryInstallStore
        let authority: TestAttestation
        let storeKitPKI: TestPKI
    }

    private func rig(installsEnabled: Bool = true) throws -> Rig {
        let authority = try TestAttestation()
        let storeKitPKI = try TestPKI()
        let store = InMemoryInstallStore()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        let ledger = try SpendLedger.bootstrap(
            databaseURL: folder.appendingPathComponent("spend.sqlite"), limitMicros: 5_000_000)
        let gate = AdmissionGate(
            authorize: PilotRouter.authorizer(token: Self.pilotToken, subjectID: UUID().uuidString))
        let service = PilotService(pilot: PilotAdmission(admission: gate, ledger: ledger), transport: FixedTransport())
        var router = PilotRouter(service: service)
        if installsEnabled {
            let trust = InstallTrust(
                verifier: AppAttestVerifier(
                    roots: [authority.root], appID: TestAttestation.appID, allowsDevelopment: false,
                    now: { TestAttestation.now }),
                challenges: AttestationChallenges(secret: Data(repeating: 3, count: 32), now: { TestAttestation.now }),
                store: store, now: { TestAttestation.now })
            router.installs = InstallGate(
                trust: trust,
                transactions: AppleTransactionVerifier(
                    roots: [storeKitPKI.root], bundleID: Self.bundle, productIDs: [Self.product],
                    now: { TestAttestation.now }),
                now: { TestAttestation.now })
        }
        return Rig(router: router, store: store, authority: authority, storeKitPKI: storeKitPKI)
    }

    private func post(_ rig: Rig, _ path: String, headers: [String: String] = [:], body: Data) async -> HTTPReply {
        await rig.router.route(
            HTTPHead(method: "POST", path: path, headers: headers, contentLength: body.count), body: body)
    }

    private func get(_ rig: Rig, _ path: String) async -> HTTPReply {
        await rig.router.route(HTTPHead(method: "GET", path: path, headers: [:], contentLength: 0), body: Data())
    }

    /// Registers a fresh device and returns it.
    private func register(_ rig: Rig) async throws -> TestAttestation.Device {
        let challenge = try challengeData(await get(rig, "/v1/challenge"))
        let device = try rig.authority.attest(challenge: challenge)
        let body = try JSONSerialization.data(withJSONObject: [
            "keyID": device.keyID.base64EncodedString(), "attestation": device.attestation.base64EncodedString(),
            "challenge": challenge.base64EncodedString(),
        ])
        let reply = await post(rig, "/v1/register", body: body)
        XCTAssertEqual(reply.status, 200)
        return device
    }

    private func challengeData(_ reply: HTTPReply) throws -> Data {
        XCTAssertEqual(reply.status, 200)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: reply.body) as? [String: String])
        return try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(object["challenge"])))
    }

    private func headers(_ device: TestAttestation.Device, body: Data, counter: UInt32) throws -> [String: String] {
        [
            "x-install-key": device.keyID.base64EncodedString(),
            "x-install-assertion": try TestAttestation.assertion(for: device, clientData: body, counter: counter)
                .base64EncodedString(),
        ]
    }

    private func answerBody() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "requestID": UUID().uuidString, "cropPNG": Self.pixel.base64EncodedString(),
            "neighborhoodPNG": Self.pixel.base64EncodedString(), "transcript": "what is photosynthesis",
            "intent": "continue", "maxOutputTokens": 256,
        ])
    }

    private func ask(_ rig: Rig, _ device: TestAttestation.Device, counter: UInt32) async throws -> HTTPReply {
        let body = try answerBody()
        return await post(rig, "/v1/answer", headers: try headers(device, body: body, counter: counter), body: body)
    }

    private func transactionBody(_ rig: Rig, product: String = InstallRoutesTests.product) throws -> Data {
        let claims: [String: Any] = [
            "bundleId": Self.bundle, "productId": product, "originalTransactionId": "1000000777",
            "environment": "Production",
            "expiresDate": (TestAttestation.now.timeIntervalSince1970 + 86_400 * 30) * 1000,
        ]
        let jws = try rig.storeKitPKI.signedTransaction(claims: claims)
        return try JSONSerialization.data(withJSONObject: ["transaction": jws])
    }

    // MARK: - Tests

    func testChallengesAreIssuedOnlyWhenInstallsAreEnabled() async throws {
        let enabled = try rig()
        _ = try challengeData(await get(enabled, "/v1/challenge"))
        let off = try rig(installsEnabled: false)
        let disabled = await get(off, "/v1/challenge")
        XCTAssertEqual(disabled.status, 404)
        let registerOff = await post(off, "/v1/register", body: Data("{}".utf8))
        XCTAssertEqual(registerOff.status, 404)
    }

    func testARegisteredInstallGetsAnswersAndExactlyThreeFreeAsks() async throws {
        let rig = try rig()
        let device = try await register(rig)
        for counter in UInt32(1)...3 {
            let reply = try await ask(rig, device, counter: counter)
            XCTAssertEqual(reply.status, 200, "ask \(counter)")
            XCTAssertEqual(reply.body, Data(#"{"version":1}"#.utf8))
        }
        let fourth = try await ask(rig, device, counter: 4)
        XCTAssertEqual(fourth.status, 402)
        let loaded = try await rig.store.load(device.keyID)
        XCTAssertEqual(loaded?.record.tourAsksUsed, 3)
        XCTAssertEqual(loaded?.record.key.counter, 3, "a refused ask does not advance the counter")
    }

    func testAReplayedRequestIsRefused() async throws {
        let rig = try rig()
        let device = try await register(rig)
        let body = try answerBody()
        let replayHeaders = try headers(device, body: body, counter: 1)
        let first = await post(rig, "/v1/answer", headers: replayHeaders, body: body)
        XCTAssertEqual(first.status, 200)
        let replay = await post(rig, "/v1/answer", headers: replayHeaders, body: body)
        XCTAssertEqual(replay.status, 401)
    }

    func testAnAssertionForOneBodyDoesNotAuthorizeAnother() async throws {
        let rig = try rig()
        let device = try await register(rig)
        let signedFor = try answerBody()
        let swapped = try answerBody()
        let reply = await post(
            rig, "/v1/answer", headers: try headers(device, body: signedFor, counter: 1), body: swapped)
        XCTAssertEqual(reply.status, 401)
    }

    func testAnUnknownOrUnsignedCallerIsRefused() async throws {
        let rig = try rig()
        let body = try answerBody()
        let none = await post(rig, "/v1/answer", body: body)
        XCTAssertEqual(none.status, 401)
        let stranger = try rig.authority.attest(challenge: Data(repeating: 1, count: 56))
        let unknown = await post(
            rig, "/v1/answer", headers: try headers(stranger, body: body, counter: 1), body: body)
        XCTAssertEqual(unknown.status, 401)
    }

    func testAPurchaseLiftsTheFreeLimitAndIsCostedAgainstTheMonthlyAllowance() async throws {
        let rig = try rig()
        let device = try await register(rig)
        for counter in UInt32(1)...3 { _ = try await ask(rig, device, counter: counter) }
        let blocked = try await ask(rig, device, counter: 4)
        XCTAssertEqual(blocked.status, 402)

        let body = try transactionBody(rig)
        let upgraded = await post(
            rig, "/v1/entitlement", headers: try headers(device, body: body, counter: 4), body: body)
        XCTAssertEqual(upgraded.status, 200)
        XCTAssertEqual(upgraded.body, Data(#"{"plan":"premium"}"#.utf8))

        let allowed = try await ask(rig, device, counter: 5)
        XCTAssertEqual(allowed.status, 200)
        let stored = try await rig.store.load(device.keyID)
        let usage = try XCTUnwrap(stored?.record.usageMicros)
        XCTAssertGreaterThan(usage, 0)
        XCTAssertLessThan(usage, 50_000, "the worst-case hold was replaced by the real, much smaller cost")
    }

    func testAPaidInstallThatHasSpentItsAllowanceIsStopped() async throws {
        let rig = try rig()
        let device = try await register(rig)
        let body = try transactionBody(rig)
        _ = await post(rig, "/v1/entitlement", headers: try headers(device, body: body, counter: 1), body: body)
        let stored = try await rig.store.load(device.keyID)
        let loaded = try XCTUnwrap(stored)
        var spent = loaded.record
        spent.usageMonth = InstallAllowance.month(of: TestAttestation.now)
        spent.usageMicros = InstallAllowance.monthlyMicros - 10_000
        let saved = try await rig.store.save(spent, ifVersion: loaded.version)
        XCTAssertTrue(saved)

        let reply = try await ask(rig, device, counter: 2)
        XCTAssertEqual(reply.status, 429)
    }

    func testABadOrWrongProductTransactionChangesNothing() async throws {
        let rig = try rig()
        let device = try await register(rig)
        let wrongProduct = try transactionBody(rig, product: "someone.elses.product")
        let reply = await post(
            rig, "/v1/entitlement", headers: try headers(device, body: wrongProduct, counter: 1), body: wrongProduct)
        XCTAssertEqual(reply.status, 422)
        let garbage = try JSONSerialization.data(withJSONObject: ["transaction": "not.a.jws"])
        let rejected = await post(
            rig, "/v1/entitlement", headers: try headers(device, body: garbage, counter: 2), body: garbage)
        XCTAssertEqual(rejected.status, 422)
        let loaded = try await rig.store.load(device.keyID)
        XCTAssertEqual(loaded?.record.plan, InstallPlan.free)
    }

    func testRegistrationRefusesForgedChallengesAndSecondUse() async throws {
        let rig = try rig()
        let forged = Data(repeating: 1, count: AttestationChallenges.length)
        let device = try rig.authority.attest(challenge: forged)
        let forgedBody = try JSONSerialization.data(withJSONObject: [
            "keyID": device.keyID.base64EncodedString(), "attestation": device.attestation.base64EncodedString(),
            "challenge": forged.base64EncodedString(),
        ])
        let refused = await post(rig, "/v1/register", body: forgedBody)
        XCTAssertEqual(refused.status, 400)

        let challenge = try challengeData(await get(rig, "/v1/challenge"))
        let real = try rig.authority.attest(challenge: challenge)
        let body = try JSONSerialization.data(withJSONObject: [
            "keyID": real.keyID.base64EncodedString(), "attestation": real.attestation.base64EncodedString(),
            "challenge": challenge.base64EncodedString(),
        ])
        let first = await post(rig, "/v1/register", body: body)
        XCTAssertEqual(first.status, 200)
        let second = await post(rig, "/v1/register", body: body)
        XCTAssertEqual(second.status, 409)
        let junk = await post(rig, "/v1/register", body: Data("nope".utf8))
        XCTAssertEqual(junk.status, 400)
    }

    func testThePilotTokenStillWorksAlongsideInstalls() async throws {
        let rig = try rig()
        let body = try answerBody()
        let good = await post(rig, "/v1/answer", headers: ["authorization": "Bearer \(Self.pilotToken)"], body: body)
        XCTAssertEqual(good.status, 200)
        let bad = await post(rig, "/v1/answer", headers: ["authorization": "Bearer nope"], body: body)
        XCTAssertEqual(bad.status, 401)
    }

    func testAnUnservedAskGivesItsAllowanceBack() async throws {
        let rig = try rig()
        let device = try await register(rig)
        let junk = Data("not a request".utf8)
        let reply = await post(
            rig, "/v1/answer", headers: try headers(device, body: junk, counter: 1), body: junk)
        XCTAssertEqual(reply.status, 422)
        let loaded = try await rig.store.load(device.keyID)
        XCTAssertEqual(loaded?.record.tourAsksUsed, 0, "a malformed ask does not spend a free ask")
        XCTAssertEqual(loaded?.record.key.counter, 1, "but the signed counter still moves, so it cannot be replayed")
    }

    func testTheLedgerSubjectIsStablePerInstall() {
        let key = Data((0..<32).map(UInt8.init))
        XCTAssertEqual(PilotService.subject(for: key), PilotService.subject(for: key))
        XCTAssertNotNil(UUID(uuidString: PilotService.subject(for: key)))
        XCTAssertNotEqual(PilotService.subject(for: key), PilotService.subject(for: Data(repeating: 9, count: 32)))
    }
}

private struct FixedTransport: PilotModelTransport {
    func complete(_ request: AdmittedRequest) async throws -> GeminiReply {
        GeminiReply(specJSON: Data(#"{"version":1}"#.utf8), promptTokens: 100, outputTokens: 10)
    }
}
