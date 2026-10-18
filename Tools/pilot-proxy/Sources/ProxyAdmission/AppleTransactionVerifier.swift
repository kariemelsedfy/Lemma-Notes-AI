import Crypto
import Foundation
import SwiftASN1
import X509

/// What a verified App Store transaction says about a subscription.
public struct VerifiedTransaction: Equatable, Sendable {
    public let bundleID: String
    public let productID: String
    public let originalTransactionID: String
    public let expiresAt: Date?
    public let isIntroductoryTrial: Bool
    public let revokedAt: Date?
    public let environment: String
}

public enum TransactionVerificationError: Error, Equatable, Sendable {
    /// Not a three-part JWS, or a part that is not what it should be.
    case malformed
    /// Anything but ES256 (including `none`, which must never be accepted).
    case unsupportedAlgorithm
    /// The `x5c` chain does not lead to a trusted Apple root, is expired, or lacks Apple's marker extensions.
    case untrustedChain
    case badSignature
    case wrongBundle
    case wrongProduct
    case wrongEnvironment
}

/// Verifies a StoreKit 2 signed transaction (the JWS Apple signs) without calling Apple (ADR-031).
///
/// The header's `x5c` carries leaf, intermediate and root. Our own trust anchors decide the root, so the root Apple
/// sent is ignored; the chain must validate to one of them, the leaf and intermediate must carry Apple's marker
/// extensions (so a certificate Apple issued for something else cannot sign a transaction), and the ES256 signature
/// must verify under the leaf's key. Only then are the claims read, and the bundle, product and environment checked.
public struct AppleTransactionVerifier: Sendable {
    /// Apple's markers: the leaf is a "Mac App Store Receipt Signing" certificate, the intermediate the
    /// "Worldwide Developer Relations" one for it.
    public static let leafMarkerOID = "1.2.840.113635.100.6.11.1"
    public static let intermediateMarkerOID = "1.2.840.113635.100.6.2.1"

    private let roots: [Certificate]
    private let bundleID: String
    private let productIDs: Set<String>
    private let environments: Set<String>
    private let leafMarker: String
    private let intermediateMarker: String
    private let now: @Sendable () -> Date

    public init(
        roots: [Certificate],
        bundleID: String,
        productIDs: Set<String>,
        environments: Set<String> = ["Production", "Sandbox"],
        leafMarker: String = AppleTransactionVerifier.leafMarkerOID,
        intermediateMarker: String = AppleTransactionVerifier.intermediateMarkerOID,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.roots = roots
        self.bundleID = bundleID
        self.productIDs = productIDs
        self.environments = environments
        self.leafMarker = leafMarker
        self.intermediateMarker = intermediateMarker
        self.now = now
    }

    /// The pilot's verifier: Apple's real root, this app, these products. `Xcode` (local StoreKit testing) is not
    /// a production environment and is only allowed when `allowsXcodeEnvironment` is set.
    public static func standard(
        bundleID: String, productIDs: Set<String>, allowsXcodeEnvironment: Bool = false
    ) throws -> AppleTransactionVerifier {
        let root = try Certificate(derEncoded: Array(AppleRoots.rootCAG3))
        return AppleTransactionVerifier(
            roots: [root], bundleID: bundleID, productIDs: productIDs,
            environments: allowsXcodeEnvironment ? ["Production", "Sandbox", "Xcode"] : ["Production", "Sandbox"])
    }

    public func verify(_ jws: String) async throws -> VerifiedTransaction {
        let parts = jws.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else { throw TransactionVerificationError.malformed }
        guard let headerData = Base64URL.decode(parts[0]), let payloadData = Base64URL.decode(parts[1]),
            let signature = Base64URL.decode(parts[2])
        else { throw TransactionVerificationError.malformed }

        let header = try decode(Header.self, from: headerData)
        guard header.alg == "ES256" else { throw TransactionVerificationError.unsupportedAlgorithm }
        let leaf = try await trustedLeaf(from: header.x5c)

        guard let key = P256.Signing.PublicKey(leaf.publicKey),
            let ecdsa = try? P256.Signing.ECDSASignature(rawRepresentation: signature),
            key.isValidSignature(ecdsa, for: Data("\(parts[0]).\(parts[1])".utf8))
        else { throw TransactionVerificationError.badSignature }

        return try claims(from: payloadData)
    }

    // MARK: - Chain

    private func trustedLeaf(from x5c: [String]) async throws -> Certificate {
        guard x5c.count >= 2, x5c.count <= 4 else { throw TransactionVerificationError.untrustedChain }
        let certificates: [Certificate]
        do {
            certificates = try x5c.map {
                guard let der = Data(base64Encoded: $0) else { throw TransactionVerificationError.malformed }
                return try Certificate(derEncoded: Array(der))
            }
        } catch { throw TransactionVerificationError.malformed }
        let leaf = certificates[0]
        let intermediates = Array(certificates.dropFirst())

        var verifier = Verifier(rootCertificates: CertificateStore(roots)) {
            RFC5280Policy(validationTime: self.now())
        }
        let result = await verifier.validate(
            leafCertificate: leaf, intermediates: CertificateStore(intermediates))
        guard case .validCertificate(let chain) = result, chain.count >= 3 else {
            throw TransactionVerificationError.untrustedChain
        }
        // chain is leaf ... root: the leaf and the certificate that issued it must carry Apple's markers.
        guard has(extension: leafMarker, in: chain[0]), has(extension: intermediateMarker, in: chain[1]) else {
            throw TransactionVerificationError.untrustedChain
        }
        return leaf
    }

    private func has(extension oid: String, in certificate: Certificate) -> Bool {
        certificate.extensions.contains { String(describing: $0.oid) == oid }
    }

    // MARK: - Claims

    private func claims(from data: Data) throws -> VerifiedTransaction {
        let payload = try decode(Payload.self, from: data)
        guard payload.bundleId == bundleID else { throw TransactionVerificationError.wrongBundle }
        guard productIDs.contains(payload.productId) else { throw TransactionVerificationError.wrongProduct }
        guard environments.contains(payload.environment) else { throw TransactionVerificationError.wrongEnvironment }
        return VerifiedTransaction(
            bundleID: payload.bundleId,
            productID: payload.productId,
            originalTransactionID: payload.originalTransactionId,
            expiresAt: payload.expiresDate.map { Date(timeIntervalSince1970: $0 / 1000) },
            isIntroductoryTrial: payload.offerType == 1 && payload.offerDiscountType == "FREE_TRIAL",
            revokedAt: payload.revocationDate.map { Date(timeIntervalSince1970: $0 / 1000) },
            environment: payload.environment)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch { throw TransactionVerificationError.malformed }
    }

    private struct Header: Decodable {
        let alg: String
        let x5c: [String]
    }

    private struct Payload: Decodable {
        let bundleId: String
        let productId: String
        let originalTransactionId: String
        let environment: String
        let expiresDate: Double?
        let revocationDate: Double?
        let offerType: Int?
        let offerDiscountType: String?
    }
}

enum Base64URL {
    static func decode(_ text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
