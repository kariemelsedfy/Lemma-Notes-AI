import Foundation

/// The intent verb the model resolved for a selection.
public enum SpecIntent: String, Codable, Sendable, CaseIterable {
    case answer
    /// Spelled `continue` on the wire; `continue` is a Swift keyword.
    case continuation = "continue"
    case plot
    case check
    case ask
}

/// The semantic slot a block asks to be placed in.
///
/// The model never emits coordinates (`AI_PIPELINE.md` §3.2). The placement engine
/// resolves each of these to a page rectangle using the occupancy grid.
public enum SpecPlacement: String, Codable, Sendable, CaseIterable {
    case atAnchor
    case belowSelection
    case rightOfSelection
    case nearestFree
}

/// Whether a run of content is math or prose.
public enum SpecContentKind: String, Codable, Sendable, CaseIterable {
    case math
    case text
}

/// One run of renderable content.
///
/// Math always arrives as LaTeX and prose always as plain text, so the wire format uses
/// two different keys. Collapsing them into a single `value` here means every consumer —
/// layout, synthesis, validation — reads one field and switches on `kind` instead of
/// re-deriving which key was populated.
public struct SpecRun: Equatable, Sendable, Codable {
    public let kind: SpecContentKind
    public let value: String

    public init(kind: SpecContentKind, value: String) {
        self.kind = kind
        self.value = value
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case latex
        case text
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(SpecContentKind.self, forKey: .kind)
        self.kind = kind
        switch kind {
        case .math:
            value = try container.decode(String.self, forKey: .latex)
        case .text:
            value = try container.decode(String.self, forKey: .text)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch kind {
        case .math:
            try container.encode(value, forKey: .latex)
        case .text:
            try container.encode(value, forKey: .text)
        }
    }
}

/// A closed numeric interval, carried on the wire as `[min, max]`.
///
/// The array form matches how bounds are already stored in page metadata
/// (`ARCHITECTURE.md` §3.1), so specs and documents describe geometry the same way.
public struct SpecRange: Equatable, Sendable, Codable {
    public let lowerBound: Double
    public let upperBound: Double

    public init(lowerBound: Double, upperBound: Double) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        lowerBound = try container.decode(Double.self)
        upperBound = try container.decode(Double.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(lowerBound)
        try container.encode(upperBound)
    }
}

/// A rectangle in page coordinates, carried on the wire as `[x, y, width, height]`.
public struct SpecRect: Equatable, Sendable, Codable {
    public let originX: Double
    public let originY: Double
    public let width: Double
    public let height: Double

    public init(originX: Double, originY: Double, width: Double, height: Double) {
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
    }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        originX = try container.decode(Double.self)
        originY = try container.decode(Double.self)
        width = try container.decode(Double.self)
        height = try container.decode(Double.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(originX)
        try container.encode(originY)
        try container.encode(width)
        try container.encode(height)
    }
}

/// A model response describing what to write, before validation.
///
/// Decoding this type proves the response has the right *shape*. It does not prove the
/// response is safe to render — that is `SpecValidator`'s job, and only a validated spec
/// may reach the renderer.
public struct Spec: Equatable, Sendable, Codable {
    /// The only wire version this build understands.
    public static let currentVersion = 1

    public let version: Int
    /// What the model believes it read, LaTeX or plain text.
    public let read: String
    public let readConfidence: Double
    public let intent: SpecIntent
    /// Rendered in order. Empty means the model declined to answer.
    public let blocks: [SpecBlock]
    /// Shown in the Ask bar, never inked unless the user asks for it.
    public let explanation: String?
    public let warnings: [String]

    public init(
        version: Int = Spec.currentVersion,
        read: String,
        readConfidence: Double,
        intent: SpecIntent,
        blocks: [SpecBlock],
        explanation: String? = nil,
        warnings: [String] = []
    ) {
        self.version = version
        self.read = read
        self.readConfidence = readConfidence
        self.intent = intent
        self.blocks = blocks
        self.explanation = explanation
        self.warnings = warnings
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case read
        case readConfidence
        case intent
        case blocks
        case explanation
        case warnings
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A model that cannot read the writing often returns a bare decline with fields missing. Those fields
        // default to "read nothing, with no confidence, and no blocks", which renders nothing and tells the
        // writer to try again, instead of failing as an undecodable reply. The intent stays required.
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Spec.currentVersion
        read = try container.decodeIfPresent(String.self, forKey: .read) ?? ""
        readConfidence = try container.decodeIfPresent(Double.self, forKey: .readConfidence) ?? 0
        intent = try container.decode(SpecIntent.self, forKey: .intent)
        blocks = try container.decodeIfPresent([SpecBlock].self, forKey: .blocks) ?? []
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}

/// Decodes model responses into the spec shape.
///
/// Unknown fields are ignored, which is what `Codable` already does. A reply with `blocks`, `read` or
/// `readConfidence` missing decodes as a decline (nothing to render); a missing `intent` or a mistyped field
/// is still a `DecodingError`, so a hallucinated response is never mistaken for a valid answer.
public enum SpecDecoder {
    public static func decode(_ data: Data) throws -> Spec {
        try JSONDecoder().decode(Spec.self, from: data)
    }

    public static func encode(_ spec: Spec) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(spec)
    }
}
