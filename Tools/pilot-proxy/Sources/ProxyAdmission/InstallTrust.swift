import Crypto
import Foundation

/// A record and the version it was read at, for compare-and-set writes.
public struct VersionedInstall: Equatable, Sendable {
    public let record: InstallRecord
    public let version: String

    public init(record: InstallRecord, version: String) {
        self.record = record
        self.version = version
    }
}

/// Where attested installs live. Production uses Firestore; tests and local runs use the in-memory store. Writes
/// are compare-and-set because two Cloud Run instances can handle requests for one install at once.
public protocol InstallStore: Sendable {
    /// Stores a new install. False if its key id is already registered (an attestation can be used once).
    func create(_ record: InstallRecord) async throws -> Bool
    func load(_ keyID: Data) async throws -> VersionedInstall?
    /// Writes `record` only if the stored version is still `version`. False on a conflict: re-read and retry.
    func save(_ record: InstallRecord, ifVersion version: String) async throws -> Bool
}

public actor InMemoryInstallStore: InstallStore {
    private var records: [Data: (record: InstallRecord, version: Int)] = [:]

    public init() {}

    public func create(_ record: InstallRecord) -> Bool {
        guard records[record.key.keyID] == nil else { return false }
        records[record.key.keyID] = (record, 1)
        return true
    }

    public func load(_ keyID: Data) -> VersionedInstall? {
        records[keyID].map { VersionedInstall(record: $0.record, version: String($0.version)) }
    }

    public func save(_ record: InstallRecord, ifVersion version: String) -> Bool {
        guard let stored = records[record.key.keyID], String(stored.version) == version else { return false }
        records[record.key.keyID] = (record, stored.version + 1)
        return true
    }
}

/// One-time challenges that need no storage: `random(16) || expiry(8, big endian) || HMAC-SHA256(secret, both)`.
/// Any Cloud Run instance holding the secret can validate one. A challenge cannot be replayed for long because the
/// attestation it is used with registers a key id only once.
public struct AttestationChallenges: Sendable {
    public static let length = 16 + 8 + 32

    /// The secret as bytes: `SymmetricKey` is not `Sendable` in the Linux build of swift-crypto, so the key is made
    /// where it is used.
    private let secret: Data
    private let lifetime: TimeInterval
    private let now: @Sendable () -> Date

    public init(secret: Data, lifetime: TimeInterval = 300, now: @escaping @Sendable () -> Date = { Date() }) {
        self.secret = secret
        self.lifetime = lifetime
        self.now = now
    }

    public func issue() -> Data {
        var body = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        let expiry = UInt64(now().addingTimeInterval(lifetime).timeIntervalSince1970)
        body += withUnsafeBytes(of: expiry.bigEndian) { Data($0) }
        return body + Data(HMAC<SHA256>.authenticationCode(for: body, using: SymmetricKey(data: secret)))
    }

    public func isValid(_ challenge: Data) -> Bool {
        guard challenge.count == Self.length else { return false }
        let body = challenge.prefix(24)
        let mac = challenge.suffix(32)
        guard HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: body, using: SymmetricKey(data: secret))
        else { return false }
        let expiry = body.suffix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return Date(timeIntervalSince1970: TimeInterval(expiry)) > now()
    }
}

public enum InstallTrustError: Error, Equatable, Sendable {
    case invalidChallenge
    case alreadyRegistered
    case unknownInstall
    /// Another request kept moving the record; retry the request.
    case counterConflict
}

/// Registers installs and authorizes their requests (ADR-031).
public struct InstallTrust: Sendable {
    private static let attempts = 5

    private let verifier: AppAttestVerifier
    private let challenges: AttestationChallenges
    private let store: any InstallStore
    private let now: @Sendable () -> Date

    public init(
        verifier: AppAttestVerifier, challenges: AttestationChallenges, store: any InstallStore,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.verifier = verifier
        self.challenges = challenges
        self.store = store
        self.now = now
    }

    public func newChallenge() -> Data { challenges.issue() }

    public func register(attestation: Data, challenge: Data, keyID: Data) async throws {
        guard challenges.isValid(challenge) else { throw InstallTrustError.invalidChallenge }
        let key = try await verifier.verifyAttestation(attestation, challenge: challenge, keyID: keyID)
        guard try await store.create(InstallRecord(key: key, createdAt: now())) else {
            throw InstallTrustError.alreadyRegistered
        }
    }

    /// The install that signed `clientData` (the request body), with its assertion counter advanced and `change`
    /// applied in the same write (so a hold on the allowance and the counter can never disagree).
    ///
    /// `change` runs on a fresh copy each attempt and may throw to refuse the request (an allowance error); nothing
    /// is written then.
    @discardableResult
    public func authorize(
        keyID: Data, assertion: Data, clientData: Data, change: (inout InstallRecord) throws -> Void = { _ in }
    ) async throws -> InstallRecord {
        for _ in 0..<Self.attempts {
            guard let loaded = try await store.load(keyID) else { throw InstallTrustError.unknownInstall }
            var record = loaded.record
            let counter = try verifier.verifyAssertion(assertion, clientData: clientData, key: record.key)
            record.key = AttestedKey(keyID: keyID, publicKeyX963: record.key.publicKeyX963, counter: counter)
            try change(&record)
            if try await store.save(record, ifVersion: loaded.version) { return record }
        }
        throw InstallTrustError.counterConflict
    }

    /// Applies a change to an install without an assertion (settling cost after a request, applying a verified
    /// transaction). Retries on conflict.
    @discardableResult
    public func update(keyID: Data, _ change: (inout InstallRecord) -> Void) async throws -> InstallRecord {
        for _ in 0..<Self.attempts {
            guard let loaded = try await store.load(keyID) else { throw InstallTrustError.unknownInstall }
            var record = loaded.record
            change(&record)
            if try await store.save(record, ifVersion: loaded.version) { return record }
        }
        throw InstallTrustError.counterConflict
    }
}
