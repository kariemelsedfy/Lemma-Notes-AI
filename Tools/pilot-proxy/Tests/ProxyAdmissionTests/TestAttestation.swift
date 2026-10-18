import Crypto
import Foundation
import SwiftASN1
import X509

@testable import ProxyAdmission

/// A minimal CBOR writer, only for building test attestations.
enum CBORWriter {
    static func head(_ major: UInt8, _ value: Int) -> [UInt8] {
        let tag = major << 5
        switch value {
        case ..<24: return [tag | UInt8(value)]
        case ..<256: return [tag | 24, UInt8(value)]
        case ..<65_536: return [tag | 25, UInt8(value >> 8), UInt8(value & 0xFF)]
        default: return [tag | 26] + (0..<4).map { UInt8((value >> (8 * (3 - $0))) & 0xFF) }
        }
    }

    static func text(_ value: String) -> [UInt8] { head(3, value.utf8.count) + Array(value.utf8) }
    static func bytes(_ value: Data) -> [UInt8] { head(2, value.count) + Array(value) }
    static func array(_ items: [[UInt8]]) -> [UInt8] { head(4, items.count) + items.flatMap { $0 } }
    static func map(_ entries: [(String, [UInt8])]) -> [UInt8] {
        head(5, entries.count) + entries.flatMap { text($0.0) + $0.1 }
    }
}

/// A throwaway App Attest authority and device: root, intermediate, a credential certificate carrying the nonce, and
/// the key that signs assertions.
struct TestAttestation {
    static let appID = "TEAM123456.edu.bowdoin.margin"
    static let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    static let now = epoch.addingTimeInterval(86_400)

    let rootKey = P256.Signing.PrivateKey()
    let intermediateKey = P256.Signing.PrivateKey()
    let root: Certificate
    let intermediate: Certificate
    let rootName: DistinguishedName
    let intermediateName: DistinguishedName

    init() throws {
        rootName = try DistinguishedName { CommonName("Test App Attestation Root") }
        intermediateName = try DistinguishedName { CommonName("Test App Attestation CA") }
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
        intermediate = try Certificate(
            version: .v3, serialNumber: Certificate.SerialNumber(), publicKey: .init(intermediateKey.publicKey),
            notValidBefore: start, notValidAfter: end, issuer: rootName, subject: intermediateName,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
                Critical(KeyUsage(keyCertSign: true))
            },
            issuerPrivateKey: .init(rootKey))
    }

    struct Device {
        let key: P256.Signing.PrivateKey
        let keyID: Data
        let attestation: Data
    }

    static let developmentAAGUID = Data("appattestdevelop".utf8)
    static let productionAAGUID = Data("appattest".utf8) + Data(repeating: 0, count: 7)

    /// What a device sends once, when it registers.
    func attest(
        challenge: Data, appID: String = TestAttestation.appID, aaguid: Data = TestAttestation.productionAAGUID,
        counter: UInt32 = 0, nonceChallenge: Data? = nil, includeNonce: Bool = true, claimedKeyID: Data? = nil,
        credentialID: Data? = nil
    ) throws -> Device {
        let key = P256.Signing.PrivateKey()
        let keyID = Data(SHA256.hash(data: key.publicKey.x963Representation))
        let embeddedCredential = credentialID ?? keyID
        var authData = Data(SHA256.hash(data: Data(appID.utf8)))
        authData.append(0x40)
        authData += withUnsafeBytes(of: counter.bigEndian) { Data($0) }
        authData += aaguid
        authData += withUnsafeBytes(of: UInt16(embeddedCredential.count).bigEndian) { Data($0) }
        authData += embeddedCredential
        authData += Data([0xA0])  // an empty COSE map stands in for the credential public key

        let nonce = Data(SHA256.hash(data: authData + Data(SHA256.hash(data: nonceChallenge ?? challenge))))
        var extensions = try Certificate.Extensions {
            Critical(BasicConstraints.notCertificateAuthority)
            Critical(KeyUsage(digitalSignature: true))
        }
        if includeNonce {
            try extensions.append(
                Certificate.Extension(
                    oid: ASN1ObjectIdentifier(dotRepresentation: AppAttestVerifier.nonceOID), critical: false,
                    value: [0x30, 0x24, 0xA1, 0x22, 0x04, 0x20] + Array(nonce)))
        }
        let leaf = try Certificate(
            version: .v3, serialNumber: Certificate.SerialNumber(), publicKey: .init(key.publicKey),
            notValidBefore: Self.epoch.addingTimeInterval(-3_600),
            notValidAfter: Self.epoch.addingTimeInterval(86_400 * 30),
            issuer: intermediateName, subject: try DistinguishedName { CommonName("Test credential") },
            signatureAlgorithm: .ecdsaWithSHA256, extensions: extensions, issuerPrivateKey: .init(intermediateKey))

        let object = CBORWriter.map([
            ("fmt", CBORWriter.text("apple-appattest")),
            (
                "attStmt",
                CBORWriter.map([
                    (
                        "x5c",
                        CBORWriter.array([CBORWriter.bytes(try der(leaf)), CBORWriter.bytes(try der(intermediate))])
                    ),
                    ("receipt", CBORWriter.bytes(Data([1, 2, 3]))),
                ])
            ),
            ("authData", CBORWriter.bytes(authData)),
        ])
        return Device(key: key, keyID: claimedKeyID ?? keyID, attestation: Data(object))
    }

    func der(_ certificate: Certificate) throws -> Data {
        var serializer = DER.Serializer()
        try serializer.serialize(certificate)
        return Data(serializer.serializedBytes)
    }

    /// What a registered device sends with each request: a signed assertion over the request body.
    static func assertion(
        for device: Device, clientData: Data, counter: UInt32, appID: String = TestAttestation.appID,
        signingKey: P256.Signing.PrivateKey? = nil
    ) throws -> Data {
        var authData = Data(SHA256.hash(data: Data(appID.utf8)))
        authData.append(0x00)
        authData += withUnsafeBytes(of: counter.bigEndian) { Data($0) }
        let signature = try (signingKey ?? device.key).signature(for: authData + Data(SHA256.hash(data: clientData)))
        return Data(
            CBORWriter.map([
                ("signature", CBORWriter.bytes(signature.derRepresentation)),
                ("authenticatorData", CBORWriter.bytes(authData)),
            ]))
    }
}
