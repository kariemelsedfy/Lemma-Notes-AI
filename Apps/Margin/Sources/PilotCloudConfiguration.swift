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

/// Pilot builds: a token the owner's Mac put in the app bundle at build time (`scripts/provision-pilot-token.sh`),
/// used when the Keychain has none. The file is gitignored and absent from a clean checkout, so a build made
/// without it simply has Cloud Ask off. **A bundled token is extractable from the app**, which is why this is for
/// builds installed on the owner's own iPad only; per-install attestation (App Attest) replaces it before anyone
/// else gets a build.
struct BundledFallbackSecretStore: PilotSecretStore {
    static let resourceName = "PilotToken"
    static let resourceExtension = "local"

    let primary: any PilotSecretStore
    /// Where the provisioned file is, if it was bundled. Injectable so tests need no real bundle.
    var location: @Sendable () -> URL? = {
        // Never under XCTest: a provisioned token in the test host would make unit tests call the paid cloud.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return nil }
        return Bundle.main.url(forResource: BundledFallbackSecretStore.resourceName, withExtension: resourceExtension)
    }

    func token() -> String? {
        if let stored = primary.token() { return stored }
        guard let url = location(),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    @discardableResult
    func setToken(_ value: String?) -> Bool { primary.setToken(value) }
}

/// The pilot's cloud settings (ADR-027/028/029): the proxy address and the bearer token. Read at
/// request time, so removing the token takes effect on the very next Ask.
struct PilotCloudConfiguration: Sendable {
    static let urlKey = "pilot.cloud.url"
    /// The owner's deployed pilot proxy. Not a secret: every request still needs the bearer token.
    static let defaultServerText = "https://pilot-proxy-185495186917.us-central1.run.app"

    private let defaults: UserDefaults
    private let secrets: any PilotSecretStore
    /// This install's App Attest identity (ADR-031), when the build and device can attest. Nil in tests and in
    /// builds without the capability.
    var installs: (any InstallCredentialSource)?
    /// Whether the App Store says this user has Premium. Read at request time.
    var isPaid: @Sendable () -> Bool

    init(
        defaults: UserDefaults = .standard,
        secrets: any PilotSecretStore = BundledFallbackSecretStore(primary: KeychainPilotSecretStore()),
        installs: (any InstallCredentialSource)? = nil,
        isPaid: @escaping @Sendable () -> Bool = { false }
    ) {
        self.defaults = defaults
        self.secrets = secrets
        self.installs = installs
        self.isPaid = isPaid
    }

    /// The app's real configuration: the token if this build has one, else this install's attested identity.
    static var standard: PilotCloudConfiguration {
        var configuration = PilotCloudConfiguration(isPaid: { PaidPlanFlag.shared.isPaid })
        configuration.installs = InstallSessionRegistry.shared.session(for: configuration.serverURL)
        return configuration
    }

    /// Whether this install may use the hosted model. **Entitlement, not a toggle** (ADR-029): hosted answers
    /// are part of the premium plan, so there is no consent switch in the app. Until StoreKit entitlements
    /// exist (M6) the stand-in is "this build was provisioned with an access token"; a build without one is
    /// the free tier and never makes a cloud call. The provider layer still gates on this (invariant 8), and
    /// the purchase flow must carry the third-party AI disclosure and acceptance (BUSINESS.md 5.1.2(i)).
    var plan: Plan { hasToken ? .pilot : .free }

    /// Whether a hosted request may leave the device at all: this build has the pilot token, or this install can
    /// attest and the server decides (three free asks, then Premium, ADR-031). Without either, nothing is sent.
    var isEntitled: Bool { plan.includesHostedAsk || installs?.isAvailable == true }

    /// Whether Plot should have the model read the handwriting. A plot costs nothing for a free install, so it never
    /// spends one of the three free asks: only the pilot token or a paying, attested install uses the model.
    var usesHostedPlotReading: Bool {
        serverURL != nil && (hasToken || (isPaid() && installs?.isAvailable == true))
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
    var isReady: Bool { isEntitled && serverURL != nil }

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
        guard let url = configuration.serverURL else { throw ProxyTransportFailure.refused }
        // The pilot token wins when there is one (the owner's build); otherwise the request is signed by this install.
        let token = configuration.token
        let installs = token == nil ? configuration.installs : nil
        let authorizer: HTTPSProxyTransport.Authorizer = { body in
            if let token { return ["Authorization": "Bearer \(token)"] }
            guard let installs, installs.isAvailable else { throw ProxyTransportFailure.unauthorized }
            return try await installs.headers(forBody: body)
        }
        guard let transport = HTTPSProxyTransport(baseURL: url, authorizer: authorizer) else {
            throw ProxyTransportFailure.refused
        }
        do {
            return try await transport.response(to: request)
        } catch ProxyTransportFailure.unauthorized {
            // The server did not accept this install (a reinstall invalidates its key): register afresh next time.
            await installs?.rejected()
            throw ProxyTransportFailure.unauthorized
        }
    }
}

/// One App Attest identity per server address, created on first use.
final class InstallSessionRegistry: @unchecked Sendable {
    static let shared = InstallSessionRegistry()

    private let lock = NSLock()
    private var sessions: [URL: InstallSession] = [:]

    func session(for url: URL?) -> InstallSession? {
        guard let url else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let existing = sessions[url] { return existing }
        let created = InstallSession(baseURL: url)
        sessions[url] = created
        return created
    }
}

/// Whether the user has Premium, readable from any thread (the provider layer asks at request time).
final class PaidPlanFlag: @unchecked Sendable {
    static let shared = PaidPlanFlag()

    private let lock = NSLock()
    private var paid = false

    var isPaid: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return paid
        }
        set {
            lock.lock()
            paid = newValue
            lock.unlock()
        }
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
            isConsentGranted: { configuration.isEntitled }
        )
        // Plot: an entitled install has the model read the function from the handwriting (the drawing is still
        // local); anyone else, a typed correction, or any hosted failure reads it on the device.
        return PlotRoutingProvider(
            plot: HostedPlotSpecProvider(
                hosted: cloud, local: LocalPlotSpecProvider(), isReady: { configuration.usesHostedPlotReading }),
            other: FallbackSpecProvider(
                primary: LocalArithmeticSpecProvider(),
                fallback: cloud,
                // A question local arithmetic cannot answer is what Premium is for; an unreadable scribble keeps its
                // own, friendlier explanation.
                surfacesConsentRequirement: { ($0 as? LocalArithmeticFailure) == .unsupported },
                shouldEscalate: { $0 is LocalArithmeticFailure }
            )
        )
    }
}
