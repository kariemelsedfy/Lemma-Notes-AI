import Foundation
import XCTest

@testable import ProxyAdmission

final class FirestoreStoreTests: XCTestCase {
    private static let secret = "ya29.fake-token"

    func testLoadDecodesStateAndUsesUpdateTimeAsVersion() async throws {
        let log = Log()
        let store = makeStore(log) { _ in (Self.stateDocument(reserved: 50_000), 200) }
        let loaded = try await store.load()
        XCTAssertEqual(loaded?.version, "2026-10-15T12:00:00.000000Z")
        XCTAssertEqual(loaded?.state.reservedMicros, 50_000)
        XCTAssertEqual(loaded?.state.recent["p"], [100, 200])
        let sent = await log.requests
        XCTAssertEqual(sent.first?.url?.path, "/v1/projects/demo/databases/(default)/documents/pilotLedger/state")
        XCTAssertEqual(sent.first?.value(forHTTPHeaderField: "Authorization"), "Bearer \(Self.secret)")
    }

    func testMissingStateIsNilAndServerErrorsFailClosed() async throws {
        let absent = makeStore(Log()) { _ in (Data(), 404) }
        let loaded = try await absent.load()
        XCTAssertNil(loaded)
        let broken = makeStore(Log()) { _ in (Data("<html>".utf8), 500) }
        await expect(.storageUnavailable) { _ = try await broken.load() }
        let garbled = makeStore(Log()) { _ in (Data(#"{"fields":{}}"#.utf8), 200) }
        await expect(.storageUnavailable) { _ = try await garbled.load() }
    }

    func testReservationIsOneAtomicCommitWithBothPreconditions() async throws {
        let log = Log()
        let store = makeStore(log) { _ in (Data("{}".utf8), 200) }
        let id = UUID()
        var state = LedgerState(limitMicros: 100_000)
        state.reservedMicros = 50_000
        try await store.commitReservation(requestID: id, hold: 50_000, state: state, version: "V1")
        let requests = await log.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(request.url?.absoluteString.hasSuffix("/documents:commit") == true)
        let body = try XCTUnwrap(request.httpBody)
        let writes = try XCTUnwrap(
            (JSONSerialization.jsonObject(with: body) as? [String: Any])?["writes"] as? [[String: Any]])
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual((writes[0]["currentDocument"] as? [String: Any])?["updateTime"] as? String, "V1")
        XCTAssertEqual((writes[1]["currentDocument"] as? [String: Any])?["exists"] as? Bool, false)
        let hold = (writes[1]["update"] as? [String: Any])?["name"] as? String
        XCTAssertEqual(hold, "projects/demo/databases/(default)/documents/pilotHolds/\(id.uuidString)")
    }

    func testCommitErrorsMapToConflictDuplicateOrUnavailable() async throws {
        let state = LedgerState(limitMicros: 100_000)
        let conflict = makeStore(Log()) { _ in (Self.error("FAILED_PRECONDITION"), 400) }
        let aborted = makeStore(Log()) { _ in (Self.error("ABORTED"), 409) }
        let exists = makeStore(Log()) { _ in (Self.error("ALREADY_EXISTS"), 409) }
        let down = makeStore(Log()) { _ in (Self.error("UNAVAILABLE"), 503) }
        for store in [conflict, aborted] {
            do {
                try await store.commitObservation(requestID: UUID(), observed: 1, state: state, version: "V")
                XCTFail("Expected a conflict")
            } catch let error as LedgerStoreError {
                XCTAssertEqual(error, .conflict)
            }
        }
        await expect(.duplicate) {
            try await exists.commitObservation(requestID: UUID(), observed: 1, state: state, version: "V")
        }
        await expect(.storageUnavailable) {
            try await down.commitObservation(requestID: UUID(), observed: 1, state: state, version: "V")
        }
    }

    func testHoldLookupReadsTheIntegerOrReportsAbsence() async throws {
        let present = makeStore(Log()) { _ in
            (Data(#"{"fields":{"holdMicros":{"integerValue":"50000"}}}"#.utf8), 200)
        }
        let hold = try await present.hold(for: UUID())
        XCTAssertEqual(hold, 50_000)
        let absent = makeStore(Log()) { _ in (Data(), 404) }
        let none = try await absent.hold(for: UUID())
        XCTAssertNil(none)
    }

    func testLedgerRoundTripsThroughTheRESTShapeAndNetworkFailureFailsClosed() async throws {
        let down = FirestoreLedgerStore(
            projectID: "demo", token: { Self.secret }, send: { _ in throw URLError(.timedOut) })
        let ledger = try TransactionalLedger(store: down, limitMicros: 100_000)
        await expect(.storageUnavailable) { _ = try await ledger.remainingMicros() }
    }

    func testAccessTokenIsFetchedFromMetadataServerAndCached() async throws {
        let log = Log()
        let clock = TestClock(Date(timeIntervalSince1970: 1_000))
        let token = GoogleAccessToken(
            send: { request in
                await log.add(request)
                let body = Data(#"{"access_token":"tok","expires_in":3600}"#.utf8)
                return (body, Self.response(200))
            },
            clock: { clock.now }
        )
        let first = try await token.value()
        let second = try await token.value()
        XCTAssertEqual(first, "tok")
        XCTAssertEqual(second, "tok")
        let early = await log.requests
        XCTAssertEqual(early.count, 1)
        XCTAssertEqual(early.first?.value(forHTTPHeaderField: "Metadata-Flavor"), "Google")
        XCTAssertEqual(early.first?.url, GoogleAccessToken.metadataURL)
        clock.advance(3_600)
        _ = try await token.value()
        let late = await log.requests
        XCTAssertEqual(late.count, 2)
    }

    // MARK: - helpers

    private func makeStore(
        _ log: Log, _ reply: @escaping @Sendable (URLRequest) -> (Data, Int)
    ) -> FirestoreLedgerStore {
        FirestoreLedgerStore(
            projectID: "demo", token: { Self.secret },
            send: { request in
                await log.add(request)
                let (data, status) = reply(request)
                return (data, Self.response(status))
            }
        )
    }

    private static func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.test")!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private static func error(_ status: String) -> Data {
        Data(#"{"error":{"status":"\#(status)"}}"#.utf8)
    }

    private static func stateDocument(reserved: Int64) -> Data {
        let recent = #"{\"p\":[100,200]}"#
        return Data(
            """
            {"name":"x","updateTime":"2026-10-15T12:00:00.000000Z","fields":{
            "limitMicros":{"integerValue":"100000"},"halted":{"booleanValue":false},
            "reservedMicros":{"integerValue":"\(reserved)"},"observedMicros":{"integerValue":"0"},
            "recent":{"stringValue":"\(recent)"}}}
            """.utf8)
    }

    private func expect(_ failure: LedgerError, _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("Expected \(failure)")
        } catch let error as LedgerError {
            XCTAssertEqual(error, failure)
        } catch {
            XCTFail("Expected a content-free ledger error")
        }
    }
}

private actor Log {
    private(set) var requests: [URLRequest] = []
    func add(_ request: URLRequest) { requests.append(request) }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}
