import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

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
        let server = PilotSocketServer(router: PilotRouter(service: service), port: config.port)
        let bound = try server.start()
        log("pilot-proxy: listening on \(bound)")
        while true { try await Task.sleep(for: .seconds(3_600)) }
    }

    /// Unbuffered, so Cloud Run's log collector sees it immediately.
    public static func log(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
