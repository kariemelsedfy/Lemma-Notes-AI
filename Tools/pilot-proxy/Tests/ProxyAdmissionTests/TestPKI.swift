import Crypto
import Foundation
import SwiftASN1
import X509

@testable import ProxyAdmission

/// A throwaway certificate authority shaped like Apple's: root, intermediate, leaf, each with the marker extensions
/// the real chain carries, so the verifier's checks can be tested without Apple's keys.
struct TestPKI {
    let rootKey: P256.Signing.PrivateKey
    let intermediateKey: P256.Signing.PrivateKey
    let leafKey: P256.Signing.PrivateKey
    let root: Certificate
    let intermediate: Certificate
    let leaf: Certificate

    static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    init(
        leafMarker: String? = AppleTransactionVerifier.leafMarkerOID,
        intermediateMarker: String? = AppleTransactionVerifier.intermediateMarkerOID,
        leafValidUntil: Date = TestPKI.epoch.addingTimeInterval(86_400 * 365),
        dropIntermediateCA: Bool = false
    ) throws {
        let rootKey = P256.Signing.PrivateKey()
        let intermediateKey = P256.Signing.PrivateKey()
        let leafKey = P256.Signing.PrivateKey()
        let rootName = try DistinguishedName { CommonName("Test Root CA") }
        let intermediateName = try DistinguishedName { CommonName("Test Intermediate") }
        let leafName = try DistinguishedName { CommonName("Test Leaf") }
        let start = Self.epoch.addingTimeInterval(-86_400)
        let end = Self.epoch.addingTimeInterval(86_400 * 3_650)

        root = try Certificate(
            version: .v3, serialNumber: Certificate.SerialNumber(), publicKey: .init(rootKey.publicKey),
            notValidBefore: start, notValidAfter: end, issuer: rootName, subject: rootName,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
                Critical(KeyUsage(keyCertSign: true))
            },
            issuerPrivateKey: .init(rootKey))

        var intermediateExtensions = try Certificate.Extensions {
            if !dropIntermediateCA {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
                Critical(KeyUsage(keyCertSign: true))
            }
        }
        if let intermediateMarker { try intermediateExtensions.append(Self.marker(intermediateMarker)) }
        intermediate = try Certificate(
            version: .v3, serialNumber: Certificate.SerialNumber(), publicKey: .init(intermediateKey.publicKey),
            notValidBefore: start, notValidAfter: end, issuer: rootName, subject: intermediateName,
            signatureAlgorithm: .ecdsaWithSHA256, extensions: intermediateExtensions,
            issuerPrivateKey: .init(rootKey))

        var leafExtensions = try Certificate.Extensions {
            Critical(BasicConstraints.notCertificateAuthority)
            Critical(KeyUsage(digitalSignature: true))
        }
        if let leafMarker { try leafExtensions.append(Self.marker(leafMarker)) }
        leaf = try Certificate(
            version: .v3, serialNumber: Certificate.SerialNumber(), publicKey: .init(leafKey.publicKey),
            notValidBefore: start, notValidAfter: leafValidUntil, issuer: intermediateName, subject: leafName,
            signatureAlgorithm: .ecdsaWithSHA256, extensions: leafExtensions,
            issuerPrivateKey: .init(intermediateKey))

        self.rootKey = rootKey
        self.intermediateKey = intermediateKey
        self.leafKey = leafKey
    }

    private static func marker(_ oid: String) throws -> Certificate.Extension {
        Certificate.Extension(
            oid: try ASN1ObjectIdentifier(dotRepresentation: oid), critical: false, value: [0x05, 0x00])
    }

    func x5c(includingRoot: Bool = true) throws -> [String] {
        var chain = [leaf, intermediate]
        if includingRoot { chain.append(root) }
        return try chain.map { certificate in
            var serializer = DER.Serializer()
            try serializer.serialize(certificate)
            return Data(serializer.serializedBytes).base64EncodedString()
        }
    }

    /// A signed transaction as StoreKit would hand it over.
    func signedTransaction(
        claims: [String: Any], algorithm: String = "ES256", x5c: [String]? = nil,
        signingKey: P256.Signing.PrivateKey? = nil
    ) throws -> String {
        let header: [String: Any] = ["alg": algorithm, "x5c": try x5c ?? self.x5c()]
        let headerPart = Base64URL.encode(try JSONSerialization.data(withJSONObject: header))
        let payloadPart = Base64URL.encode(try JSONSerialization.data(withJSONObject: claims))
        let signingInput = Data("\(headerPart).\(payloadPart)".utf8)
        let signature = try (signingKey ?? leafKey).signature(for: signingInput)
        return "\(headerPart).\(payloadPart).\(Base64URL.encode(signature.rawRepresentation))"
    }
}
