import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Bearer tokens for Google APIs. On Cloud Run the token comes from the metadata server for the service's
/// own identity; no key file exists. Cached until shortly before it expires.
actor GoogleAccessToken {
    typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    static let metadataURL = URL(
        string: "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
    )!

    private let send: Send
    private let clock: @Sendable () -> Date
    private var cached: (value: String, expires: Date)?

    init(send: @escaping Send, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.send = send
        self.clock = clock
    }

    func value() async throws -> String {
        if let cached, cached.expires > clock().addingTimeInterval(60) { return cached.value }
        var request = URLRequest(url: Self.metadataURL, timeoutInterval: 5)
        request.setValue("Google", forHTTPHeaderField: "Metadata-Flavor")
        guard let (data, response) = try? await send(request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = object["access_token"] as? String, !token.isEmpty,
            let seconds = object["expires_in"] as? Double
        else { throw LedgerError.storageUnavailable }
        cached = (token, clock().addingTimeInterval(seconds))
        return token
    }
}

/// `LedgerDocumentStore` over the Firestore REST API. Every change is one atomic `commit`: the state
/// document is written only if its `updateTime` is still the one we read, and the per-request document
/// is created only if absent. Errors reduce to `conflict`, `duplicate` or `storageUnavailable`.
struct FirestoreLedgerStore: LedgerDocumentStore {
    typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let projectID: String
    let token: @Sendable () async throws -> String
    let send: Send

    private var documents: String { "projects/\(projectID)/databases/(default)/documents" }
    private var root: String { "https://firestore.googleapis.com/v1/\(documents)" }
    private var statePath: String { "\(documents)/pilotLedger/state" }

    func load() async throws -> (state: LedgerState, version: String)? {
        let (status, data) = try await call("GET", "\(root)/pilotLedger/state", body: nil)
        if status == 404 { return nil }
        guard status == 200, let document = try? Self.object(data), let state = Self.decodeState(document),
            let version = document["updateTime"] as? String
        else { throw LedgerError.storageUnavailable }
        return (state, version)
    }

    func create(_ state: LedgerState) async throws {
        try await commit([Self.write(statePath, Self.encode(state), precondition: ["exists": false])])
    }

    func hold(for requestID: UUID) async throws -> Int64? {
        let (status, data) = try await call("GET", "\(root)/pilotHolds/\(requestID.uuidString)", body: nil)
        if status == 404 { return nil }
        guard status == 200, let document = try? Self.object(data),
            let fields = document["fields"] as? [String: Any], let hold = Self.integer(fields["holdMicros"])
        else { throw LedgerError.storageUnavailable }
        return hold
    }

    func commitReservation(requestID: UUID, hold: Int64, state: LedgerState, version: String) async throws {
        let holdPath = "\(documents)/pilotHolds/\(requestID.uuidString)"
        try await commit([
            Self.write(statePath, Self.encode(state), precondition: ["updateTime": version]),
            Self.write(holdPath, ["holdMicros": Self.int(hold)], precondition: ["exists": false]),
        ])
    }

    func commitObservation(requestID: UUID, observed: Int64, state: LedgerState, version: String) async throws {
        let path = "\(documents)/pilotObservations/\(requestID.uuidString)"
        try await commit([
            Self.write(statePath, Self.encode(state), precondition: ["updateTime": version]),
            Self.write(path, ["observedMicros": Self.int(observed)], precondition: ["exists": false]),
        ])
    }

    // MARK: - REST plumbing

    private func commit(_ writes: [[String: Any]]) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["writes": writes])
        let (status, data) = try await call(
            "POST", "https://firestore.googleapis.com/v1/\(documents):commit", body: body)
        if status == 200 { return }
        switch Self.errorStatus(data) {
        case "ALREADY_EXISTS": throw LedgerError.duplicate
        case "ABORTED", "FAILED_PRECONDITION": throw LedgerStoreError.conflict
        default: throw LedgerError.storageUnavailable
        }
    }

    private func call(_ method: String, _ url: String, body: Data?) async throws -> (Int, Data) {
        guard let target = URL(string: url) else { throw LedgerError.storageUnavailable }
        var request = URLRequest(url: target, timeoutInterval: 10)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        guard let (data, response) = try? await send(request), let http = response as? HTTPURLResponse else {
            throw LedgerError.storageUnavailable
        }
        return (http.statusCode, data)
    }

    private static func write(_ name: String, _ fields: [String: Any], precondition: [String: Any]) -> [String: Any] {
        ["update": ["name": name, "fields": fields], "currentDocument": precondition]
    }

    private static func int(_ value: Int64) -> [String: Any] { ["integerValue": String(value)] }

    private static func encode(_ state: LedgerState) -> [String: Any] {
        let recent = (try? JSONSerialization.data(withJSONObject: state.recent, options: [.sortedKeys])) ?? Data()
        return [
            "limitMicros": int(state.limitMicros), "halted": ["booleanValue": state.halted],
            "reservedMicros": int(state.reservedMicros), "observedMicros": int(state.observedMicros),
            "recent": ["stringValue": String(data: recent, encoding: .utf8) ?? ""],
        ]
    }

    private static func decodeState(_ document: [String: Any]) -> LedgerState? {
        guard let fields = document["fields"] as? [String: Any],
            let limit = integer(fields["limitMicros"]), let reserved = integer(fields["reservedMicros"]),
            let observed = integer(fields["observedMicros"]),
            let halted = (fields["halted"] as? [String: Any])?["booleanValue"] as? Bool,
            let text = (fields["recent"] as? [String: Any])?["stringValue"] as? String,
            let recent = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: [Int64]]
        else { return nil }
        return LedgerState(
            limitMicros: limit, halted: halted, reservedMicros: reserved, observedMicros: observed, recent: recent
        )
    }

    private static func integer(_ value: Any?) -> Int64? {
        ((value as? [String: Any])?["integerValue"] as? String).flatMap(Int64.init)
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LedgerError.storageUnavailable
        }
        return object
    }

    private static func errorStatus(_ data: Data) -> String? {
        ((try? object(data))?["error"] as? [String: Any])?["status"] as? String
    }
}
