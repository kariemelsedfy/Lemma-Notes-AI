import InkCore
import Intelligence
import XCTest

@testable import Margin

final class HostedPlotTests: XCTestCase {
    private struct StubProvider: SpecProvider {
        let tier = ModelTier.onDevice
        let result: Result<ValidatedSpec, Error>
        let counter: Counter
        func spec(for request: SpecRequest) async throws -> ValidatedSpec {
            counter.count += 1
            return try result.get()
        }
    }

    private final class Counter: @unchecked Sendable { var count = 0 }

    private func plotSpec(_ expression: String) throws -> ValidatedSpec {
        let plot = SpecPlot(functions: [SpecPlotFunction(expression: expression)])
        return try SpecValidator.validate(
            Spec(
                read: "y=\(expression)", readConfidence: 0.9, intent: .plot,
                blocks: [SpecBlock(placement: .belowSelection, content: .plot(plot))]))
    }

    private func request(corrected: Bool = false) throws -> SpecRequest {
        let stroke = InkStroke(points: [
            InkPoint(location: CGPoint(x: 100, y: 100), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
            InkPoint(location: CGPoint(x: 220, y: 130), timeOffset: 1, force: 0.5, altitude: 1, azimuth: 0),
        ])
        let loop = [CGPoint(x: 80, y: 80), CGPoint(x: 260, y: 80), CGPoint(x: 260, y: 170), CGPoint(x: 80, y: 170)]
        let context = try XCTUnwrap(
            SelectionContextBuilder.build(
                strokes: [stroke], loop: loop, pageSize: CGSize(width: 1668, height: 2388)))
        return SpecRequest(
            context: context, intent: .plot,
            selectedAreaReading: SelectionReading(transcript: "y=x", confidence: 0.9, isCorrection: corrected))
    }

    private struct Rig {
        let plot: HostedPlotSpecProvider
        let hosted: Counter
        let local: Counter
    }

    private func provider(hosted: Result<ValidatedSpec, Error>, ready: Bool = true) throws -> Rig {
        let hostedCounter = Counter()
        let localCounter = Counter()
        let value = try plotSpec("x^2")
        return Rig(
            plot: HostedPlotSpecProvider(
                hosted: StubProvider(result: hosted, counter: hostedCounter),
                local: StubProvider(result: .success(value), counter: localCounter), isReady: { ready }),
            hosted: hostedCounter, local: localCounter)
    }

    func testAnEntitledInstallUsesTheModelsReadingAndNormalisesIt() async throws {
        let rig = try provider(hosted: .success(try plotSpec("x^3 + cos(x)")))
        let (plot, hosted, local) = (rig.plot, rig.hosted, rig.local)
        let spec = try await plot.spec(for: try request())
        guard case .plot(let drawn)? = spec.blocks.first?.content else { return XCTFail("plot") }
        XCTAssertEqual(drawn.functions.map(\.expression), ["x^3+cos(x)"])
        XCTAssertEqual(hosted.count, 1)
        XCTAssertEqual(local.count, 0)
        XCTAssertTrue(spec.explanation?.contains("x^3+cos(x)") == true)
    }

    func testAFreeInstallNeverCallsTheModel() async throws {
        let rig = try provider(hosted: .success(try plotSpec("x")), ready: false)
        let (plot, hosted, local) = (rig.plot, rig.hosted, rig.local)
        _ = try await plot.spec(for: try request())
        XCTAssertEqual(hosted.count, 0)
        XCTAssertEqual(local.count, 1)
    }

    func testATypedCorrectionIsPlottedAsTypedWithoutTheModel() async throws {
        let rig = try provider(hosted: .success(try plotSpec("x")))
        let (plot, hosted, local) = (rig.plot, rig.hosted, rig.local)
        _ = try await plot.spec(for: try request(corrected: true))
        XCTAssertEqual(hosted.count, 0)
        XCTAssertEqual(local.count, 1)
    }

    func testAHostedFailureFallsBackToTheDeviceReading() async throws {
        let rig = try provider(hosted: .failure(ProxyProviderFailure.offline))
        let (plot, hosted, local) = (rig.plot, rig.hosted, rig.local)
        _ = try await plot.spec(for: try request())
        XCTAssertEqual(hosted.count, 1)
        XCTAssertEqual(local.count, 1)
    }

    func testADeclineOrAnExpressionTheDeviceCannotEvaluateFallsBack() async throws {
        let decline = try SpecValidator.validate(
            Spec(read: "", readConfidence: 0, intent: .plot, blocks: []))
        for reply in [decline, try plotSpec("f(x)(")] {
            let rig = try provider(hosted: .success(reply))
            let (plot, hosted, local) = (rig.plot, rig.hosted, rig.local)
            _ = try await plot.spec(for: try request())
            XCTAssertEqual(hosted.count, 1)
            XCTAssertEqual(local.count, 1)
        }
    }

    func testCancellationIsNotSwallowed() async throws {
        let rig = try provider(hosted: .failure(CancellationError()))
        let (plot, local) = (rig.plot, rig.local)
        do {
            _ = try await plot.spec(for: try request())
            XCTFail("expected cancellation")
        } catch is CancellationError {
            XCTAssertEqual(local.count, 0)
        }
    }
}
