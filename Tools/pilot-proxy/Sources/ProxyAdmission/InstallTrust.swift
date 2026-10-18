import Crypto
import Foundation

/// Where attested installs and their assertion counters live. Production uses Firestore (P4); tests and local runs
/// use the in-memory store. Every method must be atomic: two Cloud Run instances can see the same request.
public protocol InstallStore: Sendable {
    /// Stores a new install. False if its key id is already registered (an attestation can be used once).
    func register(_ key: AttestedKey) async throws -> Bool
    func key(for keyID: Data) async throws -> AttestedKey?
    /// Moves the counter from `old` to `new` only if it is still `old` (compare and set). False on a conflict.
    func advanceCounter(keyID: Data, from old: UInt32, to new: UInt32) async throws -> Bool
}

public actor InMemoryInstallStore: InstallStore {
    private var keys: [Data: AttestedKey] = [:]

    public init() {}

    public func register(_ key: AttestedKey) -> Bool {
        guard keys[key.keyID] == nil else { return false }
        keys[key.keyID] = key
        return true
    }

    public func key(for keyID: Data) -> AttestedKey? { keys[keyID] }

    public func advanceCounter(keyID: Data, from old: UInt32, to new: UInt32) -> Bool {
        guard let key = keys[keyID], key.counter == old else { return false }
        keys[keyID] = AttestedKey(keyID: keyID, publicKeyX963: key.publicKeyX963, counter: new)
        return true
    }
}

/// One-time challenges that need no storage: `random(16) || expiry(8, big endian) || HMAC-SHA256(secret, both)`.
/// Any Cloud Run instance holding the secret can validate one. A challenge cannot be replayed for long because the
/// attestation it is used with registers a key id only once.
public struct AttestationChallenges: Sendable {
    public static let length = 16 + 8 + 32

    private let key: SymmetricKey
    private let lifetime: TimeInterval
    private let now: @Sendable () -> Date

    public init(secret: Data, lifetime: TimeInterval = 300, now: @escaping @Sendable () -> Date = { Date() }) {
        self.key = SymmetricKey(data: secret)
        self.lifetime = lifetime
        self.now = now
    }

    public func issue() -> Data {
        var body = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        let expiry = UInt64(now().addingTimeInterval(lifetime).timeIntervalSince1970)
        body += withUnsafeBytes(of: expiry.bigEndian) { Data($0) }
        return body + Data(HMAC<SHA256>.authenticationCode(for: body, using: key))
    }

    public func isValid(_ challenge: Data) -> Bool {
        guard challenge.count == Self.length else { return false }
        let body = challenge.prefix(24)
        let mac = challenge.suffix(32)
        guard HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: body, using: key) else { return false }
        let expiry = body.suffix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return Date(timeIntervalSince1970: TimeInterval(expiry)) > now()
    }
}

public enum InstallTrustError: Error, Equatable, Sendable {
    case invalidChallenge
    case alreadyRegistered
    case unknownInstall
    /// Another request moved the counter first. A replayed assertion lands here or in `counterNotIncreased`.
    case counterConflict
}

/// Registers installs and authorizes their requests (ADR-031).
public struct InstallTrust: Sendable {
    private let verifier: AppAttestVerifier
    private let challenges: AttestationChallenges
    private let store: any InstallStore

    public init(verifier: AppAttestVerifier, challenges: AttestationChallenges, store: any InstallStore) {
        self.verifier = verifier
        self.challenges = challenges
        self.store = store
    }

    public func newChallenge() -> Data { challenges.issue() }

    public func register(attestation: Data, challenge: Data, keyID: Data) async throws {
        guard challenges.isValid(challenge) else { throw InstallTrustError.invalidChallenge }
        let key = try await verifier.verifyAttestation(attestation, challenge: challenge, keyID: keyID)
        guard try await store.register(key) else { throw InstallTrustError.alreadyRegistered }
    }

    /// The install that signed `clientData` (the request body), with its counter advanced.
    @discardableResult
    public func authorize(keyID: Data, assertion: Data, clientData: Data) async throws -> AttestedKey {
        guard let key = try await store.key(for: keyID) else { throw InstallTrustError.unknownInstall }
        let counter = try verifier.verifyAssertion(assertion, clientData: clientData, key: key)
        guard try await store.advanceCounter(keyID: keyID, from: key.counter, to: counter) else {
            throw InstallTrustError.counterConflict
        }
        return AttestedKey(keyID: keyID, publicKeyX963: key.publicKeyX963, counter: counter)
    }
}
