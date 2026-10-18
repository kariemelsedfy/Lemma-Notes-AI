import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// What an attested-installs deployment is configured with (ADR-031).
struct PilotInstallSettings: Equatable {
    /// `TEAMID.bundleid`, as hashed into every App Attest object.
    let appID: String
    let bundleID: String
    let productIDs: Set<String>
    let challengeSecret: Data
    let allowsDevelopment: Bool
}

/// Process entry for the hosted pilot proxy. Configuration comes only from the environment (Cloud Run injects
/// secrets as environment values), so nothing sensitive is ever in an argument, file or image layer.
public enum PilotServer {
    public enum ConfigurationError: Error, Equatable {
        case missing(String)
        case invalid(String)
    }

    struct Configuration {
        let port: UInt16
        let projectID: String
        let token: String
        let subjectID: String
        let geminiKey: String
        /// Present only when the deployment accepts attested installs (ADR-031); absent, the install routes are off.
        let installs: PilotInstallSettings?

        init(environment: [String: String]) throws {
            func value(_ name: String) throws -> String {
                guard let found = environment[name], !found.isEmpty else { throw ConfigurationError.missing(name) }
                return found
            }
            guard let port = UInt16(environment["PORT"] ?? "8080"), port > 0 else {
                throw ConfigurationError.invalid("PORT")
            }
            self.port = port
            projectID = try value("GOOGLE_CLOUD_PROJECT")
            token = try value("PILOT_TOKEN")
            guard token.utf8.count >= 32 else { throw ConfigurationError.invalid("PILOT_TOKEN") }
            subjectID = try value("PILOT_SUBJECT")
            guard UUID(uuidString: subjectID) != nil else { throw ConfigurationError.invalid("PILOT_SUBJECT") }
            geminiKey = try value("GEMINI_API_KEY")
            installs = try Self.installs(environment)
        }

        /// All-or-nothing: setting `APPLE_APP_ID` turns attested installs on and then requires the rest, so a
        /// half-configured deployment fails to start instead of running open.
        static func installs(_ environment: [String: String]) throws -> PilotInstallSettings? {
            guard let appID = environment["APPLE_APP_ID"], !appID.isEmpty else { return nil }
            func value(_ name: String) throws -> String {
                guard let found = environment[name], !found.isEmpty else { throw ConfigurationError.missing(name) }
                return found
            }
            guard appID.contains("."), appID.split(separator: ".").first?.count == 10 else {
                throw ConfigurationError.invalid("APPLE_APP_ID")
            }
            let secret = Data(try value("CHALLENGE_SECRET").utf8)
            guard secret.count >= 32 else { throw ConfigurationError.invalid("CHALLENGE_SECRET") }
            let products = Set(
                try value("PREMIUM_PRODUCT_IDS").split(separator: ",").map {
                    String($0).trimmingCharacters(in: .whitespaces)
                })
            guard !products.isEmpty, !products.contains("") else {
                throw ConfigurationError.invalid("PREMIUM_PRODUCT_IDS")
            }
            return PilotInstallSettings(
                appID: appID, bundleID: try value("APPLE_BUNDLE_ID"), productIDs: products, challengeSecret: secret,
                allowsDevelopment: environment["ALLOW_APP_ATTEST_DEVELOPMENT"] == "1")
        }
    }

    /// Starts the server and never returns. Logs one content-free line per lifecycle event.
    public static func run(environment: [String: String] = ProcessInfo.processInfo.environment) async throws {
        let config = try Configuration(environment: environment)
        let session = URLSession(configuration: .ephemeral)
        let send: GoogleAccessToken.Send = { try await session.data(for: $0) }
        let access = GoogleAccessToken(send: send)
        let store = FirestoreLedgerStore(projectID: config.projectID, token: { try await access.value() }, send: send)
        let ledger = try TransactionalLedger(store: store)
        do {
            if try await store.load() == nil { try await ledger.bootstrap() }
        } catch {
            log("pilot-proxy: ledger not ready; requests will be refused until it is")
        }
        let key = config.geminiKey
        let transport = GeminiHTTPTransport(key: { key }, send: { try await session.data(for: $0) })
        let gate = AdmissionGate(authorize: PilotRouter.authorizer(token: config.token, subjectID: config.subjectID))
        let service = PilotService(pilot: PilotAdmission(admission: gate, ledger: ledger), transport: transport)
        var router = PilotRouter(service: service)
        if let settings = config.installs {
            let trust = InstallTrust(
                verifier: try AppAttestVerifier.standard(
                    appID: settings.appID, allowsDevelopment: settings.allowsDevelopment),
                challenges: AttestationChallenges(secret: settings.challengeSecret),
                store: FirestoreInstallStore(
                    projectID: config.projectID, token: { try await access.value() }, send: send))
            router.installs = InstallGate(
                trust: trust,
                transactions: try AppleTransactionVerifier.standard(
                    bundleID: settings.bundleID, productIDs: settings.productIDs),
                now: { Date() })
            log("pilot-proxy: attested installs enabled")
        }
        let server = PilotSocketServer(router: router, port: config.port)
        let bound = try server.start()
        log("pilot-proxy: listening on \(bound)")
        while true { try await Task.sleep(for: .seconds(3_600)) }
    }

    /// Unbuffered, so Cloud Run's log collector sees it immediately.
    public static func log(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
