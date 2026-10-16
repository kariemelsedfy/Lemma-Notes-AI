import CoreGraphics
import Foundation
import InkCore

/// Draws a function plot so it looks sketched by hand: axes with arrowheads, tick marks, small numbers and the
/// curve, all slightly wobbly, with pressure that swells and fades along each stroke.
///
/// **Generic on purpose.** A plot is a shape, not a piece of the writer's handwriting, so it uses a built-in print
/// hand for its numbers and never touches the glyph bank. It is also local: nothing here involves a model.
/// Output is deterministic for a given `seed`, so re-rendering a plot gives the same picture.
public struct HandPlotRenderer: Sendable {
    public init() {}

    /// The ink for `plot`, drawn inside `frame`. Throws `unsupportedContent` when no function can be read.
    public func strokes(
        for plot: SpecPlot, in frame: CGRect, penWidth: CGFloat = 4, seed: UInt64 = 0
    ) throws -> [InkStroke] {
        let functions = plot.functions.compactMap { PlotExpression($0.expression) }
        guard !functions.isEmpty, frame.width > 20, frame.height > 20 else {
            throw SuggestionRenderError.unsupportedContent
        }
        // Mixed with the functions so two different plots do not share a wobble, and stable across launches
        // (`Hashable` is randomly seeded per process, so it is not used).
        let signature = functions.map(\.text).joined(separator: ",").utf8.reduce(UInt64(0xCBF2_9CE4_8422_2325)) {
            ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3
        }
        var canvas = Canvas(frame: frame, penWidth: penWidth, seed: seed ^ signature)
        let window = PlotSampler.window(
            for: functions,
            xRange: plot.xRange.flatMap { $0.lowerBound < $0.upperBound ? $0.lowerBound...$0.upperBound : nil },
            yRange: plot.yRange.flatMap { $0.lowerBound < $0.upperBound ? $0.lowerBound...$0.upperBound : nil }
        )
        canvas.drawAxes(window)
        canvas.drawTicksAndNumbers(window)
        for (index, function) in plot.functions.enumerated() where index < functions.count {
            canvas.drawCurve(functions[index], style: function.style, window: window)
        }
        canvas.drawAxisLetters()
        return canvas.strokes
    }
}

// MARK: - Drawing

private struct Canvas {
    let frame: CGRect
    let side: CGFloat
    let inner: CGRect
    let penWidth: CGFloat
    var random: SplitMix64
    var strokes: [InkStroke] = []
    private(set) var axisX: CGFloat = 0
    private(set) var axisY: CGFloat = 0

    init(frame: CGRect, penWidth: CGFloat, seed: UInt64) {
        self.frame = frame
        side = min(frame.width, frame.height)
        // Room around the plot for the numbers and arrowheads.
        inner = frame.insetBy(dx: side * 0.12, dy: side * 0.12)
        self.penWidth = min(max(penWidth, 2), 8)
        random = SplitMix64(seed: seed &+ 0x9E37_79B9)
    }

    func point(_ x: Double, _ y: Double, in window: PlotWindow) -> CGPoint {
        CGPoint(
            x: inner.minX + CGFloat((x - window.xMin) / window.xSpan) * inner.width,
            y: inner.maxY - CGFloat((y - window.yMin) / window.ySpan) * inner.height
        )
    }

    // MARK: Axes

    mutating func drawAxes(_ window: PlotWindow) {
        axisX = point(min(max(0, window.xMin), window.xMax), 0, in: window).x
        axisY = point(0, min(max(0, window.yMin), window.yMax), in: window).y
        let over = side * 0.02
        axis(
            from: CGPoint(x: inner.minX - over * random.unit(), y: axisY),
            to: CGPoint(x: inner.maxX + over * random.unit(), y: axisY))
        axis(
            from: CGPoint(x: axisX, y: inner.maxY + over * random.unit()),
            to: CGPoint(x: axisX, y: inner.minY - over * random.unit()))
    }

    private mutating func axis(from start: CGPoint, to end: CGPoint) {
        // Hand-drawn lines bow a little, and the second end is rarely exactly where the first aimed.
        let length = hypot(end.x - start.x, end.y - start.y)
        let normal = CGPoint(x: -(end.y - start.y) / length, y: (end.x - start.x) / length)
        let bow = length * 0.008 * random.signed()
        let line = (0...8).map { index -> CGPoint in
            let t = CGFloat(index) / 8
            let offset = bow * 4 * t * (1 - t)
            return CGPoint(
                x: start.x + (end.x - start.x) * t + normal.x * offset,
                y: start.y + (end.y - start.y) * t + normal.y * offset)
        }
        add(line, width: 0.9, wobble: side * 0.002)
        arrowHead(at: end, from: start)
        arrowHead(at: start, from: end)
    }

    private mutating func arrowHead(at tip: CGPoint, from tail: CGPoint) {
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let length = side * 0.035 * (0.9 + 0.25 * random.unit())
        let spread = (26 + 8 * random.signed()) * CGFloat.pi / 180
        let left = CGPoint(
            x: tip.x - length * cos(angle - spread), y: tip.y - length * sin(angle - spread))
        let right = CGPoint(
            x: tip.x - length * 0.9 * cos(angle + spread * 1.1), y: tip.y - length * 0.9 * sin(angle + spread * 1.1))
        add([left, tip, right], width: 0.9, wobble: side * 0.0012, spacing: 3)
    }

    // MARK: Ticks and numbers

    mutating func drawTicksAndNumbers(_ window: PlotWindow) {
        let height = side * 0.045
        let gap = side * 0.014
        let xStep = PlotSampler.tickStep(for: window.xSpan)
        let yStep = PlotSampler.tickStep(for: window.ySpan)
        let xTicks = tickValues(window.xMin, window.xMax, xStep)
        let yTicks = tickValues(window.yMin, window.yMax, yStep)
        let xLabelEvery = xTicks.count > 9 ? 2 : 1
        let yLabelEvery = yTicks.count > 9 ? 2 : 1

        for (index, value) in xTicks.enumerated() {
            let x = point(value, 0, in: window).x
            let length = side * 0.014 * (0.8 + 0.4 * random.unit())
            let tilt = 0.12 * random.signed()
            add(
                [
                    CGPoint(x: x - length * tilt, y: axisY - length),
                    CGPoint(x: x + length * tilt, y: axisY + length),
                ], width: 0.8, wobble: 0, spacing: 3)
            guard index % xLabelEvery == 0 else { continue }
            let text = Self.format(value, step: xStep)
            let width = Self.width(of: text, height: height)
            label(text, bottomLeft: CGPoint(x: x - width / 2, y: axisY + length + gap + height), height: height)
        }
        for (index, value) in yTicks.enumerated() {
            let y = point(0, value, in: window).y
            let length = side * 0.014 * (0.8 + 0.4 * random.unit())
            let tilt = 0.12 * random.signed()
            add(
                [
                    CGPoint(x: axisX - length, y: y - length * tilt),
                    CGPoint(x: axisX + length, y: y + length * tilt),
                ], width: 0.8, wobble: 0, spacing: 3)
            guard index % yLabelEvery == 0 else { continue }
            let text = Self.format(value, step: yStep)
            let width = Self.width(of: text, height: height)
            label(
                text, bottomLeft: CGPoint(x: axisX - length - gap - width, y: y + height / 2), height: height)
        }
    }

    /// Multiples of `step` inside the window, without the origin (a hand-drawn graph rarely labels it).
    private func tickValues(_ low: Double, _ high: Double, _ step: Double) -> [Double] {
        guard step > 0 else { return [] }
        let first = Int((low / step).rounded(.up))
        let last = Int((high / step).rounded(.down))
        guard first <= last, last - first < 40 else { return [] }
        return (first...last).filter { $0 != 0 }.map { Double($0) * step }
    }

    static func format(_ value: Double, step: Double) -> String { PlotFormat.label(value, step: step) }

    static func width(of text: String, height: CGFloat) -> CGFloat {
        text.reduce(0) { $0 + (HandStrokeFont.glyph(for: $1)?.advance ?? 0.6) * height }
    }

    // MARK: Curves

    mutating func drawCurve(_ function: PlotExpression, style: SpecPlotStyle, window: PlotWindow) {
        let clip = inner.insetBy(dx: -side * 0.01, dy: -side * 0.01)
        for run in PlotSampler.runs(of: function, in: window) {
            let points = run.map { point(Double($0.x), Double($0.y), in: window) }
            for piece in PlotGeometry.clipped(points, to: clip) {
                switch style {
                case .solid: add(piece, width: 1.15, wobble: side * 0.0028, curve: true)
                case .dashed:
                    for dash in PlotGeometry.dashes(piece, drawn: side * 0.03, gap: side * 0.018) {
                        add(dash, width: 1.1, wobble: side * 0.0015, spacing: 4)
                    }
                case .dotted:
                    for dot in PlotGeometry.dashes(piece, drawn: side * 0.004, gap: side * 0.016) {
                        add(dot, width: 1.3, wobble: 0, spacing: 2)
                    }
                }
            }
        }
    }

    // MARK: Letters

    mutating func drawAxisLetters() {
        let height = side * 0.05
        label(
            "x", bottomLeft: CGPoint(x: inner.maxX - height * 0.4, y: axisY - side * 0.03), height: height)
        label(
            "y", bottomLeft: CGPoint(x: axisX + side * 0.028, y: inner.minY + height * 0.9), height: height)
    }

    /// Draws `text` in the generic print hand with its baseline at `bottomLeft.y`.
    private mutating func label(_ text: String, bottomLeft: CGPoint, height: CGFloat) {
        var cursor = bottomLeft.x
        for character in text {
            guard let glyph = HandStrokeFont.glyph(for: character) else { continue }
            let scale = height * (0.93 + 0.14 * random.unit())
            let lift = height * 0.07 * random.signed()
            let rotation = 0.09 * random.signed()
            for stroke in glyph.strokes {
                let points = stroke.map { unit -> CGPoint in
                    let x = unit.x * scale
                    let y = -unit.y * scale
                    return CGPoint(
                        x: cursor + x * cos(rotation) - y * sin(rotation),
                        y: bottomLeft.y + lift + x * sin(rotation) + y * cos(rotation))
                }
                add(points, width: 0.8, wobble: height * 0.012, spacing: max(1.5, height * 0.1))
            }
            cursor += glyph.advance * height
        }
    }

    // MARK: Stroke building

    /// Resamples `points` evenly, nudges them sideways by a slow wobble, and gives them swelling pressure.
    private mutating func add(
        _ points: [CGPoint], width scale: CGFloat, wobble: CGFloat, spacing: CGFloat = 5, curve: Bool = false
    ) {
        let path = PlotGeometry.resampled(points, spacing: spacing)
        guard path.count > 1 else { return }
        let wavelength = max(side * 0.2 * (0.7 + 0.6 * random.unit()), 30)
        let phase = CGFloat(random.unit()) * 2 * .pi
        let phase2 = CGFloat(random.unit()) * 2 * .pi
        let speed = CGFloat(380 + 120 * random.unit())
        var distance: CGFloat = 0
        var samples: [InkPoint] = []
        let total = zip(path, path.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        for index in path.indices {
            let here = path[index]
            if index > 0 {
                distance += hypot(here.x - path[index - 1].x, here.y - path[index - 1].y)
            }
            let before = path[max(index - 1, 0)]
            let after = path[min(index + 1, path.count - 1)]
            let tangent = CGPoint(x: after.x - before.x, y: after.y - before.y)
            let norm = max(hypot(tangent.x, tangent.y), 0.0001)
            let sway =
                wobble
                * (0.6 * sin(2 * .pi * distance / wavelength + phase)
                    + 0.4 * sin(2 * .pi * distance / (wavelength * 0.37) + phase2))
            let position = CGPoint(x: here.x - tangent.y / norm * sway, y: here.y + tangent.x / norm * sway)
            // Pressure builds after the pen lands, eases through the stroke, and lifts at the end.
            let progress = total > 0 ? distance / total : 0
            let ramp = min(1, min(progress, 1 - progress) / 0.12)
            let force = 0.3 + 0.5 * ramp + 0.08 * sin(2 * .pi * distance / (wavelength * 1.3) + phase)
            let nib = penWidth * scale * (0.82 + 0.3 * force)
            samples.append(
                InkPoint(
                    location: position,
                    timeOffset: TimeInterval(distance / speed),
                    force: min(max(force, 0.1), 1),
                    altitude: .pi / 4,
                    azimuth: 0,
                    size: CGSize(width: nib, height: nib)
                ))
        }
        strokes.append(InkStroke(points: samples))
    }
}

/// SplitMix64: small, seedable, and the reason the same plot renders identically twice.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// In `[0, 1)`.
    mutating func unit() -> CGFloat { CGFloat(Double(next() >> 11) / Double(1 << 53)) }

    /// In `[-1, 1)`.
    mutating func signed() -> CGFloat { unit() * 2 - 1 }
}

/// How tick values are written: no trailing zeros, no "-0".
enum PlotFormat {
    static func label(_ value: Double, step: Double) -> String {
        let decimals = step >= 1 ? 0 : min(3, Int(ceil(-log10(step))))
        var text = String(format: "%.\(decimals)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }
}
