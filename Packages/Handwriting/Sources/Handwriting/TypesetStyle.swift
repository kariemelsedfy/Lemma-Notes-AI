import CoreGraphics
import CoreText
import Foundation
import InkCore

/// Renders text as clean typeset letterforms, drawn as real ink strokes.
///
/// `HANDWRITING.md` §8 calls this "the honest fallback": what the app writes when the user
/// has not calibrated, when their hand does not reconstruct well, or in Exam Mode where
/// pretending to be their handwriting would be exactly wrong. It is also the pivot target
/// if the M3 gate fails, which is why it exists before the synthesizer rather than after.
///
/// **Letterforms come from a real font**, traced from Core Text glyph outlines rather than
/// hand-authored. That buys the full character set — Greek, operators, anything the spec
/// contract can contain — for none of the drawing effort, and it cannot be beaten for
/// legibility by anything hand-drawn.
public enum TypesetStyle {
    public enum Error: Swift.Error, Equatable, Sendable {
        case degenerateFrame
        /// The font has no glyph for something in the string.
        case unsupportedCharacter(Character)
    }

    /// Traced outlines are *stroked*, not filled, so the nib has to be a large enough
    /// fraction of the stem width that a letter reads as solid rather than hollow.
    ///
    /// **Was 0.075, which produced heavy bold display type** — the nib is laid down
    /// centred on the contour, so half of it sits *outside* the letter and every stem
    /// gains a full nib of width. §8 asks for "clean vector text"; beside a person's pen
    /// strokes the old weight looked like a sticker rather than a note (M3-00B).
    ///
    /// 0.025 renders as regular Helvetica and is also *better* for OCR — 5/5 on the sweep
    /// corpus against 4/5 at 0.075, because inflated stems close the counters of `e` and
    /// `a`. Lighter still works too, but the hatch spacing is tied to the nib, so halving
    /// it doubles the stroke count and the render time with it.
    ///
    /// **This ratio is a ceiling on lightness, not a promise.** At a typical answer size it
    /// asks for a 1.5pt nib, and PencilKit — which draws the page, unlike the `InkRasterizer`
    /// this constant was tuned against — will not draw a `.pen` that thin *at all*. The nib
    /// is therefore floored at `InkRenderingLimits.minimumStrokeWidth`, so in practice most
    /// answers render at 3.4pt however light this number gets. Lowering it further changes
    /// nothing on the page. See `renderableNib(_:)` and M2-13.
    public static let nibToHeightRatio: CGFloat = 0.025

    /// The nib to actually draw with: what the ratio asked for, or the narrowest stroke the
    /// page can show, whichever is wider.
    ///
    /// Applied *before* the advance compensation below rather than at the PencilKit
    /// boundary, because the layout has to know the real pen width. Compensating gaps for a
    /// 1.5pt nib and then drawing 3.4pt is how letters merge.
    private static func renderableNib(_ requested: CGFloat) -> CGFloat {
        max(requested, InkRenderingLimits.minimumStrokeWidth)
    }

    /// Lays `text` out inside `frame`, sitting on its baseline.
    ///
    /// Deterministic by construction: unlike the synthesizer there is no jitter, no
    /// sample choice, and no seed. Typeset output is *supposed* to look mechanical.
    public static func strokes(
        for text: String,
        in frame: CGRect,
        style: StyleStats = .unmeasured,
        nibRatio: CGFloat = TypesetStyle.nibToHeightRatio
    ) throws -> [InkStroke] {
        guard frame.width > 0, frame.height > 0 else { throw Error.degenerateFrame }
        guard !text.isEmpty else { return [] }

        let font = CTFontCreateWithName(fontName as CFString, referencePointSize, nil)
        let glyphs = try glyphs(for: text, font: font)
        var metrics = layout(glyphs, font: font, in: frame)
        var nib = renderableNib(metrics.pointSize * nibRatio)

        // A stroked glyph is fatter than its outline by half a nib on each side, so gaps
        // close by a full nib. Left uncompensated, words merge — Vision read
        // "The derivative is 2x" back as "ThederivativelsI2x". Widen the advances by the
        // nib and re-fit, since the widening changes the width the run needs.
        let bleed = nib / metrics.scale
        let compensated = glyphs.map {
            GlyphEntry(glyph: $0.glyph, advance: $0.advance + bleed, isBlank: $0.isBlank)
        }
        metrics = layout(compensated, font: font, in: frame)
        nib = renderableNib(metrics.pointSize * nibRatio)

        var strokes: [InkStroke] = []
        var clock: TimeInterval = 0
        var pen = metrics.origin

        for entry in compensated {
            defer { pen.x += entry.advance * metrics.scale }
            guard !entry.isBlank, let path = CTFontCreatePathForGlyph(font, entry.glyph, nil) else { continue }
            let contours = polylines(of: path)
            // Outline plus hatch fill. Tracing the outline alone leaves hollow letters,
            // which measured *worse* than the crude placeholder font — Vision is trained
            // on solid text and reads outlines badly. That matters beyond the metric: the
            // app reads its own pages with Vision (`AI_PIPELINE.md` §1 `pageText`), so ink
            // our own OCR cannot read breaks asking a follow-up about generated content.
            for polyline in contours + hatchFill(of: contours, spacing: nib / metrics.scale * 0.8) {
                let placed = polyline.map { point in
                    CGPoint(
                        // Core Text's y grows upward; ink coordinates grow downward.
                        x: pen.x + point.x * metrics.scale,
                        y: pen.y - point.y * metrics.scale
                    )
                }
                strokes.append(stroke(through: placed, nib: nib, from: &clock, style: style))
            }
        }
        return strokes
    }

    /// Every character the font can draw. Used to fail closed rather than drop a glyph.
    public static func supports(_ text: String) -> Bool {
        let font = CTFontCreateWithName(fontName as CFString, referencePointSize, nil)
        return (try? glyphs(for: text, font: font)) != nil
    }

    // MARK: - Layout

    private static let fontName = "Helvetica"
    /// Wider than Helvetica's own space (~0.28 em). A stroked glyph eats into the gap on
    /// both sides, and a space that reads as a space to a human still merged words for
    /// Vision at the font's natural value.
    private static let spaceAdvanceRatio: CGFloat = 0.42
    /// Glyph outlines are traced at this size and scaled; large enough that the flattening
    /// tolerance below is fine relative to the letterforms.
    private static let referencePointSize: CGFloat = 100

    private struct GlyphEntry {
        let glyph: CGGlyph
        let advance: CGFloat
        /// Advances the pen and draws nothing. **Not** glyph 0 — that is `.notdef`, which
        /// Helvetica draws as a box, and it was appearing in the output as `[` and `D`.
        var isBlank = false
    }

    private struct Metrics {
        let scale: CGFloat
        let pointSize: CGFloat
        /// The pen position for the first glyph, on the baseline.
        let origin: CGPoint
    }

    private static func glyphs(for text: String, font: CTFont) throws -> [GlyphEntry] {
        var entries: [GlyphEntry] = []
        for character in text {
            if character == " " {
                entries.append(GlyphEntry(glyph: 0, advance: referencePointSize * spaceAdvanceRatio, isBlank: true))
                continue
            }
            let scalars = Array(String(character).utf16)
            var characters = scalars
            var glyphs = [CGGlyph](repeating: 0, count: scalars.count)
            guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, scalars.count), let glyph = glyphs.first,
                glyph != 0
            else {
                throw Error.unsupportedCharacter(character)
            }
            var advance = CGSize.zero
            var single = glyph
            CTFontGetAdvancesForGlyphs(font, .horizontal, &single, &advance, 1)
            entries.append(GlyphEntry(glyph: glyph, advance: advance.width))
        }
        return entries
    }

    /// Fits the run to the frame on both axes and returns the baseline origin.
    private static func layout(_ glyphs: [GlyphEntry], font: CTFont, in frame: CGRect) -> Metrics {
        let totalAdvance = glyphs.reduce(0) { $0 + $1.advance }
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let lineHeight = ascent + descent

        // Honour whichever axis binds first, so descenders never leave the frame the
        // placement engine reserved.
        let byWidth = totalAdvance > 0 ? frame.width / totalAdvance : .greatestFiniteMagnitude
        let byHeight = lineHeight > 0 ? frame.height / lineHeight : .greatestFiniteMagnitude
        let scale = min(byWidth, byHeight)

        // Baseline sits a descender above the frame's bottom, so a `g` reaches the edge
        // and nothing escapes the rectangle placement reserved.
        return Metrics(
            scale: scale,
            pointSize: referencePointSize * scale,
            origin: CGPoint(x: frame.minX, y: frame.maxY - descent * scale)
        )
    }

    // MARK: - Outline tracing

    /// Flattens a glyph outline into one polyline per closed contour.
    private static func polylines(of path: CGPath) -> [[CGPoint]] {
        var contours: [[CGPoint]] = []
        var current: [CGPoint] = []
        var cursor = CGPoint.zero
        var start = CGPoint.zero

        path.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                if current.count > 1 { contours.append(current) }
                cursor = element.points[0]
                start = cursor
                current = [cursor]
            case .addLineToPoint:
                cursor = element.points[0]
                current.append(cursor)
            case .addQuadCurveToPoint:
                let control = element.points[0]
                let end = element.points[1]
                current.append(contentsOf: sampleQuad(from: cursor, control: control, to: end))
                cursor = end
            case .addCurveToPoint:
                let first = element.points[0]
                let second = element.points[1]
                let end = element.points[2]
                current.append(contentsOf: sampleCubic(from: cursor, first, second, to: end))
                cursor = end
            case .closeSubpath:
                current.append(start)
                if current.count > 1 { contours.append(current) }
                current = []
                cursor = start
            @unknown default:
                break
            }
        }
        if current.count > 1 { contours.append(current) }
        return contours
    }

    /// Horizontal scanlines across the glyph interior, so a traced outline reads as solid.
    ///
    /// The plotter approach to filling a shape: for each scanline, find where it crosses
    /// the contours, sort the crossings, and draw between alternate pairs (even-odd, which
    /// is what leaves the counter of an `o` empty). Spacing is tied to the nib so adjacent
    /// passes just overlap — tighter wastes strokes, looser leaves visible banding.
    private static func hatchFill(of contours: [[CGPoint]], spacing: CGFloat) -> [[CGPoint]] {
        guard spacing > 0, !contours.isEmpty else { return [] }
        let allPoints = contours.flatMap { $0 }
        guard let minY = allPoints.map(\.y).min(), let maxY = allPoints.map(\.y).max(), maxY > minY else {
            return []
        }

        var lines: [[CGPoint]] = []
        var scanY = minY + spacing / 2
        while scanY < maxY {
            var crossings: [CGFloat] = []
            for contour in contours {
                for index in 0..<(contour.count - 1) {
                    let start = contour[index]
                    let end = contour[index + 1]
                    // Half-open in y, so a vertex touching the scanline counts once.
                    guard (start.y <= scanY) != (end.y <= scanY) else { continue }
                    let travel = (scanY - start.y) / (end.y - start.y)
                    crossings.append(start.x + travel * (end.x - start.x))
                }
            }
            crossings.sort()
            var pair = 0
            while pair + 1 < crossings.count {
                let left = crossings[pair]
                let right = crossings[pair + 1]
                if right - left > 0.5 {
                    lines.append([CGPoint(x: left, y: scanY), CGPoint(x: right, y: scanY)])
                }
                pair += 2
            }
            scanY += spacing
        }
        return lines
    }

    /// Curve sampling is fixed-step rather than adaptive. At the 100pt reference size a
    /// glyph curve is never long enough for the difference to show once scaled down.
    private static let curveSamples = 8

    private static func sampleQuad(from start: CGPoint, control: CGPoint, to end: CGPoint) -> [CGPoint] {
        (1...curveSamples).map { step in
            let time = CGFloat(step) / CGFloat(curveSamples)
            let inverse = 1 - time
            return CGPoint(
                x: inverse * inverse * start.x + 2 * inverse * time * control.x + time * time * end.x,
                y: inverse * inverse * start.y + 2 * inverse * time * control.y + time * time * end.y
            )
        }
    }

    private static func sampleCubic(
        from start: CGPoint,
        _ first: CGPoint,
        _ second: CGPoint,
        to end: CGPoint
    ) -> [CGPoint] {
        (1...curveSamples).map { step in
            let time = CGFloat(step) / CGFloat(curveSamples)
            let inverse = 1 - time
            let startWeight = inverse * inverse * inverse
            let firstWeight = 3 * inverse * inverse * time
            let secondWeight = 3 * inverse * time * time
            let endWeight = time * time * time
            return CGPoint(
                x: startWeight * start.x + firstWeight * first.x + secondWeight * second.x + endWeight * end.x,
                y: startWeight * start.y + firstWeight * first.y + secondWeight * second.y + endWeight * end.y
            )
        }
    }

    /// Typeset ink is deliberately even: no pressure envelope, no timing jitter.
    ///
    /// The synthesizer varies these to look human (`HANDWRITING.md` §4.1). Doing it here
    /// would be dishonest — this style exists precisely so the app can write something the
    /// user will not mistake for their own hand.
    private static func stroke(
        through points: [CGPoint],
        nib: CGFloat,
        from clock: inout TimeInterval,
        style: StyleStats
    ) -> InkStroke {
        let speed = style.meanVelocity > 0 ? style.meanVelocity : 320
        let force = style.meanForce > 0 ? style.meanForce : 0.6
        var samples: [InkPoint] = []
        samples.reserveCapacity(points.count)

        for (index, point) in points.enumerated() {
            if index > 0 {
                let previous = points[index - 1]
                clock += TimeInterval(hypot(point.x - previous.x, point.y - previous.y) / speed)
            }
            samples.append(
                InkPoint(
                    location: point,
                    timeOffset: clock,
                    force: force,
                    altitude: .pi / 4,
                    azimuth: 0,
                    size: CGSize(width: nib, height: nib)
                )
            )
        }
        return InkStroke(points: samples)
    }
}
