import CryptoKit
import DeviceCheck
import Foundation
import Intelligence
import Security

/// Apple App Attest, as `InstallSession` needs it. The real one is `DeviceAttestation`; tests use a fake, because
/// App Attest only runs on a real device with the capability (and never in the Simulator).
protocol InstallAttesting: Sendable {
    var isSupported: Bool { get }
    /// A new key in the Secure Enclave; the id is base64 of the SHA-256 of its public key.
    func generateKey() async throws -> String
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

struct DeviceAttestation: InstallAttesting {
    var isSupported: Bool { DCAppAttestService.shared.isSupported }
    func generateKey() async throws -> String { try await DCAppAttestService.shared.generateKey() }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: clientDataHash)
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHash)
    }
}

/// Where this install's attested key id lives. Keychain, device-only: it is an identifier, not a secret, but losing
/// it would make the install register again.
protocol InstallKeyStore: Sendable {
    func keyID() -> String?
    func save(_ keyID: String)
    func clear()
}

struct KeychainInstallKeyStore: InstallKeyStore {
    private let service = "edu.bowdoin.margin.install"
    private let account = "app-attest-key-id"

    private var identity: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func keyID() -> String? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(bytes: data, encoding: .utf8)
    }

    func save(_ keyID: String) {
        clear()
        var attributes = identity
        attributes[kSecValueData as String] = Data(keyID.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func clear() { SecItemDelete(identity as CFDictionary) }
}

/// What the proxy transport needs from an install identity.
protocol InstallCredentialSource: Sendable {
    /// Whether this build and device can attest at all.
    var isAvailable: Bool { get }
    func headers(forBody body: Data) async throws -> [String: String]
    /// The server did not accept these credentials: forget the registration so the next request registers again.
    func rejected() async
}

enum InstallIdentityError: Error, Equatable {
    /// No App Attest on this device or build (the Simulator, an old device, or a build without the capability).
    case unsupported
    /// The server could not be reached or refused the attestation.
    case registrationFailed
}

/// This install's identity with the proxy (ADR-031): it registers once with an App Attest attestation, then signs
/// every hosted request, and tells the server about its Premium subscription. One registration at a time.
actor InstallSession: InstallCredentialSource {
    typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let baseURL: URL
    private let attesting: any InstallAttesting
    private let keys: any InstallKeyStore
    private let send: Send
    private var registration: Task<String, Error>?

    init(
        baseURL: URL, attesting: any InstallAttesting = DeviceAttestation(),
        keys: any InstallKeyStore = KeychainInstallKeyStore(),
        send: @escaping Send = { try await URLSession(configuration: .ephemeral).data(for: $0) }
    ) {
        self.baseURL = baseURL
        self.attesting = attesting
        self.keys = keys
        self.send = send
    }

    nonisolated var isSupported: Bool { attesting.isSupported }
    nonisolated var isAvailable: Bool { attesting.isSupported }
    func rejected() { keys.clear() }

    /// The headers that authenticate one request: the key id and an assertion over the request body.
    func headers(forBody body: Data) async throws -> [String: String] {
        let hash = Data(SHA256.hash(data: body))
        let keyID = try await registeredKeyID()
        do {
            let assertion = try await attesting.generateAssertion(keyID, clientDataHash: hash)
            return ["x-install-key": keyID, "x-install-assertion": assertion.base64EncodedString()]
        } catch {
            // The Keychain outlives a reinstall but the Secure Enclave key does not, so a stored id can be dead.
            // Forget it and register once more.
            keys.clear()
            let fresh = try await registeredKeyID()
            let assertion = try await attesting.generateAssertion(fresh, clientDataHash: hash)
            return ["x-install-key": fresh, "x-install-assertion": assertion.base64EncodedString()]
        }
    }

    /// Tells the server about a signed StoreKit transaction so it can grant the plan.
    func uploadTransaction(_ signedTransaction: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["transaction": signedTransaction])
        let credentials = try await headers(forBody: body)
        let (_, status) = try await post("/v1/entitlement", body: body, headers: credentials)
        guard status == 200 else { throw InstallIdentityError.registrationFailed }
    }

    /// For callers that retry later anyway.
    func uploadIgnoringFailure(_ signedTransaction: String) async {
        try? await uploadTransaction(signedTransaction)
    }

    // MARK: - Registration

    private func registeredKeyID() async throws -> String {
        guard attesting.isSupported else { throw InstallIdentityError.unsupported }
        if let stored = keys.keyID() { return stored }
        if let registration { return try await registration.value }
        let task = Task { try await register() }
        registration = task
        defer { registration = nil }
        return try await task.value
    }

    private func register() async throws -> String {
        let challengeData = try await challenge()
        let keyID = try await attesting.generateKey()
        let attestation = try await attesting.attestKey(
            keyID, clientDataHash: Data(SHA256.hash(data: challengeData)))
        let body = try JSONSerialization.data(withJSONObject: [
            "keyID": keyID, "attestation": attestation.base64EncodedString(),
            "challenge": challengeData.base64EncodedString(),
        ])
        let (_, status) = try await post("/v1/register", body: body, headers: [:])
        // 409: an earlier attempt registered this key but never saved it; it is ours either way.
        guard status == 200 || status == 409 else { throw InstallIdentityError.registrationFailed }
        keys.save(keyID)
        return keyID
    }

    private func challenge() async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent("/v1/challenge"), timeoutInterval: 15)
        request.httpMethod = "GET"
        guard let (data, response) = try? await send(request), (response as? HTTPURLResponse)?.statusCode == 200,
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
            let encoded = object["challenge"], let challenge = Data(base64Encoded: encoded)
        else { throw InstallIdentityError.registrationFailed }
        return challenge
    }

    private func post(_ path: String, body: Data, headers: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        guard let (data, response) = try? await send(request), let http = response as? HTTPURLResponse else {
            throw InstallIdentityError.registrationFailed
        }
        return (data, http.statusCode)
    }
}
