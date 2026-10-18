import Foundation
import XCTest

@testable import ProxyAdmission

final class FirestoreInstallStoreTests: XCTestCase {
    private static let keyID = Data((0..<32).map(UInt8.init))
    private static let record = InstallRecord(
        key: AttestedKey(keyID: keyID, publicKeyX963: Data(repeating: 7, count: 65), counter: 4),
        plan: .premium, planExpiresAt: Date(timeIntervalSince1970: 1_900_000_000), originalTransactionID: "tx9",
        tourAsksUsed: 2, usageMonth: "2027-01", usageMicros: 12_345,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000))

    private actor Log {
        var requests: [URLRequest] = []
        func add(_ request: URLRequest) { requests.append(request) }
    }

    private func store(_ log: Log, reply: @escaping @Sendable (URLRequest) -> (Data, Int)) -> FirestoreInstallStore {
        FirestoreInstallStore(
            projectID: "demo", token: { "ya29.fake" },
            send: { request in
                await log.add(request)
                let (data, status) = reply(request)
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                return (data, response)
            })
    }

    private static func error(_ status: String) -> Data { Data(#"{"error":{"status":"\#(status)"}}"#.utf8) }

    func testARecordRoundTripsThroughItsFirestoreEncoding() throws {
        let document: [String: Any] = ["fields": FirestoreInstallStore.encode(Self.record), "updateTime": "V1"]
        XCTAssertEqual(FirestoreInstallStore.decode(document, keyID: Self.keyID), Self.record)
        var free = Self.record
        free.plan = .free
        free.planExpiresAt = nil
        free.originalTransactionID = nil
        let freeDocument: [String: Any] = ["fields": FirestoreInstallStore.encode(free)]
        XCTAssertEqual(FirestoreInstallStore.decode(freeDocument, keyID: Self.keyID), free)
    }

    func testLoadUsesTheUpdateTimeAsTheVersion() async throws {
        let log = Log()
        let fields = try JSONSerialization.data(
            withJSONObject: ["fields": FirestoreInstallStore.encode(Self.record), "updateTime": "2027-01-15T00:00:00Z"])
        let loaded = try await store(log) { _ in (fields, 200) }.load(Self.keyID)
        XCTAssertEqual(loaded?.version, "2027-01-15T00:00:00Z")
        XCTAssertEqual(loaded?.record, Self.record)
        let sent = await log.requests
        XCTAssertEqual(
            sent.first?.url?.path,
            "/v1/projects/demo/databases/(default)/documents/installs/\(FirestoreInstallStore.name(Self.keyID))")
    }

    func testAMissingInstallIsNilAndAnythingElseFailsClosed() async throws {
        let missing = try await store(Log()) { _ in (Data(), 404) }.load(Self.keyID)
        XCTAssertNil(missing)
        for reply in [(Data("<html>".utf8), 500), (Data(#"{"fields":{}}"#.utf8), 200)] {
            do {
                _ = try await store(Log()) { _ in reply }.load(Self.keyID)
                XCTFail("expected a failure")
            } catch let error as LedgerError {
                XCTAssertEqual(error, .storageUnavailable)
            }
        }
    }

    func testCreateIsGuardedByExistsFalseAndReportsAnExistingInstall() async throws {
        let log = Log()
        let created = try await store(log) { _ in (Data("{}".utf8), 200) }.create(Self.record)
        XCTAssertTrue(created)
        let sent = await log.requests
        let body = try XCTUnwrap(sent.first?.httpBody)
        let writes = try XCTUnwrap(
            (JSONSerialization.jsonObject(with: body) as? [String: Any])?["writes"] as? [[String: Any]])
        XCTAssertEqual((writes[0]["currentDocument"] as? [String: Any])?["exists"] as? Bool, false)

        let again = try await store(Log()) { _ in (Self.error("ALREADY_EXISTS"), 409) }.create(Self.record)
        XCTAssertFalse(again)
    }

    func testSaveIsGuardedByTheVersionAndReportsAConflict() async throws {
        let log = Log()
        let saved = try await store(log) { _ in (Data("{}".utf8), 200) }.save(Self.record, ifVersion: "V1")
        XCTAssertTrue(saved)
        let sent = await log.requests
        let body = try XCTUnwrap(sent.first?.httpBody)
        let writes = try XCTUnwrap(
            (JSONSerialization.jsonObject(with: body) as? [String: Any])?["writes"] as? [[String: Any]])
        XCTAssertEqual((writes[0]["currentDocument"] as? [String: Any])?["updateTime"] as? String, "V1")

        for status in ["ABORTED", "FAILED_PRECONDITION"] {
            let conflicted = try await store(Log()) { _ in (Self.error(status), 409) }.save(
                Self.record, ifVersion: "V1")
            XCTAssertFalse(conflicted, status)
        }
    }

    func testAnOutageIsAnErrorNotAConflict() async throws {
        do {
            _ = try await store(Log()) { _ in (Self.error("UNAVAILABLE"), 503) }.save(Self.record, ifVersion: "V1")
            XCTFail("expected an error")
        } catch let error as LedgerError {
            XCTAssertEqual(error, .storageUnavailable)
        }
    }
}
