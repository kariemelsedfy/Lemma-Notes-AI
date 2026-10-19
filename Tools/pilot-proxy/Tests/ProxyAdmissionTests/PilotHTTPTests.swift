import Foundation
import XCTest

@testable import ProxyAdmission

final class PilotHTTPTests: XCTestCase {
    private func head(_ text: String) -> Data { Data(text.utf8) }

    func testParsesAPostWithLengthAndLowercasesHeaderNames() throws {
        let parsed = try HTTPHeadParser.parse(
            head("POST /v1/answer HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer abc\r\nContent-Length: 12\r\n\r\n")
        )
        XCTAssertEqual(parsed.method, "POST")
        XCTAssertEqual(parsed.path, "/v1/answer")
        XCTAssertEqual(parsed.contentLength, 12)
        XCTAssertEqual(parsed.headers["authorization"], "Bearer abc")
    }

    func testHeadEndWaitsForTheBlankLineAndCapsTheHead() throws {
        let partial = head("POST /v1/answer HTTP/1.1\r\nHost: x\r\n")
        XCTAssertNil(try HTTPHeadParser.headEnd(in: partial))
        let whole = partial + head("\r\n{body")
        XCTAssertEqual(try HTTPHeadParser.headEnd(in: whole), partial.count + 2)
        XCTAssertThrowsError(try HTTPHeadParser.headEnd(in: Data(repeating: 65, count: 20_000)))
    }

    func testRefusesAmbiguousOrUnsupportedRequests() {
        let bad = [
            "POST /v1/answer HTTP/1.1\r\nHost: x\r\n\r\n",
            "POST /v1/answer HTTP/1.1\r\nContent-Length: 5\r\nContent-Length: 6\r\n\r\n",
            "POST /v1/answer HTTP/1.1\r\nContent-Length: -1\r\n\r\n",
            "POST /v1/answer HTTP/1.1\r\nContent-Length: 7000000\r\n\r\n",
            "POST /v1/answer HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n",
            "DELETE /v1/answer HTTP/1.1\r\n\r\n",
            "POST /v1/answer?x=1 HTTP/1.1\r\nContent-Length: 1\r\n\r\n",
            "POST v1/answer HTTP/1.1\r\nContent-Length: 1\r\n\r\n",
            "POST /v1/answer HTTP/2\r\nContent-Length: 1\r\n\r\n",
            "POST /v1/answer HTTP/1.1\r\n bad header: 1\r\nContent-Length: 1\r\n\r\n",
        ]
        for request in bad {
            XCTAssertThrowsError(try HTTPHeadParser.parse(head(request)), request)
        }
    }

    func testBearerExtractionAndConstantTimeCompare() {
        XCTAssertEqual(PilotRouter.bearer("Bearer abc"), "abc")
        XCTAssertEqual(PilotRouter.bearer("bearer   abc "), "abc")
        XCTAssertNil(PilotRouter.bearer("Basic abc"))
        XCTAssertNil(PilotRouter.bearer("Bearer "))
        XCTAssertNil(PilotRouter.bearer(nil))
        XCTAssertTrue(PilotRouter.constantTimeEqual("abc", "abc"))
        XCTAssertFalse(PilotRouter.constantTimeEqual("abc", "abd"))
        XCTAssertFalse(PilotRouter.constantTimeEqual("abc", "abcd"))
        XCTAssertFalse(PilotRouter.constantTimeEqual("", "a"))
    }
}
