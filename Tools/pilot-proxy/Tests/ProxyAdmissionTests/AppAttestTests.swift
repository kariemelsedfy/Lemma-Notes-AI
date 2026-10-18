import Crypto
import Foundation
import XCTest

@testable import ProxyAdmission

final class AppAttestTests: XCTestCase {
    private static let challenge = Data((0..<56).map { UInt8($0) })

    private func verifier(
        _ authority: TestAttestation, appID: String = TestAttestation.appID, allowsDevelopment: Bool = false
    ) -> AppAttestVerifier {
        AppAttestVerifier(
            roots: [authority.root], appID: appID, allowsDevelopment: allowsDevelopment, now: { TestAttestation.now })
    }

    // MARK: - Attestation

    func testAGenuineAttestationYieldsTheKey() async throws {
        let authority = try TestAttestation()
        let device = try authority.attest(challenge: Self.challenge)
        let key = try await verifier(authority).verifyAttestation(
            device.attestation, challenge: Self.challenge, keyID: device.keyID)
        XCTAssertEqual(key.keyID, device.keyID)
        XCTAssertEqual(key.publicKeyX963, device.key.publicKey.x963Representation)
        XCTAssertEqual(key.counter, 0)
    }

    func testEachBrokenAttestationIsRefusedForItsOwnReason() async throws {
        let authority = try TestAttestation()
        let subject = verifier(authority)
        let cases: [(String, TestAttestation.Device, AppAttestError)] = [
            (
                "another challenge", try authority.attest(challenge: Self.challenge, nonceChallenge: Data([9])),
                .badNonce
            ),
            ("no nonce extension", try authority.attest(challenge: Self.challenge, includeNonce: false), .badNonce),
            (
                "another app",
                try authority.attest(challenge: Self.challenge, appID: "OTHER.app"), .wrongApp
            ),
            ("non-zero counter", try authority.attest(challenge: Self.challenge, counter: 5), .nonZeroCounter),
            (
                "development environment",
                try authority.attest(challenge: Self.challenge, aaguid: TestAttestation.developmentAAGUID),
                .wrongEnvironment
            ),
            (
                "unknown environment",
                try authority.attest(challenge: Self.challenge, aaguid: Data(repeating: 7, count: 16)),
                .wrongEnvironment
            ),
            (
                "credential id differs",
                try authority.attest(challenge: Self.challenge, credentialID: Data(repeating: 1, count: 32)),
                .keyIDMismatch
            ),
            (
                "key id differs",
                try authority.attest(challenge: Self.challenge, claimedKeyID: Data(repeating: 2, count: 32)),
                .keyIDMismatch
            ),
        ]
        for (name, device, expected) in cases {
            do {
                _ = try await subject.verifyAttestation(
                    device.attestation, challenge: Self.challenge, keyID: device.keyID)
                XCTFail("\(name) was accepted")
            } catch let error as AppAttestError {
                XCTAssertEqual(error, expected, name)
            }
        }
    }

    func testTheDevelopmentEnvironmentIsAcceptedOnlyWhenAllowed() async throws {
        let authority = try TestAttestation()
        let device = try authority.attest(challenge: Self.challenge, aaguid: TestAttestation.developmentAAGUID)
        _ = try await verifier(authority, allowsDevelopment: true).verifyAttestation(
            device.attestation, challenge: Self.challenge, keyID: device.keyID)
    }

    func testAChainFromAnotherAuthorityIsRefused() async throws {
        let device = try TestAttestation().attest(challenge: Self.challenge)
        let other = try TestAttestation()
        do {
            _ = try await verifier(other).verifyAttestation(
                device.attestation, challenge: Self.challenge, keyID: device.keyID)
            XCTFail("accepted a foreign chain")
        } catch let error as AppAttestError {
            XCTAssertEqual(error, .untrustedChain)
        }
    }

    func testMalformedAttestationsAreRefusedNotCrashed() async throws {
        let authority = try TestAttestation()
        let wrongFormat = Data(CBORWriter.map([("fmt", CBORWriter.text("packed"))]))
        for garbage in [Data(), Data([0xFF]), Data(repeating: 0, count: 40), wrongFormat] {
            do {
                _ = try await verifier(authority).verifyAttestation(
                    garbage, challenge: Self.challenge, keyID: Data(repeating: 0, count: 32))
                XCTFail("accepted garbage")
            } catch is AppAttestError {}
        }
    }

    func testTheBundledAppAttestRootIsTheOneApplePublishes() throws {
        let digest = SHA256.hash(data: AppleRoots.appAttestRoot).map { String(format: "%02X", $0) }.joined()
        XCTAssertEqual(digest, AppleRoots.appAttestRootSHA256)
        _ = try AppAttestVerifier.standard(appID: TestAttestation.appID, allowsDevelopment: false)
    }

    // MARK: - Assertion

    private func registered(_ authority: TestAttestation) async throws -> (TestAttestation.Device, AttestedKey) {
        let device = try authority.attest(challenge: Self.challenge)
        let key = try await verifier(authority).verifyAttestation(
            device.attestation, challenge: Self.challenge, keyID: device.keyID)
        return (device, key)
    }

    func testAnAssertionOverTheRequestBodyVerifiesAndReturnsItsCounter() async throws {
        let authority = try TestAttestation()
        let (device, key) = try await registered(authority)
        let body = Data("request body".utf8)
        let assertion = try TestAttestation.assertion(for: device, clientData: body, counter: 1)
        XCTAssertEqual(try verifier(authority).verifyAssertion(assertion, clientData: body, key: key), 1)
    }

    func testAnAssertionIsBoundToItsBodyKeyAndApp() async throws {
        let authority = try TestAttestation()
        let (device, key) = try await registered(authority)
        let body = Data("request body".utf8)
        let subject = verifier(authority)
        let cases: [(Data, Data, AppAttestError)] = [
            (
                try TestAttestation.assertion(for: device, clientData: body, counter: 1), Data("another body".utf8),
                .badSignature
            ),
            (
                try TestAttestation.assertion(
                    for: device, clientData: body, counter: 1, signingKey: P256.Signing.PrivateKey()), body,
                .badSignature
            ),
            (
                try TestAttestation.assertion(for: device, clientData: body, counter: 1, appID: "OTHER.app"), body,
                .wrongApp
            ),
        ]
        for (assertion, data, expected) in cases {
            XCTAssertThrowsError(try subject.verifyAssertion(assertion, clientData: data, key: key)) {
                XCTAssertEqual($0 as? AppAttestError, expected)
            }
        }
    }

    func testAReplayedOrLowerCounterIsRefused() async throws {
        let authority = try TestAttestation()
        let (device, key) = try await registered(authority)
        let body = Data("body".utf8)
        let advanced = AttestedKey(keyID: key.keyID, publicKeyX963: key.publicKeyX963, counter: 3)
        for counter in [UInt32(0), 2, 3] {
            let assertion = try TestAttestation.assertion(for: device, clientData: body, counter: counter)
            XCTAssertThrowsError(try verifier(authority).verifyAssertion(assertion, clientData: body, key: advanced)) {
                XCTAssertEqual($0 as? AppAttestError, .counterNotIncreased)
            }
        }
    }

    func testMalformedAssertionsAreRefused() async throws {
        let authority = try TestAttestation()
        let (_, key) = try await registered(authority)
        for garbage in [Data(), Data([1, 2, 3]), Data(CBORWriter.map([("signature", CBORWriter.bytes(Data([1])))]))] {
            XCTAssertThrowsError(try verifier(authority).verifyAssertion(garbage, clientData: Data(), key: key))
        }
    }
}
