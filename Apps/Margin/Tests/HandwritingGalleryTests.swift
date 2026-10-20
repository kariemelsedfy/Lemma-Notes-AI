import Handwriting
import XCTest

@testable import Margin

final class HandwritingGalleryTests: XCTestCase {
    private func glyph(_ character: Character, width: CGFloat = 0.8, depth: CGFloat = 0) -> Glyph {
        func point(_ x: CGFloat, _ y: CGFloat) -> GlyphPoint {
            GlyphPoint(location: CGPoint(x: x, y: y), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0)
        }
        return Glyph(
            character: String(character),
            strokes: [GlyphStroke(points: [point(0, -1), point(width, 0), point(width / 2, depth)])],
            advanceWidth: width + 0.2, entryPoint: .zero, exitPoint: .zero)
    }

    private func bank(_ characters: String, variants: Int = 1) -> GlyphBank {
        var bank = GlyphBank(capturedAt: Date(timeIntervalSince1970: 0))
        for character in characters { for _ in 0..<variants { bank.add(glyph(character)) } }
        return bank
    }

    func testCharactersAreGroupedInReadingOrderAndSorted() {
        let sections = HandwritingGallery.sections(from: bank("b?Za7(A1c"))
        XCTAssertEqual(sections.map(\.group), [.lowercase, .uppercase, .digits, .symbols])
        XCTAssertEqual(sections[0].entries.map(\.character), ["a", "b", "c"])
        XCTAssertEqual(sections[1].entries.map(\.character), ["A", "Z"])
        XCTAssertEqual(sections[2].entries.map(\.character), ["1", "7"])
        XCTAssertEqual(Set(sections[3].entries.map(\.character)), ["?", "("])
    }

    func testEachEntryCarriesAllItsVariantsAndEmptyGroupsAreLeftOut() {
        let sections = HandwritingGallery.sections(from: bank("ab", variants: 3))
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].entries.map(\.variants.count), [3, 3])
        XCTAssertTrue(HandwritingGallery.sections(from: GlyphBank(capturedAt: Date())).isEmpty)
    }

    func testACharacterWithNoSamplesLeftIsNotListed() {
        var edited = bank("ab")
        edited.removeSamples(for: "a")
        XCTAssertEqual(HandwritingGallery.sections(from: edited).flatMap(\.entries).map(\.character), ["b"])
    }

    func testAGlyphIsDrawnInsideItsCellWithAFixedBaseline() {
        let size = CGSize(width: 96, height: 84)
        let baseline = HandwritingGallery.baseline(in: size)
        let drawn = HandwritingGallery.points(of: glyph("g", depth: 0.9), in: size).flatMap { $0 }
        XCTAssertFalse(drawn.isEmpty)
        for point in drawn {
            XCTAssertTrue((0...size.width).contains(point.x), "\(point)")
            XCTAssertTrue((0...size.height).contains(point.y), "\(point)")
        }
        // y = 0 in the glyph is the baseline, and one x-height above it is one scale unit up.
        let onBaseline = HandwritingGallery.points(of: glyph("x"), in: size)[0][1]
        XCTAssertEqual(onBaseline.y, baseline, accuracy: 0.001)
        let top = HandwritingGallery.points(of: glyph("x"), in: size)[0][0]
        XCTAssertEqual(baseline - top.y, HandwritingGallery.scale(for: size), accuracy: 0.001)
    }

    func testGlyphsShareOneScaleSoACapitalIsTallerThanALowercaseLetter() {
        let size = CGSize(width: 96, height: 84)
        let small = HandwritingGallery.points(of: glyph("x"), in: size)[0]
        let tall = HandwritingGallery.points(of: glyph("X", width: 0.8).withHeight(1.5), in: size)[0]
        XCTAssertLessThan(tall[0].y, small[0].y)
    }

    func testPenWeightFollowsTheWritersStrokeAndIsClamped() {
        var bank = bank("a")
        bank.normalizationXHeight = 50
        bank.style = StoredStyleStats(
            StyleStats(
                xHeight: 50, slant: 0, lineSpacing: 80, baselineDrift: 0, meanVelocity: 0, meanForce: 0.5,
                strokeWidth: 5))
        XCTAssertEqual(HandwritingGallery.lineWidth(for: bank), 0.1, accuracy: 0.0001)
        bank.style = StoredStyleStats(
            StyleStats(
                xHeight: 50, slant: 0, lineSpacing: 80, baselineDrift: 0, meanVelocity: 0, meanForce: 0.5,
                strokeWidth: 500))
        XCTAssertEqual(HandwritingGallery.lineWidth(for: bank), 0.3, accuracy: 0.0001)
        XCTAssertEqual(HandwritingGallery.lineWidth(for: self.bank("a")), 0.1, accuracy: 0.0001, "unmeasured: default")
    }
}

extension Glyph {
    /// The same glyph with its first point raised to `height` x-heights above the baseline.
    fileprivate func withHeight(_ height: CGFloat) -> Glyph {
        var points = strokes[0].points
        points[0] = GlyphPoint(
            location: CGPoint(x: points[0].location.x, y: -height), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0)
        return Glyph(
            character: character, strokes: [GlyphStroke(points: points)], advanceWidth: advanceWidth,
            entryPoint: entryPoint, exitPoint: exitPoint)
    }
}
