import InkCore
import XCTest

@testable import Intelligence

/// Replies a model can plausibly send for Solve and Explain, and what the writer gets. The rule: a person who pays
/// gets an answer on the page whenever there is anything in the reply worth showing.
final class HostedReplyResilienceTests: XCTestCase {
    private actor Canned: ProxyClientTransport {
        let reply: Data
        init(_ reply: String) { self.reply = Data(reply.utf8) }
        func response(to request: ProxyClientRequest) async throws -> Data { reply }
    }

    private func answer(_ json: String, intent: SpecIntent = .answer) async throws -> ValidatedSpec {
        let provider = ProxySpecProvider.consentGated(transport: Canned(json), isConsentGranted: { true })
        return try await provider.spec(for: try request(intent))
    }

    private func request(_ intent: SpecIntent) throws -> SpecRequest {
        let ink = InkStroke(points: [
            InkPoint(location: CGPoint(x: 100, y: 100), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
            InkPoint(location: CGPoint(x: 320, y: 126), timeOffset: 1, force: 0.5, altitude: 1, azimuth: 0),
        ])
        let context = try XCTUnwrap(
            SelectionContextBuilder.build(
                strokes: [ink],
                loop: [CGPoint(x: 80, y: 80), CGPoint(x: 340, y: 80), CGPoint(x: 340, y: 150), CGPoint(x: 80, y: 150)],
                pageSize: CGSize(width: 768, height: 1_024)))
        let raster = RasterizedSelection(
            crop: InkRasterImage(data: Data("c".utf8), size: CGSize(width: 10, height: 10), scale: 1),
            neighborhood: InkRasterImage(data: Data("n".utf8), size: CGSize(width: 10, height: 10), scale: 1))
        return SpecRequest(
            context: context, intent: intent, rasterizedSelection: raster,
            selectedAreaReading: SelectionReading(transcript: "2+3=", confidence: 0.9))
    }

    private func spec(
        intent: String = "answer", confidence: String = "0.9", blocks: String, extra: String = ""
    ) -> String {
        let head = #"{"version":1,"read":"2+3=","readConfidence":\#(confidence),"intent":"\#(intent)","#
        return head + #""blocks":\#(blocks)\#(extra)}"#
    }

    private func inline(_ kind: String, _ value: String) -> String {
        let key = kind == "math" ? "latex" : "text"
        let escaped = (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return #"{"type":"inline","placement":"atAnchor","content":{"kind":"\#(kind)","\#(key)":\#(escaped)}}"#
    }

    private func firstValue(_ spec: ValidatedSpec) -> String? {
        switch spec.blocks.first?.content {
        case .inline(let run)?: run.value
        case .lines(let lines)?: lines.first?.run.value
        default: nil
        }
    }

    func testTheOrdinaryReplyAndHarmlessVariationsAllWork() async throws {
        let good = [inline("math", "5")]
        let variants: [String] = [
            spec(blocks: "[\(good[0])]"),
            spec(blocks: "[\(good[0])]", extra: #","explanation":null"#),
            spec(blocks: "[\(good[0])]", extra: #","warnings":[]"#),
            spec(blocks: "[\(good[0])]", extra: #","somethingNew":{"a":1},"explanation":"ok""#),
            spec(confidence: "1", blocks: "[\(good[0])]"),
            spec(confidence: "1.7", blocks: "[\(good[0])]"),
            spec(confidence: "-0.2", blocks: "[\(good[0])]"),
        ]
        for json in variants {
            let reply = try await answer(json)
            XCTAssertEqual(firstValue(reply), "5", json)
        }
    }

    func testAnAnswerLabelledAsExplainOrTheOtherWayRoundStillAnswers() async throws {
        let block = inline("text", "photosynthesis")
        let asContinue = try await answer(spec(intent: "continue", blocks: "[\(block)]"), intent: .answer)
        let asAnswer = try await answer(spec(intent: "answer", blocks: "[\(block)]"), intent: .continuation)
        XCTAssertEqual(firstValue(asContinue), "photosynthesis")
        XCTAssertEqual(firstValue(asAnswer), "photosynthesis")
    }

    func testLatexIsWrittenAsPlainCharactersAndBrokenLatexStillShows() async throws {
        let cases: [(String, String)] = [
            (#"\frac{1}{2}"#, "1/2"), (#"x^{2}+1"#, "x^2+1"), (#"\sqrt{x}"#, "sqrt(x)"), (#"\frac{1}{2"#, ""),
            (#"\alpha + \beta"#, ""), (#"\begin{matrix}1&2\end{matrix}"#, ""), (#"$x$"#, "x"), (#"\boxed{4}"#, "4"),
        ]
        for (latex, expected) in cases {
            let reply = try await answer(spec(blocks: "[\(inline("math", latex))]"))
            let shown = try XCTUnwrap(firstValue(reply), latex)
            XCTAssertFalse(shown.contains("\\"), "\(latex) -> \(shown)")
            XCTAssertFalse(shown.contains("{"), "\(latex) -> \(shown)")
            if !expected.isEmpty { XCTAssertEqual(shown, expected, latex) }
        }
    }

    func testLongOrAwkwardTextIsTrimmedNotRefused() async throws {
        let paragraph = String(repeating: "Photosynthesis turns light into sugar. ", count: 60)
        let reply = try await answer(
            spec(intent: "continue", blocks: "[\(inline("text", paragraph))]"), intent: .continuation)
        let shown = try XCTUnwrap(firstValue(reply))
        XCTAssertLessThanOrEqual(shown.count, SpecLimits.standard.maximumContentLength)
        XCTAssertTrue(shown.hasPrefix("Photosynthesis turns light"))
        let withBreaks = try await answer(spec(blocks: "[\(inline("text", "step one\nstep two\r\n\tstep three"))]"))
        XCTAssertEqual(
            firstValue(withBreaks), "step one step two step three")
    }

    func testManyLinesAndBlocksAreCutToTheLimitsAndStillDrawn() async throws {
        let lines = (1...80).map { #"{"kind":"text","text":"line \#($0)","indent":\#($0 % 12)}"# }.joined(
            separator: ",")
        let block = #"{"type":"lines","placement":"belowSelection","content":{"lines":[\#(lines)]}}"#
        let reply = try await answer(spec(blocks: "[\(block)]"))
        guard case .lines(let kept)? = reply.blocks.first?.content else { return XCTFail("no lines") }
        XCTAssertEqual(kept.count, SpecLimits.standard.maximumLines)
        XCTAssertTrue(kept.allSatisfy { $0.indent <= SpecLimits.standard.maximumIndent })
        let manyBlocks = Array(repeating: inline("text", "x"), count: 40).joined(separator: ",")
        let blocks = try await answer(spec(blocks: "[\(manyBlocks)]"))
        XCTAssertEqual(blocks.blocks.count, SpecLimits.standard.maximumBlocks)
    }

    func testAnEmptyPieceIsDroppedAndTheRestIsKept() async throws {
        let reply = try await answer(spec(blocks: "[\(inline("text", "   ")),\(inline("math", "7"))]"))
        XCTAssertEqual(firstValue(reply), "7")
    }

    func testUnusualCharactersPassThroughToTheRenderer() async throws {
        for text in ["→ 5 ≈ 4.99", "😀 done", "naïve café", "x² + y² = r²", "日本語", "∑ᵢ xᵢ", "a\u{200B}b", "e\u{0301}"] {
            let reply = try await answer(spec(blocks: "[\(inline("text", text))]"))
            XCTAssertNotNil(firstValue(reply), text)
        }
    }

    func testADeclineWithNothingToDrawIsADeclineNotAnError() async throws {
        let reply = try await answer(spec(confidence: "0.05", blocks: "[]", extra: #","explanation":"unreadable""#))
        XCTAssertTrue(reply.isDecline)
        let confident = try await answer(spec(confidence: "0.95", blocks: "[]"))
        XCTAssertTrue(confident.isDecline)
    }

    func testWhatIsReallyBrokenIsStillRefusedWithAReason() async throws {
        let broken = [
            "not json", "", "{}", "[]", "null", #"{"version":1}"#, spec(blocks: "[{}]"),
            spec(intent: "plot", blocks: "[\(inline("text", "x"))]"),
            #"{"version":7,"read":"","readConfidence":1,"intent":"answer","blocks":[]}"#,
            String(repeating: "x", count: 70_000),
        ]
        for json in broken {
            do {
                _ = try await answer(json)
                XCTFail("accepted \(json.prefix(40))")
            } catch is ProxyProviderFailure {
            } catch {
                XCTFail("unexpected \(error) for \(json.prefix(40))")
            }
        }
    }
}
