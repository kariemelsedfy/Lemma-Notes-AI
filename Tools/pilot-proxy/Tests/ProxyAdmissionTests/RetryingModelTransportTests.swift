import Foundation
import XCTest

@testable import ProxyAdmission

final class RetryingModelTransportTests: XCTestCase {
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    private enum Step {
        case reply(prompt: Int, output: Int)
        case billed(GeminiError, prompt: Int, output: Int)
        case transport(GeminiTransportError)
    }

    /// Plays back a script of outcomes and records the output budget of each call.
    private final class Script: PilotModelTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var steps: [Step]
        private(set) var budgets: [Int] = []

        init(_ steps: [Step]) { self.steps = steps }

        func complete(_ request: AdmittedRequest) async throws -> GeminiReply {
            let step: Step = lock.withLock {
                budgets.append(request.maxOutputTokens)
                return steps.isEmpty ? .transport(.network) : steps.removeFirst()
            }
            switch step {
            case .reply(let prompt, let output):
                return GeminiReply(specJSON: Data("{}".utf8), promptTokens: prompt, outputTokens: output)
            case .billed(let reason, let prompt, let output):
                throw GeminiBilledFailure(reason: reason, promptTokens: prompt, outputTokens: output)
            case .transport(let failure):
                throw failure
            }
        }
    }

    private func request(tokens: Int = 512) throws -> AdmittedRequest {
        let body: [String: Any] = [
            "requestID": UUID().uuidString, "cropPNG": Self.png.base64EncodedString(),
            "neighborhoodPNG": Self.png.base64EncodedString(), "transcript": "x", "intent": "answer",
            "maxOutputTokens": tokens,
        ]
        return try JSONDecoder().decode(AdmittedRequest.self, from: JSONSerialization.data(withJSONObject: body))
    }

    private func transport(_ script: Script) -> RetryingModelTransport {
        RetryingModelTransport(base: script, pause: {})
    }

    func testASuccessIsNotRetried() async throws {
        let script = Script([.reply(prompt: 100, output: 50)])
        let reply = try await transport(script).complete(try request())
        XCTAssertEqual(reply.outputTokens, 50)
        XCTAssertEqual(script.budgets, [512])
    }

    func testACutOffReplyIsTriedAgainWithTwiceTheRoomAndBothChargesAreCounted() async throws {
        let script = Script([.billed(.truncated, prompt: 1_000, output: 512), .reply(prompt: 1_000, output: 300)])
        let reply = try await transport(script).complete(try request())
        XCTAssertEqual(script.budgets, [512, 1_024])
        XCTAssertEqual(reply.promptTokens, 2_000)
        XCTAssertEqual(reply.outputTokens, 812)
    }

    func testTheRoomNeverGrowsPastTheCeiling() async throws {
        let script = Script([.billed(.truncated, prompt: 1, output: 1_024), .reply(prompt: 1, output: 1)])
        _ = try await transport(script).complete(try request(tokens: 1_024))
        XCTAssertEqual(script.budgets, [1_024, 1_024])
    }

    func testAReplyThatWasNotJSONIsTriedOnce() async throws {
        let script = Script([.billed(.malformed, prompt: 10, output: 5), .reply(prompt: 10, output: 5)])
        _ = try await transport(script).complete(try request())
        XCTAssertEqual(script.budgets.count, 2)
    }

    func testTwoCutOffRepliesFailWithTheTotalBilled() async throws {
        let script = Script([
            .billed(.truncated, prompt: 100, output: 500), .billed(.truncated, prompt: 100, output: 900),
        ])
        do {
            _ = try await transport(script).complete(try request())
            XCTFail("A second failure must surface")
        } catch let failure as GeminiBilledFailure {
            XCTAssertEqual(failure.reason, .truncated)
            XCTAssertEqual(failure.promptTokens, 200)
            XCTAssertEqual(failure.outputTokens, 1_400)
        }
        XCTAssertEqual(script.budgets.count, 2, "one retry only")
    }

    func testRateLimitsServerErrorsAndDroppedConnectionsAreTriedOnceMore() async throws {
        for failure in [GeminiTransportError.status(429), .status(500), .status(503), .status(504), .network] {
            let script = Script([.transport(failure), .reply(prompt: 1, output: 1)])
            _ = try await transport(script).complete(try request())
            XCTAssertEqual(script.budgets.count, 2, "\(failure)")
        }
        let failing = Script([.transport(.status(503)), .transport(.status(503))])
        do {
            _ = try await transport(failing).complete(try request())
            XCTFail("A second failure must surface")
        } catch let failure as GeminiTransportError {
            XCTAssertEqual(failure, .status(503))
        }
        XCTAssertEqual(failing.budgets.count, 2)
    }

    func testWhatARetryCannotFixIsNotRetried() async throws {
        let cases: [Step] = [
            .transport(.status(400)), .transport(.status(403)), .transport(.keyUnavailable), .transport(.notHTTP),
            .billed(.blocked, prompt: 1, output: 1), .billed(.usageMissing, prompt: 1, output: 1),
        ]
        for step in cases {
            let script = Script([step, .reply(prompt: 1, output: 1)])
            _ = try? await transport(script).complete(try request())
            XCTAssertEqual(script.budgets.count, 1, "\(step)")
        }
    }
}
