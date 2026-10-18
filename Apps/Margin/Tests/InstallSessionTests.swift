import CryptoKit
import Foundation
import Intelligence
import XCTest

@testable import Margin

final class InstallSessionTests: XCTestCase {
    private static let base = URL(string: "https://proxy.example")!

    private final class FakeAttesting: InstallAttesting, @unchecked Sendable {
        var isSupported = true
        var keysMade = 0
        var attestedHashes: [Data] = []
        var assertedHashes: [Data] = []
        var failNextAssertion = false
        var invalidKeys: Set<String> = []

        func generateKey() async throws -> String {
            keysMade += 1
            return Data("key-\(keysMade)".utf8).base64EncodedString()
        }
        func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
            attestedHashes.append(clientDataHash)
            return Data("attestation-for-\(keyID)".utf8)
        }
        func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
            if invalidKeys.contains(keyID) { throw InstallIdentityError.unsupported }
            assertedHashes.append(clientDataHash)
            return Data("assertion".utf8)
        }
    }

    private final class MemoryKeys: InstallKeyStore, @unchecked Sendable {
        var stored: String?
        func keyID() -> String? { stored }
        func save(_ keyID: String) { stored = keyID }
        func clear() { stored = nil }
    }

    private actor Server {
        var requests: [URLRequest] = []
        var registerStatus = 200
        let challenge = Data((0..<56).map { UInt8($0) })

        func handle(_ request: URLRequest) -> (Data, URLResponse) {
            requests.append(request)
            let path = request.url?.path ?? ""
            var status = 200
            var body = Data("{}".utf8)
            if path == "/v1/challenge" {
                body = Data(#"{"challenge":"\#(challenge.base64EncodedString())"}"#.utf8)
            } else if path == "/v1/register" {
                status = registerStatus
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (body, response)
        }

        func setRegisterStatus(_ status: Int) { registerStatus = status }
    }

    private struct Rig {
        let session: InstallSession
        let attesting: FakeAttesting
        let keys: MemoryKeys
        let server: Server
    }

    private func rig(
        _ attesting: FakeAttesting = FakeAttesting(), keys: MemoryKeys = MemoryKeys(), server: Server = Server()
    ) -> Rig {
        Rig(
            session: InstallSession(
                baseURL: Self.base, attesting: attesting, keys: keys, send: { try await server.handle($0) }),
            attesting: attesting, keys: keys, server: server)
    }

    func testTheFirstRequestRegistersWithAnAttestationOverTheChallengeHash() async throws {
        let rig = rig()
        let (session, attesting, keys, server) = (rig.session, rig.attesting, rig.keys, rig.server)
        _ = try await session.headers(forBody: Data("body".utf8))
        let challenge = await server.challenge
        XCTAssertEqual(attesting.attestedHashes, [Data(SHA256.hash(data: challenge))])
        XCTAssertNotNil(keys.stored)
        let paths = await server.requests.map { $0.url?.path ?? "" }
        XCTAssertEqual(paths, ["/v1/challenge", "/v1/register"])
        let sentRequests = await server.requests
        let register = try XCTUnwrap(sentRequests.last?.httpBody)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: register) as? [String: String])
        XCTAssertEqual(Set(fields.keys), ["keyID", "attestation", "challenge"])
    }

    func testEveryRequestCarriesTheKeyAndAnAssertionOverItsExactBody() async throws {
        let rig = rig()
        let (session, attesting, _, _) = (rig.session, rig.attesting, rig.keys, rig.server)
        let body = Data("the request body".utf8)
        let headers = try await session.headers(forBody: body)
        XCTAssertEqual(headers["x-install-key"], Data("key-1".utf8).base64EncodedString())
        XCTAssertNotNil(headers["x-install-assertion"])
        XCTAssertEqual(attesting.assertedHashes, [Data(SHA256.hash(data: body))])
        _ = try await session.headers(forBody: body)
        XCTAssertEqual(attesting.keysMade, 1, "registration happens once")
    }

    func testConcurrentFirstRequestsRegisterOnlyOnce() async throws {
        let rig = rig()
        let (session, attesting, _, server) = (rig.session, rig.attesting, rig.keys, rig.server)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<6 {
                group.addTask { _ = try await session.headers(forBody: Data([UInt8(index)])) }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(attesting.keysMade, 1)
        let registers = await server.requests.filter { $0.url?.path == "/v1/register" }
        XCTAssertEqual(registers.count, 1)
    }

    func testAnAlreadyRegisteredKeyIsOursAndIsSaved() async throws {
        let server = Server()
        await server.setRegisterStatus(409)
        let rig = rig(server: server)
        let (session, _, keys, _) = (rig.session, rig.attesting, rig.keys, rig.server)
        _ = try await session.headers(forBody: Data())
        XCTAssertNotNil(keys.stored)
    }

    func testARefusedRegistrationThrowsAndSavesNothing() async throws {
        let server = Server()
        await server.setRegisterStatus(401)
        let rig = rig(server: server)
        let (session, _, keys, _) = (rig.session, rig.attesting, rig.keys, rig.server)
        do {
            _ = try await session.headers(forBody: Data())
            XCTFail("registered despite a refusal")
        } catch let error as InstallIdentityError {
            XCTAssertEqual(error, .registrationFailed)
        }
        XCTAssertNil(keys.stored)
    }

    func testADeviceWithoutAppAttestIsUnavailableAndNeverContactsTheServer() async throws {
        let attesting = FakeAttesting()
        attesting.isSupported = false
        let rig = rig(attesting)
        let (session, _, _, server) = (rig.session, rig.attesting, rig.keys, rig.server)
        XCTAssertFalse(session.isAvailable)
        do {
            _ = try await session.headers(forBody: Data())
            XCTFail("signed without App Attest")
        } catch let error as InstallIdentityError {
            XCTAssertEqual(error, .unsupported)
        }
        let requests = await server.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testAKeyKilledByAReinstallRegistersAgain() async throws {
        let keys = MemoryKeys()
        keys.stored = "dead-key"
        let attesting = FakeAttesting()
        attesting.invalidKeys = ["dead-key"]
        let rig = rig(attesting, keys: keys)
        let session = rig.session
        let headers = try await session.headers(forBody: Data("x".utf8))
        XCTAssertEqual(headers["x-install-key"], Data("key-1".utf8).base64EncodedString())
        XCTAssertEqual(keys.stored, Data("key-1".utf8).base64EncodedString())
    }

    func testRejectionForgetsTheRegistration() async throws {
        let rig = rig()
        let (session, attesting, keys, _) = (rig.session, rig.attesting, rig.keys, rig.server)
        _ = try await session.headers(forBody: Data())
        await session.rejected()
        XCTAssertNil(keys.stored)
        _ = try await session.headers(forBody: Data())
        XCTAssertEqual(attesting.keysMade, 2)
    }

    func testUploadingATransactionIsSignedWithTheInstallHeaders() async throws {
        let rig = rig()
        let (session, _, _, server) = (rig.session, rig.attesting, rig.keys, rig.server)
        try await session.uploadTransaction("signed.jws.value")
        let sentRequests = await server.requests
        let request = try XCTUnwrap(sentRequests.last)
        XCTAssertEqual(request.url?.path, "/v1/entitlement")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-install-key"))
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-install-assertion"))
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(
            (try JSONSerialization.jsonObject(with: body) as? [String: String])?["transaction"], "signed.jws.value")
    }
}

final class HostedAccessConfigurationTests: XCTestCase {
    private struct Source: InstallCredentialSource {
        let isAvailable: Bool
        func headers(forBody body: Data) async throws -> [String: String] { [:] }
        func rejected() async {}
    }

    private struct NoSecrets: PilotSecretStore {
        func token() -> String? { nil }
        func setToken(_ value: String?) -> Bool { true }
    }

    private struct TokenSecrets: PilotSecretStore {
        func token() -> String? { "tok" }
        func setToken(_ value: String?) -> Bool { true }
    }

    private func configuration(
        token: Bool = false, installs: Bool? = nil, paid: Bool = false
    ) -> PilotCloudConfiguration {
        PilotCloudConfiguration(
            defaults: UserDefaults(suiteName: "hosted-\(UUID().uuidString)") ?? .standard,
            secrets: token ? TokenSecrets() : NoSecrets(), installs: installs.map { Source(isAvailable: $0) },
            isPaid: { paid })
    }

    func testAnInstallThatCanAttestMayReachTheServerWhichDecidesTheRest() {
        XCTAssertTrue(configuration(installs: true).isEntitled)
        XCTAssertTrue(configuration(installs: true).isReady)
    }

    func testWithoutATokenOrAttestationNothingIsSent() {
        XCTAssertFalse(configuration().isEntitled)
        XCTAssertFalse(configuration(installs: false).isReady)
    }

    func testPlotReadingByTheModelNeedsThePilotTokenOrAPayingAttestedInstall() {
        XCTAssertTrue(configuration(token: true).usesHostedPlotReading)
        XCTAssertTrue(configuration(installs: true, paid: true).usesHostedPlotReading)
        XCTAssertFalse(configuration(installs: true, paid: false).usesHostedPlotReading, "a free plot costs no ask")
        XCTAssertFalse(configuration(installs: false, paid: true).usesHostedPlotReading)
        XCTAssertFalse(configuration(paid: true).usesHostedPlotReading)
    }
}
