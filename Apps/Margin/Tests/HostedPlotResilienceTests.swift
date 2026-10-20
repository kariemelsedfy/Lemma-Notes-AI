import InkCore
import Intelligence
import XCTest

@testable import Margin

/// Every way the model's plot reply, or the call itself, can go wrong, and what the writer still gets.
final class HostedPlotResilienceTests: XCTestCase {
    private func reply(_ names: [String], intent: SpecIntent = .plot, sure: Double = 0.9) throws -> ValidatedSpec {
        let functions = names.map { SpecPlotFunction(expression: $0) }
        let blocks =
            functions.isEmpty
            ? []
            : [SpecBlock(placement: .belowSelection, content: .plot(SpecPlot(functions: functions)))]
        // As a hosted reply is: trimmed to fit, then validated.
        return try SpecValidator.validate(
            SpecLeniency.fitted(Spec(read: "y", readConfidence: sure, intent: intent, blocks: blocks)))
    }

    private func drawn(_ reply: ValidatedSpec) -> [String]? {
        guard let checked = HostedPlotSpecProvider.checked(reply),
            case .plot(let plot)? = checked.blocks.first?.content
        else { return nil }
        return plot.functions.map(\.expression)
    }

    func testSeveralFunctionsInOneEntryAreSplit() throws {
        XCTAssertEqual(drawn(try reply(["y = x^2, y = x^3"])), ["x^2", "x^3"])
        XCTAssertEqual(drawn(try reply(["x^2; x^3"])), ["x^2", "x^3"])
    }

    func testOneUnreadableFunctionIsDroppedAndTheRestAreDrawn() throws {
        XCTAssertEqual(drawn(try reply(["x^2", "foo(bar)", "sin(x)"])), ["x^2", "sin(x)"])
        XCTAssertNil(drawn(try reply(["foo(bar)", "???"])), "nothing readable: the device reading is used instead")
    }

    func testAConstantAFormulaWithADomainAndAnEquationAreAllAccepted() throws {
        XCTAssertEqual(drawn(try reply(["5"])), ["5"])
        XCTAssertEqual(drawn(try reply(["y = x^2 for -2 <= x <= 2"])), ["x^2"])
        XCTAssertEqual(drawn(try reply(["x^2 = 4"])), ["x^2", "4"])
        XCTAssertEqual(drawn(try reply(["f(x) = |x - 1|"])), ["abs(x-1)"])
    }

    func testLatexAndOddCharactersFromTheModelAreRead() throws {
        for expression in [
            "\\frac{1}{x}", "\\sin\\left(x\\right)", "x^{2}", "\\sqrt{x}", "2\\cdot x", "sin²x", "√x", "x²",
        ] {
            XCTAssertNotNil(drawn(try reply([expression])), expression)
        }
    }

    func testMoreThanFourFunctionsAreTrimmedToFour() throws {
        let reply = try reply(["x", "2x", "3x", "4x", "5x"].map { $0 })
        XCTAssertEqual(drawn(reply)?.count, 4)
    }

    func testADeclineOrAWrongIntentIsNotUsed() throws {
        XCTAssertNil(HostedPlotSpecProvider.checked(try reply([], sure: 0.1)))
        XCTAssertNil(drawn(try reply(["x^2"], intent: .answer)))
    }

    // MARK: - The whole provider

    private struct Fake: SpecProvider {
        let tier = ModelTier.frontierCloud
        let result: Result<ValidatedSpec, any Error>
        func spec(for request: SpecRequest) async throws -> ValidatedSpec { try result.get() }
    }

    private func request(_ transcript: String, correction: Bool = false) throws -> SpecRequest {
        let ink = InkStroke(points: [
            InkPoint(location: CGPoint(x: 100, y: 100), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
            InkPoint(location: CGPoint(x: 320, y: 126), timeOffset: 1, force: 0.5, altitude: 1, azimuth: 0),
        ])
        let context = try XCTUnwrap(
            SelectionContextBuilder.build(
                strokes: [ink],
                loop: [CGPoint(x: 80, y: 80), CGPoint(x: 340, y: 80), CGPoint(x: 340, y: 150), CGPoint(x: 80, y: 150)],
                pageSize: CGSize(width: 768, height: 1_024)))
        return SpecRequest(
            context: context, intent: .plot,
            selectedAreaReading: SelectionReading(transcript: transcript, confidence: 0.9, isCorrection: correction))
    }

    private func expressions(_ spec: ValidatedSpec) -> [String]? {
        guard case .plot(let plot)? = spec.blocks.first?.content else { return nil }
        return plot.functions.map(\.expression)
    }

    func testAnyHostedFailureFallsBackToTheDeviceReading() async throws {
        let failures: [any Error] = [
            ProxyProviderFailure.offline, ProxyProviderFailure.budgetExceeded, ProxyProviderFailure.refused,
            ProxyProviderFailure.unauthorized, ProxyProviderFailure.invalidResponse,
            ProxyProviderFailure.rejectedSpec("x"), ProxyProviderFailure.undecodable("x"),
            ProxyProviderFailure.responseTooLarge, ProxyProviderFailure.wrongIntent("answer"),
            ProviderError.timeout, ProviderError.transport, ProviderError.thirdPartyConsentRequired,
            SpecValidationError.emptyPlot, URLError(.notConnectedToInternet),
        ]
        for failure in failures {
            let provider = HostedPlotSpecProvider(
                hosted: Fake(result: .failure(failure)), local: LocalPlotSpecProvider(), isReady: { true })
            let spec = try await provider.spec(for: try request("y = x^2"))
            XCTAssertEqual(expressions(spec), ["x^2"], "\(failure)")
        }
    }

    func testACorrectionAndAnUnentitledInstallNeverAskTheModel() async throws {
        let wrong = Fake(result: .success(try reply(["999"])))
        let typed = HostedPlotSpecProvider(hosted: wrong, local: LocalPlotSpecProvider(), isReady: { true })
        let corrected = try await typed.spec(for: try request("y = x^2", correction: true))
        XCTAssertEqual(expressions(corrected), ["x^2"])
        let free = HostedPlotSpecProvider(hosted: wrong, local: LocalPlotSpecProvider(), isReady: { false })
        let unentitled = try await free.spec(for: try request("y = x^2"))
        XCTAssertEqual(expressions(unentitled), ["x^2"])
    }

    func testAGoodHostedReplyBeatsAGarbledDeviceReading() async throws {
        let hosted = Fake(result: .success(try reply(["x^3 + cos(x)"])))
        let provider = HostedPlotSpecProvider(hosted: hosted, local: LocalPlotSpecProvider(), isReady: { true })
        let spec = try await provider.spec(for: try request("v = >c13 (U5 ("))
        XCTAssertEqual(expressions(spec), ["x^3+cos(x)"])
    }

    func testAHostedDeclineThatTheDeviceCannotReadEitherIsReportedNotInvented() async throws {
        let hosted = Fake(result: .success(try reply([], sure: 0.05)))
        let provider = HostedPlotSpecProvider(hosted: hosted, local: LocalPlotSpecProvider(), isReady: { true })
        do {
            _ = try await provider.spec(for: try request("scribble"))
            XCTFail("A scribble must not become a graph")
        } catch let failure as LocalArithmeticFailure {
            XCTAssertEqual(failure, .noFunction(read: "scribble"))
        }
    }

    func testCancellationIsNotSwallowedByTheFallback() async throws {
        let provider = HostedPlotSpecProvider(
            hosted: Fake(result: .failure(CancellationError())), local: LocalPlotSpecProvider(), isReady: { true })
        do {
            _ = try await provider.spec(for: try request("y = x^2"))
            XCTFail("A cancelled ask must stay cancelled")
        } catch is CancellationError {}
    }
}
