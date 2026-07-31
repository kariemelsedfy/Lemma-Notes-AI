import Foundation

/// One line inside a `lines` block.
public struct SpecLine: Equatable, Sendable, Codable {
    public let run: SpecRun
    /// Indentation depth in levels, not points; the renderer owns the point size.
    public let indent: Int

    public init(run: SpecRun, indent: Int = 0) {
        self.run = run
        self.indent = indent
    }

    private enum CodingKeys: String, CodingKey {
        case indent
    }

    public init(from decoder: any Decoder) throws {
        run = try SpecRun(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        indent = try container.decodeIfPresent(Int.self, forKey: .indent) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        try run.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(indent, forKey: .indent)
    }
}

/// How a plotted curve is stroked.
public enum SpecPlotStyle: String, Codable, Sendable, CaseIterable {
    case solid
    case dashed
    case dotted
}

/// How a plot's background grid is drawn.
public enum SpecGridStyle: String, Codable, Sendable, CaseIterable {
    case none
    case light
    case full
}

/// One curve in a plot.
///
/// The expression is evaluated locally. Models are not asked for sample points because
/// they get them subtly wrong (`AI_PIPELINE.md` §6).
public struct SpecPlotFunction: Equatable, Sendable, Codable {
    public let expression: String
    public let domain: SpecRange?
    public let style: SpecPlotStyle

    public init(expression: String, domain: SpecRange? = nil, style: SpecPlotStyle = .solid) {
        self.expression = expression
        self.domain = domain
        self.style = style
    }

    private enum CodingKeys: String, CodingKey {
        case expr
        case domain
        case style
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        expression = try container.decode(String.self, forKey: .expr)
        domain = try container.decodeIfPresent(SpecRange.self, forKey: .domain)
        style = try container.decodeIfPresent(SpecPlotStyle.self, forKey: .style) ?? .solid
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(expression, forKey: .expr)
        try container.encodeIfPresent(domain, forKey: .domain)
        try container.encode(style, forKey: .style)
    }
}

/// A plot block's payload.
public struct SpecPlot: Equatable, Sendable, Codable {
    public let functions: [SpecPlotFunction]
    public let xRange: SpecRange?
    public let yRange: SpecRange?
    public let xLabel: String?
    public let yLabel: String?
    public let gridStyle: SpecGridStyle

    public init(
        functions: [SpecPlotFunction],
        xRange: SpecRange? = nil,
        yRange: SpecRange? = nil,
        xLabel: String? = nil,
        yLabel: String? = nil,
        gridStyle: SpecGridStyle = .light
    ) {
        self.functions = functions
        self.xRange = xRange
        self.yRange = yRange
        self.xLabel = xLabel
        self.yLabel = yLabel
        self.gridStyle = gridStyle
    }

    private enum CodingKeys: String, CodingKey {
        case functions
        case xRange
        case yRange
        case xLabel
        case yLabel
        case gridStyle
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        functions = try container.decode([SpecPlotFunction].self, forKey: .functions)
        xRange = try container.decodeIfPresent(SpecRange.self, forKey: .xRange)
        yRange = try container.decodeIfPresent(SpecRange.self, forKey: .yRange)
        xLabel = try container.decodeIfPresent(String.self, forKey: .xLabel)
        yLabel = try container.decodeIfPresent(String.self, forKey: .yLabel)
        gridStyle = try container.decodeIfPresent(SpecGridStyle.self, forKey: .gridStyle) ?? .light
    }
}

/// The kind of correction mark drawn over existing ink.
public enum SpecMarkKind: String, Codable, Sendable, CaseIterable {
    case strike
    case circle
    case caret
    case check
    case cross
}

/// What a correction mark points at.
///
/// Stroke indices need the revalidation described in `ARCHITECTURE.md` §3.1; bounds are
/// the fallback when the model located something OCR saw but stroke matching did not.
public enum SpecMarkTarget: Equatable, Sendable {
    case strokeIndices([Int])
    case bounds(SpecRect)
}

/// One correction mark.
public struct SpecMark: Equatable, Sendable, Codable {
    public let kind: SpecMarkKind
    public let target: SpecMarkTarget

    public init(kind: SpecMarkKind, target: SpecMarkTarget) {
        self.kind = kind
        self.target = target
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case targetStrokeIndices
        case targetBounds
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(SpecMarkKind.self, forKey: .kind)
        if let indices = try container.decodeIfPresent([Int].self, forKey: .targetStrokeIndices) {
            target = .strokeIndices(indices)
        } else if let bounds = try container.decodeIfPresent(SpecRect.self, forKey: .targetBounds) {
            target = .bounds(bounds)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .targetStrokeIndices,
                in: container,
                debugDescription: "A mark needs either targetStrokeIndices or targetBounds."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch target {
        case .strokeIndices(let indices):
            try container.encode(indices, forKey: .targetStrokeIndices)
        case .bounds(let bounds):
            try container.encode(bounds, forKey: .targetBounds)
        }
    }
}

/// Which margin a note is written in.
public enum SpecNoteSide: String, Codable, Sendable, CaseIterable {
    case left
    case right
    case below
}

/// A marginal annotation.
public struct SpecNote: Equatable, Sendable, Codable {
    public let text: String
    public let side: SpecNoteSide

    public init(text: String, side: SpecNoteSide) {
        self.text = text
        self.side = side
    }
}

/// The renderable payload of a block, tagged on the wire by `type`.
public enum SpecBlockContent: Equatable, Sendable {
    case inline(SpecRun)
    case lines([SpecLine])
    case plot(SpecPlot)
    case marks([SpecMark])
    case note(SpecNote)

    public var type: SpecBlockType {
        switch self {
        case .inline: .inline
        case .lines: .lines
        case .plot: .plot
        case .marks: .marks
        case .note: .note
        }
    }
}

/// The block discriminator carried in `type`.
public enum SpecBlockType: String, Codable, Sendable, CaseIterable {
    case inline
    case lines
    case plot
    case marks
    case note
}

/// One renderable unit of a spec.
public struct SpecBlock: Equatable, Sendable, Codable {
    public let placement: SpecPlacement
    public let content: SpecBlockContent

    public init(placement: SpecPlacement, content: SpecBlockContent) {
        self.placement = placement
        self.content = content
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case placement
        case content
    }

    private enum ContentKeys: String, CodingKey {
        case lines
        case marks
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(SpecBlockType.self, forKey: .type)
        placement = try container.decode(SpecPlacement.self, forKey: .placement)
        switch type {
        case .inline:
            content = .inline(try container.decode(SpecRun.self, forKey: .content))
        case .lines:
            let nested = try container.nestedContainer(keyedBy: ContentKeys.self, forKey: .content)
            content = .lines(try nested.decode([SpecLine].self, forKey: .lines))
        case .plot:
            content = .plot(try container.decode(SpecPlot.self, forKey: .content))
        case .marks:
            let nested = try container.nestedContainer(keyedBy: ContentKeys.self, forKey: .content)
            content = .marks(try nested.decode([SpecMark].self, forKey: .marks))
        case .note:
            content = .note(try container.decode(SpecNote.self, forKey: .content))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(content.type, forKey: .type)
        try container.encode(placement, forKey: .placement)
        switch content {
        case .inline(let run):
            try container.encode(run, forKey: .content)
        case .lines(let lines):
            var nested = container.nestedContainer(keyedBy: ContentKeys.self, forKey: .content)
            try nested.encode(lines, forKey: .lines)
        case .plot(let plot):
            try container.encode(plot, forKey: .content)
        case .marks(let marks):
            var nested = container.nestedContainer(keyedBy: ContentKeys.self, forKey: .content)
            try nested.encode(marks, forKey: .marks)
        case .note(let note):
            try container.encode(note, forKey: .content)
        }
    }
}
