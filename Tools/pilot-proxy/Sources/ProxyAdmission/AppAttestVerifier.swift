import Crypto
import Foundation
import X509

/// An install Apple vouched for: its key, and the highest assertion counter seen so far.
public struct AttestedKey: Equatable, Sendable {
    /// SHA-256 of the public key, as App Attest names the key.
    public let keyID: Data
    /// The key as an uncompressed X9.63 point (65 bytes).
    public let publicKeyX963: Data
    public let counter: UInt32

    public init(keyID: Data, publicKeyX963: Data, counter: UInt32) {
        self.keyID = keyID
        self.publicKeyX963 = publicKeyX963
        self.counter = counter
    }
}

public enum AppAttestError: Error, Equatable, Sendable {
    case malformed
    case unsupportedFormat
    case untrustedChain
    case badNonce
    case keyIDMismatch
    case wrongApp
    case nonZeroCounter
    case wrongEnvironment
    case badSignature
    case counterNotIncreased
}

/// Verifies Apple App Attest attestations and assertions (ADR-031), following Apple's "Validating apps that connect
/// to your server": the attestation proves a key lives in a genuine app's Secure Enclave, and each later assertion
/// proves a request was signed by that key.
///
/// **Not yet exercised against Apple's real output.** Everything is tested against synthesized objects built from the
/// documented format; the first real attestation (needs a paid-membership build on a device) is the check that the
/// documented format and this code agree. In particular the assertion signature is verified as ECDSA-SHA256 over
/// `authenticatorData || SHA256(clientData)`.
public struct AppAttestVerifier: Sendable {
    /// The extension in the credential certificate that carries the nonce.
    public static let nonceOID = "1.2.840.113635.100.8.2"
    private static let developmentAAGUID = Data("appattestdevelop".utf8)
    private static let productionAAGUID = Data("appattest".utf8) + Data(repeating: 0, count: 7)

    private let roots: [Certificate]
    private let appIDHash: Data
    private let allowsDevelopment: Bool
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - appID: `TEAMID.bundleid`, which App Attest hashes into every attestation and assertion.
    ///   - allowsDevelopment: accept the sandbox environment (`appattestdevelop`) as well as production.
    public init(
        roots: [Certificate], appID: String, allowsDevelopment: Bool, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.roots = roots
        self.appIDHash = Data(SHA256.hash(data: Data(appID.utf8)))
        self.allowsDevelopment = allowsDevelopment
        self.now = now
    }

    public static func standard(appID: String, allowsDevelopment: Bool) throws -> AppAttestVerifier {
        let root = try Certificate(derEncoded: Array(AppleRoots.appAttestRoot))
        return AppAttestVerifier(roots: [root], appID: appID, allowsDevelopment: allowsDevelopment)
    }

    // MARK: - Attestation

    /// The key the attestation vouches for. `challenge` is the one the server issued for this attempt.
    public func verifyAttestation(_ attestation: Data, challenge: Data, keyID: Data) async throws -> AttestedKey {
        guard let object = CBORDecoder.decode(attestation)?.map,
            object["fmt"]?.text == "apple-appattest",
            let statement = object["attStmt"]?.map,
            let authData = object["authData"]?.bytes,
            let x5c = statement["x5c"]?.array?.compactMap(\.bytes), x5c.count == 2
        else { throw AppAttestError.malformed }

        let certificates: [Certificate]
        do { certificates = try x5c.map { try Certificate(derEncoded: Array($0)) } } catch {
            throw AppAttestError.malformed
        }
        let credential = certificates[0]
        try await verifyChain(credential: credential, intermediate: certificates[1])

        // The nonce binds this attestation to this challenge and this authenticator data.
        let nonce = Data(SHA256.hash(data: authData + Data(SHA256.hash(data: challenge))))
        guard hasNonce(nonce, in: credential) else { throw AppAttestError.badNonce }

        // The key id is the hash of the credential's public key.
        guard let publicKey = P256.Signing.PublicKey(credential.publicKey) else { throw AppAttestError.malformed }
        let x963 = publicKey.x963Representation
        guard Data(SHA256.hash(data: x963)) == keyID else { throw AppAttestError.keyIDMismatch }

        let parsed = try parseAttestationAuthData(authData)
        guard parsed.rpIDHash == appIDHash else { throw AppAttestError.wrongApp }
        guard parsed.counter == 0 else { throw AppAttestError.nonZeroCounter }
        guard parsed.credentialID == keyID else { throw AppAttestError.keyIDMismatch }
        switch parsed.aaguid {
        case Self.productionAAGUID: break
        case Self.developmentAAGUID where allowsDevelopment: break
        default: throw AppAttestError.wrongEnvironment
        }
        return AttestedKey(keyID: keyID, publicKeyX963: x963, counter: 0)
    }

    private func verifyChain(credential: Certificate, intermediate: Certificate) async throws {
        var verifier = Verifier(rootCertificates: CertificateStore(roots)) {
            RFC5280Policy(validationTime: self.now())
        }
        let result = await verifier.validate(
            leafCertificate: credential, intermediates: CertificateStore([intermediate]))
        guard case .validCertificate = result else { throw AppAttestError.untrustedChain }
    }

    /// The extension value is `SEQUENCE { [1] { OCTET STRING nonce } }`; compared byte for byte.
    private func hasNonce(_ nonce: Data, in certificate: Certificate) -> Bool {
        let expected: [UInt8] = [0x30, 0x24, 0xA1, 0x22, 0x04, 0x20] + Array(nonce)
        return certificate.extensions.contains {
            String(describing: $0.oid) == Self.nonceOID && Array($0.value) == expected
        }
    }

    private struct AuthData {
        let rpIDHash: Data
        let counter: UInt32
        let aaguid: Data
        let credentialID: Data
    }

    private func parseAttestationAuthData(_ data: Data) throws -> AuthData {
        let bytes = [UInt8](data)
        guard bytes.count >= 55 else { throw AppAttestError.malformed }
        let credentialLength = Int(bytes[53]) << 8 | Int(bytes[54])
        guard bytes.count >= 55 + credentialLength else { throw AppAttestError.malformed }
        return AuthData(
            rpIDHash: Data(bytes[0..<32]), counter: Self.counter(in: bytes), aaguid: Data(bytes[37..<53]),
            credentialID: Data(bytes[55..<55 + credentialLength]))
    }

    private static func counter(in bytes: [UInt8]) -> UInt32 {
        bytes[33..<37].reduce(0) { ($0 << 8) | UInt32($1) }
    }

    // MARK: - Assertion

    /// The assertion's counter, once the request it signs is proven to come from `key` and the counter has risen.
    /// `clientData` is exactly what the app hashed when it asked for the assertion (the request body).
    public func verifyAssertion(_ assertion: Data, clientData: Data, key: AttestedKey) throws -> UInt32 {
        guard let object = CBORDecoder.decode(assertion)?.map,
            let signature = object["signature"]?.bytes,
            let authData = object["authenticatorData"]?.bytes,
            authData.count >= 37
        else { throw AppAttestError.malformed }
        let bytes = [UInt8](authData)
        guard Data(bytes[0..<32]) == appIDHash else { throw AppAttestError.wrongApp }

        guard let publicKey = try? P256.Signing.PublicKey(x963Representation: key.publicKeyX963),
            let ecdsa = try? P256.Signing.ECDSASignature(derRepresentation: signature),
            publicKey.isValidSignature(ecdsa, for: authData + Data(SHA256.hash(data: clientData)))
        else { throw AppAttestError.badSignature }

        let counter = Self.counter(in: bytes)
        guard counter > key.counter else { throw AppAttestError.counterNotIncreased }
        return counter
    }
}
