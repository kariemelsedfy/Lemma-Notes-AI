import Foundation
import XCTest

@testable import ProxyAdmission

final class InstallTrustTests: XCTestCase {
    private static let secret = Data(repeating: 0x42, count: 32)

    private func trust(
        _ authority: TestAttestation, store: any InstallStore = InMemoryInstallStore()
    ) -> InstallTrust {
        InstallTrust(
            verifier: AppAttestVerifier(
                roots: [authority.root], appID: TestAttestation.appID, allowsDevelopment: false,
                now: { TestAttestation.now }),
            challenges: AttestationChallenges(secret: Self.secret, now: { TestAttestation.now }), store: store)
    }

    // MARK: - Challenges

    func testAChallengeIsValidUntilItExpiresAndOnlyForTheSecretThatMadeIt() {
        let issued = AttestationChallenges(secret: Self.secret, lifetime: 300, now: { TestAttestation.now })
        let challenge = issued.issue()
        XCTAssertEqual(challenge.count, AttestationChallenges.length)
        XCTAssertTrue(issued.isValid(challenge))
        let later = AttestationChallenges(
            secret: Self.secret, now: { TestAttestation.now.addingTimeInterval(301) })
        XCTAssertFalse(later.isValid(challenge))
        let otherSecret = AttestationChallenges(secret: Data(repeating: 1, count: 32), now: { TestAttestation.now })
        XCTAssertFalse(otherSecret.isValid(challenge))
    }

    func testATamperedOrTruncatedChallengeIsRefused() {
        let challenges = AttestationChallenges(secret: Self.secret, now: { TestAttestation.now })
        var challenge = challenges.issue()
        XCTAssertFalse(challenges.isValid(challenge.dropLast()))
        XCTAssertFalse(challenges.isValid(Data()))
        challenge[3] ^= 0xFF
        XCTAssertFalse(challenges.isValid(challenge))
    }

    func testTwoChallengesDiffer() {
        let challenges = AttestationChallenges(secret: Self.secret)
        XCTAssertNotEqual(challenges.issue(), challenges.issue())
    }

    // MARK: - Registration and authorization

    func testARegisteredInstallCanBeAuthorizedAndItsCounterAdvances() async throws {
        let authority = try TestAttestation()
        let service = trust(authority)
        let challenge = service.newChallenge()
        let device = try authority.attest(challenge: challenge)
        try await service.register(attestation: device.attestation, challenge: challenge, keyID: device.keyID)

        let body = Data("hello".utf8)
        let first = try await service.authorize(
            keyID: device.keyID, assertion: try TestAttestation.assertion(for: device, clientData: body, counter: 1),
            clientData: body)
        XCTAssertEqual(first.key.counter, 1)
        let second = try await service.authorize(
            keyID: device.keyID, assertion: try TestAttestation.assertion(for: device, clientData: body, counter: 2),
            clientData: body)
        XCTAssertEqual(second.key.counter, 2)
    }

    func testAReplayedAssertionIsRefused() async throws {
        let authority = try TestAttestation()
        let service = trust(authority)
        let challenge = service.newChallenge()
        let device = try authority.attest(challenge: challenge)
        try await service.register(attestation: device.attestation, challenge: challenge, keyID: device.keyID)
        let body = Data("hello".utf8)
        let assertion = try TestAttestation.assertion(for: device, clientData: body, counter: 1)
        try await service.authorize(keyID: device.keyID, assertion: assertion, clientData: body)
        do {
            try await service.authorize(keyID: device.keyID, assertion: assertion, clientData: body)
            XCTFail("a replay was accepted")
        } catch let error as AppAttestError {
            XCTAssertEqual(error, .counterNotIncreased)
        }
    }

    func testAnAttestationCanRegisterOnlyOnce() async throws {
        let authority = try TestAttestation()
        let service = trust(authority)
        let challenge = service.newChallenge()
        let device = try authority.attest(challenge: challenge)
        try await service.register(attestation: device.attestation, challenge: challenge, keyID: device.keyID)
        do {
            try await service.register(attestation: device.attestation, challenge: challenge, keyID: device.keyID)
            XCTFail("registered twice")
        } catch let error as InstallTrustError {
            XCTAssertEqual(error, .alreadyRegistered)
        }
    }

    func testAnAttestationForAChallengeTheServerDidNotIssueIsRefused() async throws {
        let authority = try TestAttestation()
        let service = trust(authority)
        let forged = Data(repeating: 1, count: AttestationChallenges.length)
        let device = try authority.attest(challenge: forged)
        do {
            try await service.register(attestation: device.attestation, challenge: forged, keyID: device.keyID)
            XCTFail("accepted a forged challenge")
        } catch let error as InstallTrustError {
            XCTAssertEqual(error, .invalidChallenge)
        }
    }

    func testAllowanceAndCounterAreWrittenTogetherAndARefusalWritesNothing() async throws {
        let authority = try TestAttestation()
        let store = InMemoryInstallStore()
        let service = trust(authority, store: store)
        let challenge = service.newChallenge()
        let device = try authority.attest(challenge: challenge)
        try await service.register(attestation: device.attestation, challenge: challenge, keyID: device.keyID)
        let body = Data("hello".utf8)

        let record = try await service.authorize(
            keyID: device.keyID, assertion: try TestAttestation.assertion(for: device, clientData: body, counter: 1),
            clientData: body
        ) { try InstallAllowance.reserve(&$0, micros: 4_000, at: TestAttestation.now) }
        XCTAssertEqual(record.tourAsksUsed, 1)
        XCTAssertEqual(record.key.counter, 1)

        for counter in UInt32(2)...3 {
            try await service.authorize(
                keyID: device.keyID,
                assertion: try TestAttestation.assertion(for: device, clientData: body, counter: counter),
                clientData: body
            ) { try InstallAllowance.reserve(&$0, micros: 4_000, at: TestAttestation.now) }
        }
        do {
            try await service.authorize(
                keyID: device.keyID,
                assertion: try TestAttestation.assertion(for: device, clientData: body, counter: 4), clientData: body
            ) { try InstallAllowance.reserve(&$0, micros: 4_000, at: TestAttestation.now) }
            XCTFail("a fourth free ask was allowed")
        } catch let error as AllowanceError {
            XCTAssertEqual(error, .subscriptionRequired)
        }
        let stored = try await store.load(device.keyID)
        XCTAssertEqual(stored?.record.key.counter, 3, "the refused request did not advance the counter")
        XCTAssertEqual(stored?.record.tourAsksUsed, 3)
    }

    func testUpdateAppliesAChangeWithoutAnAssertion() async throws {
        let authority = try TestAttestation()
        let service = trust(authority)
        let challenge = service.newChallenge()
        let device = try authority.attest(challenge: challenge)
        try await service.register(attestation: device.attestation, challenge: challenge, keyID: device.keyID)
        let updated = try await service.update(keyID: device.keyID) { $0.plan = .premium }
        XCTAssertEqual(updated.plan, .premium)
        do {
            try await service.update(keyID: Data(repeating: 9, count: 32)) { _ in }
            XCTFail("updated an unknown install")
        } catch let error as InstallTrustError {
            XCTAssertEqual(error, .unknownInstall)
        }
    }

    func testAnUnknownInstallIsRefused() async throws {
        let authority = try TestAttestation()
        let service = trust(authority)
        let device = try authority.attest(challenge: service.newChallenge())
        do {
            try await service.authorize(
                keyID: device.keyID, assertion: Data(), clientData: Data())
            XCTFail("authorized an unknown install")
        } catch let error as InstallTrustError {
            XCTAssertEqual(error, .unknownInstall)
        }
    }

    func testTwoConcurrentRequestsWithTheSameCounterAdmitOnlyOne() async throws {
        let authority = try TestAttestation()
        let service = trust(authority)
        let challenge = service.newChallenge()
        let device = try authority.attest(challenge: challenge)
        try await service.register(attestation: device.attestation, challenge: challenge, keyID: device.keyID)
        let body = Data("x".utf8)
        let assertion = try TestAttestation.assertion(for: device, clientData: body, counter: 1)

        let outcomes = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    (try? await service.authorize(keyID: device.keyID, assertion: assertion, clientData: body)) != nil
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        XCTAssertEqual(outcomes.filter { $0 }.count, 1)
    }
}

final class MiniCBORTests: XCTestCase {
    func testItReadsTheShapesAppAttestUses() {
        let encoded = Data(
            CBORWriter.map([
                ("a", CBORWriter.bytes(Data([1, 2]))),
                ("b", CBORWriter.array([CBORWriter.text("x"), CBORWriter.head(0, 300)])),
            ]))
        let value = CBORDecoder.decode(encoded)?.map
        XCTAssertEqual(value?["a"]?.bytes, Data([1, 2]))
        XCTAssertEqual(value?["b"]?.array, [.text("x"), .unsigned(300)])
    }

    func testItRefusesWhatItDoesNotUnderstand() {
        let cases: [(String, [UInt8])] = [
            ("indefinite array", [0x9F, 0x01, 0xFF]),
            ("tag", [0xC1, 0x01]),
            ("float", [0xFB, 0, 0, 0, 0, 0, 0, 0, 0]),
            ("negative integer", [0x20]),
            ("trailing bytes", [0x01, 0x02]),
            ("truncated string", [0x45, 1, 2]),
            ("huge length", [0x5B, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]),
            ("non-text key", [0xA1, 0x01, 0x02]),
            ("duplicate key", [0xA2, 0x61, 0x61, 0x01, 0x61, 0x61, 0x02]),
        ]
        for (name, bytes) in cases { XCTAssertNil(CBORDecoder.decode(Data(bytes)), name) }
    }

    func testItRefusesDeepNestingAndOversizedInput() {
        let deep = Data(repeating: 0x81, count: 20) + Data([0x00])
        XCTAssertNil(CBORDecoder.decode(deep))
        XCTAssertNil(CBORDecoder.decode(Data(repeating: 0, count: CBORDecoder.maximumInputBytes + 1)))
    }
}
