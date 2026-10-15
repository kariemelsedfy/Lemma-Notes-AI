import XCTest

@testable import Intelligence

final class HTTPSProxyTransportTests: XCTestCase {
    private static let secret = "tok-secret-for-tests"
    private static let base = URL(string: "https://pilot.example.test")!

    func testPostsBoundedJSONWithBearerToHttpsPath() async throws {
        let seen = Seen()
        let transport = try XCTUnwrap(
            Self.make(token: Self.secret) { request in
                await seen.set(request)
                return (Data(#"{"version":1}"#.utf8), Self.reply(200))
            })
        let data = try await transport.response(to: Self.request())
        XCTAssertEqual(data, Data(#"{"version":1}"#.utf8))
        let captured = await seen.request
        let sent = try XCTUnwrap(captured)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.url?.absoluteString, "https://pilot.example.test/v1/answer")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer \(Self.secret)")
        XCTAssertNil(sent.url?.query)
        let body = try XCTUnwrap(sent.httpBody)
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(
            Set(keys.keys), ["requestID", "cropPNG", "neighborhoodPNG", "transcript", "intent", "maxOutputTokens"]
        )
        XCTAssertEqual(keys["intent"] as? String, "answer")
    }

    func testRefusesNonHttpsAndMissingTokenBeforeAnyRequest() async throws {
        XCTAssertNil(HTTPSProxyTransport(baseURL: URL(string: "http://pilot.example.test")!, token: { "x" }))
        XCTAssertNil(HTTPSProxyTransport(baseURL: URL(string: "ftp://pilot.example.test")!, token: { "x" }))
        let calls = Counter()
        let transport = try XCTUnwrap(
            Self.make(token: nil) { _ in
                await calls.bump()
                return (Data(), Self.reply(200))
            })
        await expect(.unauthorized, transport)
        let count = await calls.count
        XCTAssertEqual(count, 0)
    }

    func testStatusAndNetworkErrorsReduceToTransportFailures() async throws {
        let cases: [(Int, ProxyTransportFailure)] = [
            (401, .unauthorized), (403, .unauthorized), (429, .overBudget), (504, .timeout),
            (422, .refused), (500, .refused), (302, .refused),
        ]
        for (status, failure) in cases {
            let transport = try XCTUnwrap(
                Self.make(token: Self.secret) { _ in
                    (Data("detail \(Self.secret)".utf8), Self.reply(status))
                })
            await expect(failure, transport)
        }
        let timedOut = try XCTUnwrap(
            Self.make(token: Self.secret) { _ in throw URLError(.timedOut) })
        await expect(.timeout, timedOut)
        let offline = try XCTUnwrap(
            Self.make(token: Self.secret) { _ in
                throw URLError(.notConnectedToInternet)
            })
        await expect(.offline, offline)
    }

    func testOversizedReplyIsRefusedAndCancellationStaysCancellation() async throws {
        let big = try XCTUnwrap(
            Self.make(token: Self.secret) { _ in
                (Data(repeating: 65, count: 70_001), Self.reply(200))
            })
        await expect(.refused, big)
        let cancelled = try XCTUnwrap(
            Self.make(token: Self.secret) { _ in throw CancellationError() })
        do {
            _ = try await cancelled.response(to: Self.request())
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }
    }

    // MARK: - helpers

    private func expect(_ failure: ProxyTransportFailure, _ transport: HTTPSProxyTransport) async {
        do {
            _ = try await transport.response(to: Self.request())
            XCTFail("Expected \(failure)")
        } catch let error as ProxyTransportFailure {
            XCTAssertEqual(error, failure)
            XCTAssertFalse("\(error)".contains(Self.secret))
        } catch {
            XCTFail("Expected a content-free transport failure")
        }
    }

    private static func make(token: String?, _ send: @escaping HTTPSProxyTransport.Send) -> HTTPSProxyTransport? {
        HTTPSProxyTransport(baseURL: base, token: { token }, send: send)
    }

    private static func reply(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: base, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private static func request() -> ProxyClientRequest {
        ProxyClientRequest(
            requestID: UUID(), cropPNG: Data("crop".utf8), neighborhoodPNG: Data("near".utf8),
            transcript: "2+3=", intent: .answer, maxOutputTokens: 256
        )
    }
}

private actor Seen {
    private(set) var request: URLRequest?
    func set(_ request: URLRequest) { self.request = request }
}

private actor Counter {
    private(set) var count = 0
    func bump() { count += 1 }
}
