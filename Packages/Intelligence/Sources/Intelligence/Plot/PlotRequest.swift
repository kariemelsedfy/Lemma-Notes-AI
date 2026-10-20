import CoreGraphics
import Foundation

/// Turns what the writer wrote ("y = x^2", "plot sin(x)", "x² plot:") into functions to draw, with no model.
public enum PlotRequest {
    public static let maximumFunctions = 4

    private static let fillerWords = ["plot", "graph", "draw", "sketch", "function", "please", "the", "of"]
    /// "y = x^2 for -2 <= x <= 2": what follows these words describes the domain, which the drawing picks for itself.
    private static let domainWords = "for|from|on|where|when|if|with|over|between|domain|range|in|using"

    /// The functions found in a recognised selection, or nil when there is nothing to plot.
    ///
    /// Filler words and a trailing domain are dropped; `y =`, `f(x) =` (any letter) and `y <` prefixes are stripped;
    /// several functions may be separated by commas, semicolons, new lines, `&` or "and". An equation with both
    /// sides (`x^2 = 4`) draws both sides, so where they cross is the answer; `x^2 - 4 = 0` draws the left side. A
    /// piece with no `x` in it is plotted only when the writer said `y =` (a horizontal line), so a stray sum is not
    /// drawn as a graph.
    public static func functions(from transcript: String) -> [PlotExpression]? {
        var found: [PlotExpression] = []
        for piece in pieces(of: transcript) {
            for expression in expressions(in: piece) where !found.contains(where: { $0.text == expression.text }) {
                found.append(expression)
                if found.count == maximumFunctions { return found }
            }
        }
        return found.isEmpty ? nil : found
    }

    private static func pieces(of transcript: String) -> [String] {
        var text = transcript.lowercased()
        for word in fillerWords {
            text = text.replacingOccurrences(
                of: #"(?<![a-z])\#(word)(?![a-z])"#, with: " ", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: ":", with: " ")
        text = text.replacingOccurrences(of: #"(?<![a-z])and(?![a-z])"#, with: ",", options: .regularExpression)
        for separator in ["&", ";", "\n", "\r", "\u{2028}"] {
            text = text.replacingOccurrences(of: separator, with: ",")
        }
        return text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func expressions(in piece: String) -> [PlotExpression] {
        var body = piece.replacingOccurrences(
            of: #"(?<![a-z0-9])(?:\#(domainWords))(?![a-z]).*$"#, with: "", options: .regularExpression)
        body = strippingOuterBrackets(body.trimmingCharacters(in: .whitespacesAndNewlines))
        var hadY = false
        if let range = body.range(of: #"^(?:[a-z]\(x\)|y\d?)\s*(?:=|[<>≤≥]=?)"#, options: .regularExpression) {
            body.removeSubrange(range)
            hadY = true
        }
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        while body.hasSuffix("=") { body.removeLast() }
        let sides = body.split(separator: "=", omittingEmptySubsequences: false).map(String.init)
        if hadY || sides.count < 2 {
            let formula = sides.first ?? body
            guard let expression = PlotExpression(formula), expression.usesVariable || hadY else { return [] }
            return [expression]
        }
        return equation(left: sides[0], right: sides[1])
    }

    /// Both sides of `A = B`; just `A` when `B` is 0 (the graph's roots are the equation's solutions).
    private static func equation(left: String, right: String) -> [PlotExpression] {
        guard let lhs = PlotExpression(left), lhs.usesVariable else { return [] }
        let rhsText = right.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rhsText != "0", let rhs = PlotExpression(rhsText) else { return [lhs] }
        return [lhs, rhs]
    }

    /// `(y = x^2)` or `[x^2]`: a wrapper that holds the whole piece.
    private static func strippingOuterBrackets(_ text: String) -> String {
        guard text.hasPrefix("("), text.hasSuffix(")") else { return text }
        var depth = 0
        for (offset, character) in text.enumerated() {
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1 }
            if depth == 0, offset < text.count - 1 { return text }
        }
        return String(text.dropFirst().dropLast())
    }
}

/// The part of the plane a plot shows.
public struct PlotWindow: Equatable, Sendable {
    public let xMin: Double
    public let xMax: Double
    public let yMin: Double
    public let yMax: Double

    public init(xMin: Double, xMax: Double, yMin: Double, yMax: Double) {
        self.xMin = xMin
        self.xMax = xMax
        self.yMin = yMin
        self.yMax = yMax
    }

    public var xSpan: Double { xMax - xMin }
    public var ySpan: Double { yMax - yMin }
}

/// Samples functions and chooses a window that shows them the way someone sketching would.
public enum PlotSampler {
    public static let sampleCount = 240

    /// Picks the window: the spec's ranges where given, otherwise a readable one.
    ///
    /// Auto x: ±2π for trigonometry, −1…9 for roots and logs, otherwise ±5 — narrowed (to ±4, ±3, ±2) while that
    /// makes the picture less tall and thin, so `x²` shows as a bowl and not a spike. Auto y: the curve's own
    /// extent (outliers near an asymptote ignored), always including the axis, with a margin.
    public static func window(
        for functions: [PlotExpression], xRange: ClosedRange<Double>? = nil, yRange: ClosedRange<Double>? = nil
    ) -> PlotWindow {
        let xBounds: (Double, Double)
        if let xRange {
            xBounds = (xRange.lowerBound, xRange.upperBound)
        } else if functions.contains(where: \.usesPeriodicFunction) {
            xBounds = (-2 * .pi, 2 * .pi)
        } else if functions.contains(where: \.usesFactorial) {
            // x! climbs fast and has gaps at the negative whole numbers; this window shows both.
            xBounds = (-4, 5)
        } else if functions.contains(where: \.usesRestrictedDomain) {
            xBounds = (-1, 9)
        } else {
            xBounds = bestSymmetricX(for: functions)
        }
        let yBounds: (Double, Double)
        if let yRange {
            yBounds = (yRange.lowerBound, yRange.upperBound)
        } else {
            yBounds = autoY(for: functions, x: xBounds)
        }
        return PlotWindow(xMin: xBounds.0, xMax: xBounds.1, yMin: yBounds.0, yMax: yBounds.1)
    }

    private static func bestSymmetricX(for functions: [PlotExpression]) -> (Double, Double) {
        let candidates: [Double] = [5, 4, 3, 2]
        var best = (half: 5.0, ratio: Double.infinity)
        for half in candidates {
            let y = extent(of: functions, x: (-half, half))
            let ratio = (y.1 - y.0) / (2 * half)
            if ratio <= 1.5 { return (-half, half) }
            if ratio < best.ratio - 0.0001 { best = (half, ratio) }
        }
        // Nothing looked balanced (a line, a steep cubic): the widest view is the least surprising.
        return (-5, 5)
    }

    /// The central extent of the curves over `x`, ignoring the few samples an asymptote throws far away.
    private static func extent(of functions: [PlotExpression], x: (Double, Double)) -> (Double, Double) {
        var values: [Double] = []
        for function in functions {
            for index in 0...sampleCount {
                let t = x.0 + (x.1 - x.0) * Double(index) / Double(sampleCount)
                let y = function.value(at: t)
                if y.isFinite { values.append(y) }
            }
        }
        guard !values.isEmpty else { return (-1, 1) }
        values.sort()
        let low = values[Int(Double(values.count - 1) * 0.02)]
        let high = values[Int(Double(values.count - 1) * 0.98)]
        return (low, high)
    }

    private static func autoY(for functions: [PlotExpression], x: (Double, Double)) -> (Double, Double) {
        var (low, high) = extent(of: functions, x: x)
        low = min(low, 0)
        high = max(high, 0)
        if high - low < 1e-9 { (low, high) = (-1, 1) }
        let pad = (high - low) * 0.12
        return (low - pad, high + pad)
    }

    /// Data-space points of one function, broken into runs wherever it is undefined, leaves the window, or jumps
    /// across an asymptote (so `1/x` is two branches, not a line joining them).
    public static func runs(of function: PlotExpression, in window: PlotWindow) -> [[CGPoint]] {
        var runs: [[CGPoint]] = []
        var current: [CGPoint] = []
        var previous: Double?
        let margin = window.ySpan * 0.35
        let top = window.yMax + margin
        let bottom = window.yMin - margin
        for index in 0...sampleCount {
            let x = window.xMin + window.xSpan * Double(index) / Double(sampleCount)
            let y = function.value(at: x)
            let visible = y.isFinite && y <= top && y >= bottom
            let jumps = previous.map { abs(y - $0) > window.ySpan * 1.5 } ?? false
            if visible && !jumps {
                current.append(CGPoint(x: x, y: y))
            } else {
                if current.count > 1 { runs.append(current) }
                current = []
                if visible { current.append(CGPoint(x: x, y: y)) }
            }
            previous = y.isFinite ? y : nil
        }
        if current.count > 1 { runs.append(current) }
        return runs
    }

    /// A round tick spacing giving roughly five to nine marks across `span`.
    public static func tickStep(for span: Double) -> Double {
        guard span > 0, span.isFinite else { return 1 }
        let raw = span / 8
        let magnitude = pow(10, floor(log10(raw)))
        for multiple in [1.0, 2.0, 5.0, 10.0] where multiple * magnitude >= raw {
            return multiple * magnitude
        }
        return 10 * magnitude
    }
}
