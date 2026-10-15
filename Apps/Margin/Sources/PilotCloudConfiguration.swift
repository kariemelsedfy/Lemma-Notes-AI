import Foundation
import Intelligence
import Security

/// Where the pilot bearer token lives. The token is a credential: Keychain only, never `UserDefaults`, never a
/// log line, never in the repository.
protocol PilotSecretStore: Sendable {
    func token() -> String?
    @discardableResult func setToken(_ value: String?) -> Bool
}

struct KeychainPilotSecretStore: PilotSecretStore {
    private let service = "edu.bowdoin.margin.pilot"
    private let account = "bearer-token"

    private var identity: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func token() -> String? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        let value = String(bytes: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    @discardableResult
    func setToken(_ value: String?) -> Bool {
        SecItemDelete(identity as CFDictionary)
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return true }
        var attributes = identity
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}

/// The owner's pilot settings (ADR-027/028): a consent flag, the proxy address and the bearer token. Read at
/// request time, so turning consent off or removing the token takes effect on the very next Ask.
struct PilotCloudConfiguration: Sendable {
    static let consentKey = "pilot.cloud.consent"
    static let urlKey = "pilot.cloud.url"
    /// The owner's deployed pilot proxy. Not a secret: every request still needs the bearer token.
    static let defaultServerText = "https://pilot-proxy-185495186917.us-central1.run.app"

    private let defaults: UserDefaults
    private let secrets: any PilotSecretStore

    init(defaults: UserDefaults = .standard, secrets: any PilotSecretStore = KeychainPilotSecretStore()) {
        self.defaults = defaults
        self.secrets = secrets
    }

    static var standard: PilotCloudConfiguration { PilotCloudConfiguration() }

    var consentGranted: Bool {
        get { defaults.bool(forKey: Self.consentKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.consentKey) }
    }

    var serverText: String {
        get { defaults.string(forKey: Self.urlKey) ?? Self.defaultServerText }
        nonmutating set { defaults.set(newValue, forKey: Self.urlKey) }
    }

    /// `https` origin only: no credentials, query or fragment, and a real host.
    var serverURL: URL? { Self.validatedURL(serverText) }
    var token: String? { secrets.token() }
    var hasToken: Bool { token != nil }

    /// Everything needed to send a question. Missing any piece means the Ask never leaves the iPad.
    var isReady: Bool { consentGranted && serverURL != nil && hasToken }

    @discardableResult
    func setToken(_ value: String?) -> Bool { secrets.setToken(value) }

    static func validatedURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https", let host = url.host, !host.isEmpty,
            url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
            ["", "/"].contains(url.path)
        else { return nil }
        return url
    }
}

/// Builds the proxy transport per request from the current settings.
struct ConfiguredProxyTransport: ProxyClientTransport {
    let configuration: PilotCloudConfiguration

    func response(to request: ProxyClientRequest) async throws -> Data {
        guard let url = configuration.serverURL,
            let transport = HTTPSProxyTransport(baseURL: url, token: { configuration.token })
        else { throw ProxyTransportFailure.refused }
        return try await transport.response(to: request)
    }
}

extension VirtualizedPageStack {
    /// Local arithmetic first (free, offline). Only a question the evaluator cannot answer may go to the hosted
    /// proxy, and only when consent, a valid address and a token are all present. The hosted provider is also
    /// consent-gated in the provider layer (invariant 8), so this readiness check is a second lock, not the
    /// only one.
    static func makeAskProvider(
        configuration: PilotCloudConfiguration,
        transport: (any ProxyClientTransport)? = nil
    ) -> any SpecProvider {
        let cloud = ProxySpecProvider.consentGated(
            transport: transport ?? ConfiguredProxyTransport(configuration: configuration),
            isConsentGranted: { configuration.consentGranted }
        )
        return FallbackSpecProvider(
            primary: LocalArithmeticSpecProvider(),
            fallback: cloud,
            shouldEscalate: { $0 is LocalArithmeticFailure && configuration.isReady }
        )
    }
}
