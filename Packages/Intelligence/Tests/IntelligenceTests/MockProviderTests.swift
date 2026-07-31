import InkCore
import XCTest

@testable import Intelligence

final class MockProviderTests: XCTestCase {
    func testReturnsTheFixtureRegisteredForTheRequest() async throws {
        let request = try Self.request()
        let provider = MockProvider(fixtures: [request.cacheKey: Self.answerSpec])

        let validated = try await provider.spec(for: request)

        XCTAssertEqual(validated.intent, .answer)
        XCTAssertEqual(validated.blocks.count, 1)
        XCTAssertEqual(provider.tier, .mock)
    }

    func testUnknownFixtureFailsWithItsKey() async throws {
        let request = try Self.request()
        let provider = MockProvider()

        await assertThrowsAsync(try await provider.spec(for: request)) { error in
            XCTAssertEqual(error as? ProviderError, .unknownFixture(request.cacheKey))
        }
    }

    func testInjectedTransportFailureIsReported() async throws {
        let request = try Self.request()
        let provider = MockProvider(
            fixtures: [request.cacheKey: Self.answerSpec],
            behavior: .init(failure: .transport)
        )

        await assertThrowsAsync(try await provider.spec(for: request)) { error in
            XCTAssertEqual(error as? ProviderError, .transport)
        }
    }

    func testCorruptedSpecFailsValidationRatherThanReachingTheCaller() async throws {
        let request = try Self.request()
        let provider = MockProvider(
            fixtures: [request.cacheKey: Self.answerSpec],
            behavior: .init(corruptsSpec: true)
        )

        await assertThrowsAsync(try await provider.spec(for: request)) { error in
            XCTAssertEqual(error as? SpecValidationError, .lowReadConfidence(0.1))
        }
    }

    func testLatencyIsCancellable() async throws {
        let request = try Self.request()
        let provider = MockProvider(
            fixtures: [request.cacheKey: Self.answerSpec],
            behavior: .init(latency: .seconds(30))
        )

        let task = Task { try await provider.spec(for: request) }
        // Let the request reach the sleep before cancelling it.
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()

        await assertThrowsAsync(try await task.value) { error in
            XCTAssertTrue(error is CancellationError, "Expected cancellation, got \(error).")
        }
        let requested = await provider.requestedKeys
        XCTAssertEqual(requested, [request.cacheKey])
    }

    func testBehaviorCanBeChangedBetweenRequests() async throws {
        let request = try Self.request()
        let provider = MockProvider(fixtures: [request.cacheKey: Self.answerSpec])

        _ = try await provider.spec(for: request)
        await provider.setBehavior(.init(failure: .timeout))

        await assertThrowsAsync(try await provider.spec(for: request)) { error in
            XCTAssertEqual(error as? ProviderError, .timeout)
        }
    }

    // MARK: - Cache key

    func testCacheKeyIsStableAcrossIdenticalRequests() throws {
        XCTAssertEqual(try Self.request().cacheKey, try Self.request().cacheKey)
    }

    func testCacheKeyChangesWithTheIntentHint() throws {
        let withoutHint = try Self.request()
        let withHint = SpecRequest(context: withoutHint.context, intent: .plot)

        XCTAssertNotEqual(withoutHint.cacheKey, withHint.cacheKey)
    }

    func testCacheKeyChangesWithTheSelectedInk() throws {
        let first = try Self.request()
        let second = try Self.request(origin: CGPoint(x: 400, y: 400))

        XCTAssertNotEqual(first.cacheKey, second.cacheKey)
    }

    // MARK: - Fixtures

    private static func request(origin: CGPoint = CGPoint(x: 100, y: 100)) throws -> SpecRequest {
        let stroke = InkStroke(points: [
            InkPoint(location: origin, timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
            InkPoint(
                location: CGPoint(x: origin.x + 120, y: origin.y + 30),
                timeOffset: 1,
                force: 0.5,
                altitude: 1,
                azimuth: 0
            ),
        ])
        let loop = [
            CGPoint(x: origin.x - 20, y: origin.y - 20),
            CGPoint(x: origin.x + 160, y: origin.y - 20),
            CGPoint(x: origin.x + 160, y: origin.y + 70),
            CGPoint(x: origin.x - 20, y: origin.y + 70),
        ]
        let context = try XCTUnwrap(
            SelectionContextBuilder.build(
                strokes: [stroke],
                loop: loop,
                pageSize: CGSize(width: 1668, height: 2388)
            )
        )
        return SpecRequest(context: context)
    }

    private static let answerSpec = Spec(
        read: "2+2=",
        readConfidence: 0.97,
        intent: .answer,
        blocks: [SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: .math, value: "4")))],
        explanation: "Addition."
    )
}

/// `XCTAssertThrowsError` has no async form; this keeps the failure message at the call site.
func assertThrowsAsync<Success>(
    _ expression: @autoclosure () async throws -> Success,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ handler: (any Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error but the call succeeded.", file: file, line: line)
    } catch {
        handler(error)
    }
}
