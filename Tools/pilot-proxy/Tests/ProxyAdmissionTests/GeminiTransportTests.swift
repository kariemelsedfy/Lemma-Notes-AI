import Foundation
import XCTest

@testable import ProxyAdmission

final class GeminiTransportTests: XCTestCase {
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    private static let secret = "test-key-not-real"
    private static let truncated = reply(
        finish: "MAX_TOKENS", usage: #""promptTokenCount":2000,"candidatesTokenCount":500"#
    )
    private static let hugeUsage =
        #""promptTokenCount":1,"candidatesTokenCount":9223372036854775807,"#
        + #""thoughtsTokenCount":9223372036854775807"#

    private static func make(_ send: @escaping GeminiHTTPTransport.Send) -> GeminiHTTPTransport {
        GeminiHTTPTransport(key: { secret }, send: send)
    }

    func testSendsOneKeyedPostAndParsesTheReply() async throws {
        let seen = Captured()
        let transport = Self.make { request in
            await seen.set(request)
            let usage = #""promptTokenCount":100,"candidatesTokenCount":10"#
            return (Self.reply(finish: "STOP", usage: usage), Self.ok(200))
        }
        let reply = try await transport.complete(try request())
        XCTAssertEqual(reply.promptTokens, 100)
        XCTAssertEqual(reply.outputTokens, 10)
        let captured = await seen.request
        let sent = try XCTUnwrap(captured)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.url, GeminiHTTPTransport.endpoint)
        XCTAssertEqual(sent.url?.host, "generativelanguage.googleapis.com")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "x-goog-api-key"), Self.secret)
        XCTAssertNil(sent.url?.query)
        XCTAssertEqual(sent.timeoutInterval, GeminiHTTPTransport.timeout)
    }

    func testKeyFailureNeverSendsAndStatusNetworkErrorsAreContentFree() async throws {
        let calls = Counter()
        let noKey = GeminiHTTPTransport(
            key: { throw GeminiTransportError.keyUnavailable },
            send: { _ in
                await calls.bump()
                return (Data(), Self.ok(200))
            }
        )
        await expect(.keyUnavailable, noKey)
        let calls0 = await calls.count
        XCTAssertEqual(calls0, 0)
        let errorBody = Data(#"{"error":"secret body"}"#.utf8)
        let rejected = Self.make { _ in (errorBody, Self.ok(429)) }
        await expect(.status(429), rejected)
        let down = Self.make { _ in throw URLError(.notConnectedToInternet) }
        await expect(.network, down)
        let notHTTP = Self.make { _ in (Data(), URLResponse()) }
        await expect(.notHTTP, notHTTP)
    }

    func testCancellationStaysCancellation() async {
        let transport = Self.make { _ in throw CancellationError() }
        do {
            _ = try await transport.complete(try request())
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Cancellation was rewritten")
        }
    }

    func testRefusedButBilledReplyCarriesItsUsage() async throws {
        let transport = Self.make { _ in
            (Self.truncated, Self.ok(200))
        }
        do {
            _ = try await transport.complete(try request())
            XCTFail("Truncated reply was accepted")
        } catch let billed as GeminiBilledFailure {
            XCTAssertEqual(billed.reason, .truncated)
            XCTAssertEqual(billed.promptTokens, 2000)
            XCTAssertEqual(billed.outputTokens, 500)
            XCTAssertEqual(billed.costMicros, 1_250)
        }
    }

    func testBilledFailureIsRecordedByAdmissionAndFailsWithItsReason() async throws {
        let ledger = try SpendLedger.bootstrap(databaseURL: temporaryDatabase(), limitMicros: 100_000)
        let gate = PilotAdmission(admission: admission(), ledger: ledger)
        let transport = Self.make { _ in
            (Self.truncated, Self.ok(200))
        }
        do {
            _ = try await gate.invoke(try body(), proof: "pilot", transport: transport)
            XCTFail("Truncated reply was accepted")
        } catch let error as GeminiError {
            XCTAssertEqual(error, .truncated)
        }
        let observed = try await ledger.observedTotalMicros()
        XCTAssertEqual(observed, 1_250)
    }

    func testHostileUsageCountsAreRejectedWithoutTrapping() {
        let huge = Self.reply(finish: "STOP", usage: Self.hugeUsage)
        XCTAssertThrowsError(try GeminiResponseParser.parse(huge))
        XCTAssertNil(GeminiResponseParser.usage(huge))
        let negative = Self.reply(
            finish: "STOP", usage: #""promptTokenCount":1,"candidatesTokenCount":-5,"thoughtsTokenCount":9"#
        )
        XCTAssertThrowsError(try GeminiResponseParser.parse(negative))
        XCTAssertNil(GeminiResponseParser.usage(negative))
        let missing = Self.reply(finish: "STOP", usage: #""candidatesTokenCount":1"#)
        XCTAssertThrowsError(try GeminiResponseParser.parse(missing))
    }

    private func admission() -> AdmissionGate {
        let id = UUID().uuidString
        return AdmissionGate(authorize: { $0 == "pilot" ? PilotIdentity(subjectID: id) : nil })
    }

    private func body() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "requestID": UUID().uuidString, "cropPNG": Self.pixel.base64EncodedString(),
            "neighborhoodPNG": Self.pixel.base64EncodedString(), "transcript": "2+3=",
            "intent": "answer", "maxOutputTokens": 256,
        ])
    }

    private static let pixel = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR42mNgAAAAAgAB5Sfe/AAAAABJRU5ErkJggg=="
    )!

    private func temporaryDatabase() throws -> URL {
        let root = FileManager.default.temporaryDirectory
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("spend.sqlite")
    }

    private func request() throws -> AdmittedRequest {
        let body: [String: Any] = [
            "requestID": UUID().uuidString, "cropPNG": Self.png.base64EncodedString(),
            "neighborhoodPNG": Self.png.base64EncodedString(), "transcript": "2+3=",
            "intent": "answer", "maxOutputTokens": 256,
        ]
        return try JSONDecoder().decode(AdmittedRequest.self, from: JSONSerialization.data(withJSONObject: body))
    }

    private static func reply(finish: String, usage: String) -> Data {
        let spec = #"{\"version\":1}"#
        let candidate = #"{"content":{"parts":[{"text":"\#(spec)"}]},"finishReason":"\#(finish)"}"#
        return Data(#"{"candidates":[\#(candidate)],"usageMetadata":{\#(usage)}}"#.utf8)
    }

    private static func ok(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: GeminiHTTPTransport.endpoint, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private func expect(_ failure: GeminiTransportError, _ transport: GeminiHTTPTransport) async {
        do {
            _ = try await transport.complete(try request())
            XCTFail("Expected \(failure)")
        } catch let error as GeminiTransportError {
            XCTAssertEqual(error, failure)
            XCTAssertFalse("\(error)".contains(Self.secret))
        } catch {
            XCTFail("Expected a content-free transport error")
        }
    }
}

private actor Captured {
    private(set) var request: URLRequest?
    func set(_ request: URLRequest) { self.request = request }
}

private actor Counter {
    private(set) var count = 0
    func bump() { count += 1 }
}
