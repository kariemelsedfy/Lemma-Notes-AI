import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// `InstallStore` over the Firestore REST API: one document per install under `installs/{hex key id}`. A create is
/// guarded by "document must not exist", and a save by "update time must still be the one we read", so two Cloud
/// Run instances racing on one install cannot both win (ADR-031).
struct FirestoreInstallStore: InstallStore {
    typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let projectID: String
    let token: @Sendable () async throws -> String
    let send: Send

    private var documents: String { "projects/\(projectID)/databases/(default)/documents" }

    func create(_ record: InstallRecord) async throws -> Bool {
        do {
            try await commit(write(record, precondition: ["exists": false]))
            return true
        } catch LedgerError.duplicate {
            return false
        }
    }

    func load(_ keyID: Data) async throws -> VersionedInstall? {
        let (status, data) = try await call(
            "GET", "https://firestore.googleapis.com/v1/\(documents)/installs/\(Self.name(keyID))", body: nil)
        if status == 404 { return nil }
        guard status == 200, let document = try? Self.object(data), let version = document["updateTime"] as? String,
            let record = Self.decode(document, keyID: keyID)
        else { throw LedgerError.storageUnavailable }
        return VersionedInstall(record: record, version: version)
    }

    func save(_ record: InstallRecord, ifVersion version: String) async throws -> Bool {
        do {
            try await commit(write(record, precondition: ["updateTime": version]))
            return true
        } catch LedgerStoreError.conflict {
            return false
        }
    }

    // MARK: - Encoding

    static func name(_ keyID: Data) -> String { keyID.map { String(format: "%02x", $0) }.joined() }

    private func write(_ record: InstallRecord, precondition: [String: Any]) -> [String: Any] {
        [
            "update": [
                "name": "\(documents)/installs/\(Self.name(record.key.keyID))", "fields": Self.encode(record),
            ],
            "currentDocument": precondition,
        ]
    }

    static func encode(_ record: InstallRecord) -> [String: Any] {
        func int(_ value: Int64) -> [String: Any] { ["integerValue": String(value)] }
        func string(_ value: String) -> [String: Any] { ["stringValue": value] }
        return [
            "publicKey": string(record.key.publicKeyX963.base64EncodedString()),
            "counter": int(Int64(record.key.counter)),
            "plan": string(record.plan.rawValue),
            "planExpiresAt": record.planExpiresAt.map { int(Int64($0.timeIntervalSince1970)) } ?? [
                "nullValue": NSNull()
            ],
            "originalTransactionID": record.originalTransactionID.map(string) ?? ["nullValue": NSNull()],
            "tourAsksUsed": int(Int64(record.tourAsksUsed)),
            "usageMonth": string(record.usageMonth),
            "usageMicros": int(record.usageMicros),
            "createdAt": int(Int64(record.createdAt.timeIntervalSince1970)),
        ]
    }

    static func decode(_ document: [String: Any], keyID: Data) -> InstallRecord? {
        guard let fields = document["fields"] as? [String: Any],
            let publicKey = string(fields["publicKey"]).flatMap({ Data(base64Encoded: $0) }),
            let counter = integer(fields["counter"]), let counter32 = UInt32(exactly: counter),
            let plan = string(fields["plan"]).flatMap(InstallPlan.init(rawValue:)),
            let tour = integer(fields["tourAsksUsed"]), let month = string(fields["usageMonth"]),
            let micros = integer(fields["usageMicros"]), let created = integer(fields["createdAt"])
        else { return nil }
        return InstallRecord(
            key: AttestedKey(keyID: keyID, publicKeyX963: publicKey, counter: counter32),
            plan: plan,
            planExpiresAt: integer(fields["planExpiresAt"]).map { Date(timeIntervalSince1970: TimeInterval($0)) },
            originalTransactionID: string(fields["originalTransactionID"]), tourAsksUsed: Int(tour), usageMonth: month,
            usageMicros: micros, createdAt: Date(timeIntervalSince1970: TimeInterval(created)))
    }

    private static func integer(_ value: Any?) -> Int64? {
        ((value as? [String: Any])?["integerValue"] as? String).flatMap(Int64.init)
    }

    private static func string(_ value: Any?) -> String? { (value as? [String: Any])?["stringValue"] as? String }

    // MARK: - REST plumbing

    private func commit(_ write: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["writes": [write]])
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
