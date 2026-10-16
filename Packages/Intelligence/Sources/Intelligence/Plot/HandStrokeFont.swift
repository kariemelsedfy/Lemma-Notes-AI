import CoreGraphics
import Foundation

/// A small generic print hand for plot labels: digits, minus, point, `x` and `y`.
///
/// Not the writer's handwriting and not meant to be: a plot is drawn the same for everyone. Glyphs are pen
/// paths in a unit box (y up, baseline 0, digit height 1), one array of points per pen-down stroke.
enum HandStrokeFont {
    struct Glyph {
        let strokes: [[CGPoint]]
        /// Horizontal room the glyph takes, in units of its height.
        let advance: CGFloat
    }

    static func glyph(for character: Character) -> Glyph? { glyphs[character] }

    private static let glyphs: [Character: Glyph] = [
        "0": Glyph(strokes: [loop(Oval(0.3, 0.5, 0.26, 0.5), from: 95, sweep: -370)], advance: 0.62),
        "1": Glyph(strokes: [[pen(0.1, 0.78), pen(0.3, 1.0), pen(0.3, 0.5), pen(0.3, 0)]], advance: 0.5),
        "2": Glyph(
            strokes: [
                arc(Oval(0.3, 0.72, 0.26, 0.26), from: 165, to: -40)
                    + [pen(0.28, 0.35), pen(0.05, 0), pen(0.3, 0.02), pen(0.56, 0)]
            ], advance: 0.64),
        "3": Glyph(
            strokes: [
                arc(Oval(0.28, 0.76, 0.22, 0.22), from: 150, to: -90)
                    + arc(Oval(0.28, 0.28, 0.27, 0.27), from: 90, to: -150)
            ], advance: 0.62),
        "4": Glyph(
            strokes: [[pen(0.42, 0), pen(0.42, 1.0), pen(0.02, 0.3), pen(0.3, 0.3), pen(0.6, 0.3)]], advance: 0.66),
        "5": Glyph(
            strokes: [
                [pen(0.52, 1.0), pen(0.2, 1.0), pen(0.1, 0.55)] + arc(Oval(0.28, 0.3, 0.29, 0.29), from: 120, to: -140)
            ], advance: 0.62),
        "6": Glyph(
            strokes: [
                [pen(0.5, 0.95), pen(0.28, 0.82), pen(0.1, 0.5)]
                    + loop(Oval(0.3, 0.28, 0.25, 0.28), from: 180, sweep: 370)
            ], advance: 0.62),
        "7": Glyph(
            strokes: [[pen(0.04, 1.0), pen(0.3, 1.0), pen(0.56, 1.0), pen(0.3, 0.45), pen(0.2, 0)]], advance: 0.6),
        "8": Glyph(
            strokes: [
                loop(Oval(0.3, 0.76, 0.2, 0.22), from: 90, sweep: 360),
                loop(Oval(0.3, 0.27, 0.26, 0.27), from: 90, sweep: -360),
            ], advance: 0.62),
        "9": Glyph(
            strokes: [
                loop(Oval(0.3, 0.72, 0.25, 0.28), from: 0, sweep: 360)
                    + [pen(0.55, 0.62), pen(0.48, 0.3), pen(0.3, 0.08), pen(0.1, 0.04)]
            ], advance: 0.62),
        "-": Glyph(strokes: [[pen(0.04, 0.4), pen(0.28, 0.41), pen(0.52, 0.4)]], advance: 0.62),
        ".": Glyph(strokes: [[pen(0.08, 0.03), pen(0.1, 0.0)]], advance: 0.3),
        "x": Glyph(strokes: [[pen(0.05, 0.7), pen(0.55, 0)], [pen(0.55, 0.7), pen(0.05, 0)]], advance: 0.62),
        "y": Glyph(
            strokes: [[pen(0.05, 0.7), pen(0.3, 0.05)], [pen(0.55, 0.7), pen(0.2, -0.3), pen(0.1, -0.32)]],
            advance: 0.62),
    ]

    /// Whether every character of `text` has a glyph.
    static func canDraw(_ text: String) -> Bool { text.allSatisfy { glyph(for: $0) != nil } }

    private static func pen(_ across: CGFloat, _ height: CGFloat) -> CGPoint { CGPoint(x: across, y: height) }

    /// An ellipse: centre and radii, in glyph units.
    private struct Oval {
        let centreX: CGFloat
        let centreY: CGFloat
        let radiusX: CGFloat
        let radiusY: CGFloat

        init(_ centreX: CGFloat, _ centreY: CGFloat, _ radiusX: CGFloat, _ radiusY: CGFloat) {
            self.centreX = centreX
            self.centreY = centreY
            self.radiusX = radiusX
            self.radiusY = radiusY
        }
    }

    /// Points along an arc of `oval` from `from` to `to` degrees (counter-clockwise when `to` > `from`).
    private static func arc(_ oval: Oval, from: CGFloat, to end: CGFloat, steps: Int = 10) -> [CGPoint] {
        (0...steps).map { index in
            let degrees = from + (end - from) * CGFloat(index) / CGFloat(steps)
            let radians = degrees * .pi / 180
            return CGPoint(
                x: oval.centreX + oval.radiusX * cos(radians), y: oval.centreY + oval.radiusY * sin(radians))
        }
    }

    private static func loop(_ oval: Oval, from: CGFloat, sweep: CGFloat) -> [CGPoint] {
        arc(oval, from: from, to: from + sweep, steps: 18)
    }
}
