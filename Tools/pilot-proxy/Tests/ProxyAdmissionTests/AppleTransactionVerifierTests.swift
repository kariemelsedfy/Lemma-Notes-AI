import Crypto
import Foundation
import XCTest

@testable import ProxyAdmission

final class AppleTransactionVerifierTests: XCTestCase {
    private static let bundle = "edu.bowdoin.margin"
    private static let product = "lemmanotesai.premium.yearly"
    private static let now = TestPKI.epoch.addingTimeInterval(86_400)

    private static let liveEnvironments: Set<String> = ["Production", "Sandbox"]

    private func verifier(_ pki: TestPKI, environments: Set<String> = liveEnvironments) -> AppleTransactionVerifier {
        AppleTransactionVerifier(
            roots: [pki.root], bundleID: Self.bundle, productIDs: [Self.product], environments: environments,
            now: { Self.now })
    }

    private func claims(
        bundle: String = AppleTransactionVerifierTests.bundle, product: String = AppleTransactionVerifierTests.product,
        environment: String = "Production", expires: TimeInterval = 1_700_000_000_000 + 7 * 86_400_000,
        trial: Bool = false, revoked: Bool = false
    ) -> [String: Any] {
        var result: [String: Any] = [
            "bundleId": bundle, "productId": product, "originalTransactionId": "1000000123456789",
            "environment": environment, "expiresDate": expires,
        ]
        if trial {
            result["offerType"] = 1
            result["offerDiscountType"] = "FREE_TRIAL"
        }
        if revoked { result["revocationDate"] = 1_700_000_500_000 }
        return result
    }

    func testAGenuineTransactionVerifiesAndYieldsItsClaims() async throws {
        let pki = try TestPKI()
        let jws = try pki.signedTransaction(claims: claims(trial: true))
        let verified = try await verifier(pki).verify(jws)
        XCTAssertEqual(verified.productID, Self.product)
        XCTAssertEqual(verified.bundleID, Self.bundle)
        XCTAssertTrue(verified.isIntroductoryTrial)
        XCTAssertEqual(verified.originalTransactionID, "1000000123456789")
        XCTAssertEqual(verified.environment, "Production")
        XCTAssertNil(verified.revokedAt)
        XCTAssertNotNil(verified.expiresAt)
    }

    func testARevokedTransactionIsReportedAsRevoked() async throws {
        let pki = try TestPKI()
        let verified = try await verifier(pki).verify(try pki.signedTransaction(claims: claims(revoked: true)))
        XCTAssertNotNil(verified.revokedAt)
    }

    func testTheRootApplePutsInTheHeaderIsIgnoredAndOursDecides() async throws {
        let signer = try TestPKI()
        let trusted = try TestPKI()
        let jws = try signer.signedTransaction(claims: claims())
        await assertFails(.untrustedChain, try await verifier(trusted).verify(jws))
    }

    func testAChainWithoutTheRootStillVerifiesAgainstOurRoot() async throws {
        let pki = try TestPKI()
        let jws = try pki.signedTransaction(claims: claims(), x5c: try pki.x5c(includingRoot: false))
        _ = try await verifier(pki).verify(jws)
    }

    func testACertificateWithoutAppleMarkerExtensionsCannotSign() async throws {
        for pki in [try TestPKI(leafMarker: nil), try TestPKI(intermediateMarker: nil)] {
            let jws = try pki.signedTransaction(claims: claims())
            await assertFails(.untrustedChain, try await verifier(pki).verify(jws))
        }
    }

    func testAnExpiredLeafIsRefused() async throws {
        let pki = try TestPKI(leafValidUntil: TestPKI.epoch.addingTimeInterval(3_600))
        let jws = try pki.signedTransaction(claims: claims())
        await assertFails(.untrustedChain, try await verifier(pki).verify(jws))
    }

    func testASignatureFromAnotherKeyIsRefused() async throws {
        let pki = try TestPKI()
        let jws = try pki.signedTransaction(claims: claims(), signingKey: P256.Signing.PrivateKey())
        await assertFails(.badSignature, try await verifier(pki).verify(jws))
    }

    func testTamperedClaimsBreakTheSignature() async throws {
        let pki = try TestPKI()
        let jws = try pki.signedTransaction(claims: claims(product: Self.product))
        var parts = jws.split(separator: ".").map(String.init)
        let forged = try JSONSerialization.data(withJSONObject: claims(expires: 9_999_999_999_999))
        parts[1] = Base64URL.encode(forged)
        await assertFails(.badSignature, try await verifier(pki).verify(parts.joined(separator: ".")))
    }

    func testOnlyES256IsAccepted() async throws {
        let pki = try TestPKI()
        for algorithm in ["none", "HS256", "RS256"] {
            let jws = try pki.signedTransaction(claims: claims(), algorithm: algorithm)
            await assertFails(.unsupportedAlgorithm, try await verifier(pki).verify(jws))
        }
    }

    func testWrongBundleProductAndEnvironmentAreRefused() async throws {
        let pki = try TestPKI()
        let subject = verifier(pki)
        await assertFails(
            .wrongBundle, try await subject.verify(try pki.signedTransaction(claims: claims(bundle: "other.app"))))
        await assertFails(
            .wrongProduct, try await subject.verify(try pki.signedTransaction(claims: claims(product: "other.product")))
        )
        await assertFails(
            .wrongEnvironment, try await subject.verify(try pki.signedTransaction(claims: claims(environment: "Xcode")))
        )
        _ = try await verifier(pki, environments: ["Xcode"]).verify(
            try pki.signedTransaction(claims: claims(environment: "Xcode")))
    }

    func testMalformedInputIsRefusedNotCrashed() async throws {
        let pki = try TestPKI()
        for garbage in ["", "a.b", "a.b.c.d", "...", "not a jws", "e30.e30.e30"] {
            do {
                _ = try await verifier(pki).verify(garbage)
                XCTFail("accepted \(garbage)")
            } catch is TransactionVerificationError {}
        }
    }

    func testTheBundledAppleRootIsTheOneApplePublishes() throws {
        let digest = SHA256.hash(data: AppleRoots.rootCAG3).map { String(format: "%02X", $0) }.joined()
        XCTAssertEqual(digest, AppleRoots.rootCAG3SHA256)
        _ = try AppleTransactionVerifier.standard(bundleID: Self.bundle, productIDs: [Self.product])
    }

    private func assertFails(
        _ expected: TransactionVerificationError, _ expression: @autoclosure () async throws -> some Any,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as TransactionVerificationError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected \(error)", file: file, line: line)
        }
    }
}
