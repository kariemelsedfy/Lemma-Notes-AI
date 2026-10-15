import Foundation
import XCTest

@testable import ProxyAdmission

final class PilotServiceTests: XCTestCase {
    private static let token = "pilot-token-for-tests"
    private static let pixel = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR42mNgAAAAAgAB5Sfe/AAAAABJRU5ErkJggg=="
    )!

    func testErrorsReduceToFourStatuses() {
        XCTAssertEqual(PilotService.status(for: AdmissionError.unauthorized), .unauthorized)
        XCTAssertEqual(PilotService.status(for: LedgerError.overBudget), .overBudget)
        XCTAssertEqual(PilotService.status(for: LedgerError.rateLimited), .overBudget)
        XCTAssertEqual(PilotService.status(for: AdmissionError.malformed), .refused)
        XCTAssertEqual(PilotService.status(for: GeminiError.truncated), .refused)
        XCTAssertEqual(PilotService.status(for: GeminiTransportError.status(500)), .refused)
    }

    func testRouterAnswersWithSpecOnlyForTheRightToken() async throws {
        let router = try await makeRouter()
        let body = try requestBody()
        let good = await router.route(head(token: Self.token, length: body.count), body: body)
        XCTAssertEqual(good.status, 200)
        XCTAssertEqual(good.body, Data(#"{"version":1}"#.utf8))
        for bad in [nil, "wrong", "pilot-token-for-test", Self.token + "x"] {
            let denied = await router.route(head(token: bad, length: body.count), body: body)
            XCTAssertEqual(denied.status, 401)
            XCTAssertEqual(denied.body, Data())
        }
    }

    func testRouterMapsRefusalsHealthAndUnknownRoutes() async throws {
        let router = try await makeRouter()
        let junk = Data("nope".utf8)
        let refused = await router.route(head(token: Self.token, length: junk.count), body: junk)
        XCTAssertEqual(refused.status, 422)
        let health = await router.route(
            HTTPHead(method: "GET", path: "/status", headers: [:], contentLength: 0), body: Data())
        XCTAssertEqual(health.status, 200)
        let wrongMethod = await router.route(
            HTTPHead(method: "GET", path: "/v1/answer", headers: [:], contentLength: 0), body: Data())
        XCTAssertEqual(wrongMethod.status, 405)
        let missing = await router.route(
            HTTPHead(method: "GET", path: "/admin", headers: [:], contentLength: 0), body: Data())
        XCTAssertEqual(missing.status, 404)
        let lying = await router.route(head(token: Self.token, length: 99), body: junk)
        XCTAssertEqual(lying.status, 400)
    }

    func testEmptyConfiguredTokenAuthorizesNobody() async {
        let authorize = PilotRouter.authorizer(token: "", subjectID: UUID().uuidString)
        let denied = await authorize("")
        XCTAssertNil(denied)
        let missing = await authorize(nil)
        XCTAssertNil(missing)
    }

    func testReplyEncodingIsContentFreeAndClosesTheConnection() throws {
        let text = try XCTUnwrap(String(bytes: HTTPReply(status: 429).encoded(), encoding: .utf8))
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 429 Too Many Requests\r\n"))
        XCTAssertTrue(text.contains("Content-Length: 0\r\n"))
        XCTAssertTrue(text.contains("Connection: close\r\n"))
        XCTAssertTrue(text.contains("Cache-Control: no-store\r\n"))
    }

    // MARK: - helpers

    private func head(token: String?, length: Int) -> HTTPHead {
        var headers: [String: String] = [:]
        if let token { headers["authorization"] = "Bearer \(token)" }
        return HTTPHead(method: "POST", path: "/v1/answer", headers: headers, contentLength: length)
    }

    private func makeRouter() async throws -> PilotRouter {
        let ledger = try SpendLedger.bootstrap(databaseURL: temporaryDatabase(), limitMicros: 1_000_000)
        let gate = AdmissionGate(authorize: PilotRouter.authorizer(token: Self.token, subjectID: UUID().uuidString))
        let service = PilotService(pilot: PilotAdmission(admission: gate, ledger: ledger), transport: FixedTransport())
        return PilotRouter(service: service)
    }

    private func requestBody() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "requestID": UUID().uuidString, "cropPNG": Self.pixel.base64EncodedString(),
            "neighborhoodPNG": Self.pixel.base64EncodedString(), "transcript": "2+3=",
            "intent": "answer", "maxOutputTokens": 256,
        ])
    }

    private func temporaryDatabase() throws -> URL {
        let root = FileManager.default.temporaryDirectory
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("spend.sqlite")
    }
}

private struct FixedTransport: PilotModelTransport {
    func complete(_ request: AdmittedRequest) async throws -> GeminiReply {
        GeminiReply(specJSON: Data(#"{"version":1}"#.utf8), promptTokens: 100, outputTokens: 10)
    }
}
