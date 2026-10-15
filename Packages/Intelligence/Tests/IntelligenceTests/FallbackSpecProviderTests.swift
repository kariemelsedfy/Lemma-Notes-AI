import InkCore
import XCTest

@testable import Intelligence

final class FallbackSpecProviderTests: XCTestCase {
    private enum Cannot: Error, Equatable { case answer, crash }

    func testPrimaryAnswerNeverTouchesTheFallback() async throws {
        let fallback = Counting(result: .failure(Cannot.crash))
        let provider = FallbackSpecProvider(
            primary: Fixed(.success(try Self.spec("4"))), fallback: fallback, shouldEscalate: { _ in true }
        )
        let spec = try await provider.spec(for: try Self.request())
        XCTAssertEqual(spec.read, "2+2=")
        let calls = await fallback.calls
        XCTAssertEqual(calls, 0)
    }

    func testEscalatesOnlyWhenAskedTo() async throws {
        let fallback = Counting(result: .success(try Self.spec("84")))
        let provider = FallbackSpecProvider(
            primary: Fixed(.failure(Cannot.answer)), fallback: fallback, shouldEscalate: { $0 as? Cannot == .answer }
        )
        _ = try await provider.spec(for: try Self.request())
        let escalated = await fallback.calls
        XCTAssertEqual(escalated, 1)

        let strict = Counting(result: .success(try Self.spec("84")))
        let fault = FallbackSpecProvider(
            primary: Fixed(.failure(Cannot.crash)), fallback: strict, shouldEscalate: { $0 as? Cannot == .answer }
        )
        do {
            _ = try await fault.spec(for: try Self.request())
            XCTFail("A fault must not escalate")
        } catch {
            XCTAssertEqual(error as? Cannot, .crash)
        }
        let none = await strict.calls
        XCTAssertEqual(none, 0)
    }

    func testMissingConsentKeepsThePrimarysOwnError() async throws {
        let gated = ConsentGatedProvider(
            wrapping: Fixed(.success(try Self.spec("84")), tier: .frontierCloud), isConsentGranted: { false }
        )
        let provider = FallbackSpecProvider(
            primary: Fixed(.failure(Cannot.answer)), fallback: gated, shouldEscalate: { _ in true }
        )
        do {
            _ = try await provider.spec(for: try Self.request())
            XCTFail("Nothing should have been answered or sent")
        } catch {
            XCTAssertEqual(error as? Cannot, .answer)
        }
    }

    func testConsentedFallbackAnswersAndFallbackFailuresSurface() async throws {
        let granted = FallbackSpecProvider(
            primary: Fixed(.failure(Cannot.answer)),
            fallback: ConsentGatedProvider(
                wrapping: Fixed(.success(try Self.spec("84")), tier: .frontierCloud), isConsentGranted: { true }
            ),
            shouldEscalate: { _ in true }
        )
        _ = try await granted.spec(for: try Self.request())
        let timing = FallbackSpecProvider(
            primary: Fixed(.failure(Cannot.answer)), fallback: Fixed(.failure(ProviderError.timeout)),
            shouldEscalate: { _ in true }
        )
        do {
            _ = try await timing.spec(for: try Self.request())
            XCTFail("Expected the fallback's timeout")
        } catch {
            XCTAssertEqual(error as? ProviderError, .timeout)
        }
    }

    func testCancellationNeverEscalatesAndTierIsThePrimarys() async throws {
        let fallback = Counting(result: .success(try Self.spec("84")))
        let provider = FallbackSpecProvider(
            primary: Fixed(.failure(CancellationError())), fallback: fallback, shouldEscalate: { _ in true }
        )
        XCTAssertEqual(provider.tier, .onDevice)
        do {
            _ = try await provider.spec(for: try Self.request())
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }
        let calls = await fallback.calls
        XCTAssertEqual(calls, 0)
    }

    // MARK: - helpers

    private static func spec(_ value: String) throws -> ValidatedSpec {
        try SpecValidator.validate(
            Spec(
                read: "2+2=", readConfidence: 0.9, intent: .answer,
                blocks: [SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: .math, value: value)))],
                explanation: nil
            ))
    }

    private static func request() throws -> SpecRequest {
        let context = try XCTUnwrap(
            SelectionContextBuilder.build(
                strokes: [], loop: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)],
                pageSize: CGSize(width: 100, height: 100)
            ))
        return SpecRequest(context: context, intent: .answer)
    }
}

private struct Fixed: SpecProvider {
    let tier: ModelTier
    let result: Result<ValidatedSpec, any Error>

    init(_ result: Result<ValidatedSpec, any Error>, tier: ModelTier = .onDevice) {
        self.result = result
        self.tier = tier
    }

    func spec(for request: SpecRequest) async throws -> ValidatedSpec { try result.get() }
}

private actor Counting: SpecProvider {
    nonisolated let tier = ModelTier.frontierCloud
    private let result: Result<ValidatedSpec, any Error>
    private(set) var calls = 0

    init(result: Result<ValidatedSpec, any Error>) { self.result = result }

    func spec(for request: SpecRequest) async throws -> ValidatedSpec {
        calls += 1
        return try result.get()
    }
}
