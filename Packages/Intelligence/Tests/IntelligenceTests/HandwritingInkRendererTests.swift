import Handwriting
import InkCore
import XCTest

@testable import Intelligence

/// `HANDWRITING.md` §8 ships three styles over one pipeline. These tests care about the
/// two ways that goes wrong: drawing nothing, and drawing half a block in each style.
final class HandwritingInkRendererTests: XCTestCase {

    func testTextTheBankKnowsIsDrawnInTheUsersHand() throws {
        let renderer = HandwritingInkRenderer(bank: try Self.bank())

        let strokes = try renderer.strokes(for: Self.placement(text: "sum"), style: Self.style, seed: 1)

        XCTAssertFalse(strokes.isEmpty)
    }

    func testGlyphSizeTracksTheSelectedWritingsXHeightInsteadOfCalibrationSize() throws {
        let renderer = HandwritingInkRenderer(bank: try Self.bank(letters: "s"))
        let smallStyle = Self.style(xHeight: 18)
        let largeStyle = Self.style(xHeight: 36)
        let smallPlacement = Self.placement(
            content: .inline(SpecRun(kind: .text, value: "s")),
            frame: CGRect(x: 40, y: 60, width: 100, height: smallStyle.xHeight * 1.4)
        )
        let largePlacement = Self.placement(
            content: .inline(SpecRun(kind: .text, value: "s")),
            frame: CGRect(x: 40, y: 60, width: 200, height: largeStyle.xHeight * 1.4)
        )

        let small = try renderer.strokes(for: smallPlacement, style: smallStyle, seed: 1)
        let large = try renderer.strokes(for: largePlacement, style: largeStyle, seed: 1)
        let scale = InkLineGrouping.bounds(of: large).height / InkLineGrouping.bounds(of: small).height

        XCTAssertEqual(scale, 2, accuracy: 0.05)
    }

    func testNeatDiffersFromNaturalButStaysInTheSameFrame() throws {
        let bank = try Self.bank()
        let placement = Self.placement(text: "sum")

        let natural = try HandwritingInkRenderer(bank: bank, variation: .natural)
            .strokes(for: placement, style: Self.style, seed: 7)
        let neat = try HandwritingInkRenderer(bank: bank, variation: .neat)
            .strokes(for: placement, style: Self.style, seed: 7)

        // Compared by geometry, not by `==`: every `InkStroke` gets a fresh id, so the
        // obvious `XCTAssertNotEqual(natural, neat)` passes even when the two renders are
        // pixel-identical. It did, and hid how small the difference actually is.
        //
        // §8 asks for "variance reduced ~60%". What `Variation` currently scales is
        // vertical jitter and baseline drift only — not sample choice, spacing or slant —
        // so the difference here is under a point. Filed as M3-08C.
        XCTAssertNotEqual(Self.geometry(natural), Self.geometry(neat))
        XCTAssertTrue(placement.frame.insetBy(dx: -4, dy: -4).contains(InkLineGrouping.bounds(of: neat)))
    }

    func testTheSameSeedDrawsTheSameInkTwice() throws {
        let renderer = HandwritingInkRenderer(bank: try Self.bank())
        let placement = Self.placement(text: "sum")

        let first = try renderer.strokes(for: placement, style: Self.style, seed: 3)
        let second = try renderer.strokes(for: placement, style: Self.style, seed: 3)

        // Re-rendering the same spec must not quietly redraw the answer differently.
        // Compared by geometry: every `InkStroke` gets a fresh id, so `==` never holds
        // across two renders.
        XCTAssertEqual(Self.geometry(first), Self.geometry(second))
    }

    func testAWordWithAnUnknownCharacterFallsBackForTheWholeBlock() throws {
        // Half a sentence in someone's handwriting and half in a typeface is more
        // obviously wrong than either style used consistently.
        let renderer = HandwritingInkRenderer(bank: try Self.bank(letters: "sum"))

        let strokes = try renderer.strokes(for: Self.placement(text: "sum x"), style: Self.style, seed: 1)
        let typeset = try TypesetInkRenderer().strokes(for: Self.placement(text: "sum x"), style: Self.style, seed: 1)

        XCTAssertEqual(Self.geometry(strokes), Self.geometry(typeset))
    }

    func testOneMissingGlyphOnOneLineSendsEveryLineToTheFallback() throws {
        let renderer = HandwritingInkRenderer(bank: try Self.bank(letters: "sum"))
        let placement = Self.placement(lines: ["sum", "sum x"])

        let strokes = try renderer.strokes(for: placement, style: Self.style, seed: 1)
        let typeset = try TypesetInkRenderer().strokes(for: placement, style: Self.style, seed: 1)

        XCTAssertEqual(Self.geometry(strokes), Self.geometry(typeset))
    }

    func testEachLineOfAMultiLineBlockGetsItsOwnJitter() throws {
        let renderer = HandwritingInkRenderer(bank: try Self.bank())

        let strokes = try renderer.strokes(for: Self.placement(lines: ["sum", "sum"]), style: Self.style, seed: 1)

        // The same word twice. Identical jitter repeating down a block is the tell that
        // gives away machine-drawn text (§4.1), so the two lines must differ by more than
        // their vertical offset.
        let lines = InkLineGrouping.lines(from: strokes)
        XCTAssertEqual(lines.count, 2)
        let shapes = lines.map { line -> [[CGPoint]] in
            let owned = strokes.filter { line.strokeIDs.contains($0.id) }
            let origin = InkLineGrouping.bounds(of: owned).origin
            return owned.map { stroke in
                stroke.points.map { CGPoint(x: $0.location.x - origin.x, y: $0.location.y - origin.y) }
            }
        }
        XCTAssertNotEqual(shapes[0], shapes[1])
    }

    func testCanRenderAnswersBeforeTheAnswerIsDrawn() throws {
        let renderer = HandwritingInkRenderer(bank: try Self.bank(letters: "sum"))

        XCTAssertTrue(renderer.canRender("sums"))
        XCTAssertFalse(renderer.canRender("sum x"))
    }

    // MARK: - Fixtures

    /// Stroke geometry without identity. Every render mints fresh `InkStroke` ids, so two
    /// renders of the same thing are never `==` however identical they look.
    private static func geometry(_ strokes: [InkStroke]) -> [[CGPoint]] {
        strokes.map { $0.points.map(\.location) }
    }

    private static let style = StyleStats(
        xHeight: 18,
        slant: 0,
        lineSpacing: 30,
        baselineDrift: 0.5,
        meanVelocity: 320,
        meanForce: 0.55,
        strokeWidth: 3
    )

    private static func style(xHeight: CGFloat) -> StyleStats {
        StyleStats(
            xHeight: xHeight,
            slant: style.slant,
            lineSpacing: xHeight * 1.7,
            baselineDrift: style.baselineDrift,
            meanVelocity: style.meanVelocity,
            meanForce: style.meanForce,
            strokeWidth: style.strokeWidth
        )
    }

    private static func placement(text: String) -> BlockPlacement {
        placement(
            content: .inline(SpecRun(kind: .text, value: text)),
            frame: CGRect(x: 40, y: 60, width: 300, height: 40)
        )
    }

    private static func placement(lines: [String]) -> BlockPlacement {
        placement(
            content: .lines(lines.map { SpecLine(run: SpecRun(kind: .text, value: $0)) }),
            frame: CGRect(x: 40, y: 60, width: 300, height: 80)
        )
    }

    private static func placement(content: SpecBlockContent, frame: CGRect) -> BlockPlacement {
        BlockPlacement(
            block: SpecBlock(placement: .belowSelection, content: content),
            frame: frame,
            requested: .belowSelection,
            usedFallback: false
        )
    }

    /// A bank built from the typeset style, so it renders without a device or a capture.
    private static func bank(letters: String = "abcdefghijklmnopqrstuvwxyz ") throws -> GlyphBank {
        let reference = CGRect(x: 0, y: 0, width: 120, height: 120)
        let xHeight = InkLineGrouping.bounds(of: try TypesetStyle.strokes(for: "x", in: reference)).height
        var bank = GlyphBank(
            style: StoredStyleStats(style),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        for character in Set(letters) where character != " " {
            let rendered = try TypesetStyle.strokes(for: String(character), in: reference)
            bank.add(try GlyphNormalizer.glyph(for: character, from: rendered, xHeight: xHeight))
        }
        return bank
    }
}
