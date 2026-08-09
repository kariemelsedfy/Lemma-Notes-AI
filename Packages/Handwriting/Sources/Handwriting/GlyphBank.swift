import CoreGraphics
import Foundation
import InkCore

/// How a glyph joins its neighbours, for cursive connection (`HANDWRITING.md` §4 step 4).
public enum ConnectionClass: String, Codable, Equatable, Sendable, CaseIterable {
    /// Written as an island; neighbours are not joined to it.
    case isolated
    /// Joins to the following glyph from its exit point.
    case joinsForward
    /// Accepts a join from the preceding glyph at its entry point.
    case joinsBackward
    /// Both.
    case joinsBoth
}

/// One sampled point of a captured glyph, in normalized glyph space.
///
/// Keeps the stylus dynamics rather than just the path: `HANDWRITING.md` §4.1 is blunt
/// that ink with flat pressure reads as fake instantly, and the only way to have the
/// writer's real pressure is to have captured it.
public struct GlyphPoint: Codable, Equatable, Sendable {
    public let location: CGPoint
    /// Seconds from the start of this glyph's first stroke — relative, so a glyph is
    /// reusable in any context.
    public let timeOffset: TimeInterval
    public let force: CGFloat
    public let altitude: CGFloat
    public let azimuth: CGFloat

    public init(location: CGPoint, timeOffset: TimeInterval, force: CGFloat, altitude: CGFloat, azimuth: CGFloat) {
        self.location = location
        self.timeOffset = timeOffset
        self.force = force
        self.altitude = altitude
        self.azimuth = azimuth
    }
}

/// One pen-down-to-pen-up run within a glyph.
///
/// Stored separately rather than flattened, because *where a writer lifts the pen* is part
/// of their hand — §4.1 lists preserving lift patterns as one of the details that decides
/// the "is this mine?" verdict.
public struct GlyphStroke: Codable, Equatable, Sendable {
    public let points: [GlyphPoint]

    public init(points: [GlyphPoint]) {
        self.points = points
    }
}

/// One captured sample of one character.
///
/// **Normalized so x-height is 1 and the baseline is y = 0**, with x measured from the
/// glyph's left edge. Synthesis then scales by the target x-height and never has to know
/// what size the calibration sheet was.
public struct Glyph: Codable, Equatable, Sendable {
    /// Stored as a string because `Character` is not `Codable`. Always one character.
    public let character: String
    public let strokes: [GlyphStroke]
    /// How far the pen advances after this glyph, in x-heights.
    public let advanceWidth: CGFloat
    /// Where a preceding cursive join should land.
    public let entryPoint: CGPoint
    /// Where a join to the next glyph should leave from.
    public let exitPoint: CGPoint
    public let connectionClass: ConnectionClass

    public init(
        character: String,
        strokes: [GlyphStroke],
        advanceWidth: CGFloat,
        entryPoint: CGPoint,
        exitPoint: CGPoint,
        connectionClass: ConnectionClass = .isolated
    ) {
        self.character = character
        self.strokes = strokes
        self.advanceWidth = advanceWidth
        self.entryPoint = entryPoint
        self.exitPoint = exitPoint
        self.connectionClass = connectionClass
    }

    /// The drawn extent in normalized space. Descenders give a positive `maxY`.
    public var bounds: CGRect {
        let locations = strokes.flatMap(\.points).map(\.location)
        guard let first = locations.first else { return .null }
        return locations.dropFirst().reduce(CGRect(origin: first, size: .zero)) { box, point in
            box.union(CGRect(origin: point, size: .zero))
        }
    }
}

/// A writer's captured handwriting.
///
/// **This never leaves the device.** `AGENTS.md` §7 makes that an invariant rather than a
/// preference — it is biometric-adjacent data — and `scripts/check-glyph-bank-privacy.sh`
/// fails the build if anything in this module gains the ability to send it anywhere.
public struct GlyphBank: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    /// Samples keyed by character. Several per character where the capture allowed it,
    /// because reusing one sample for every `e` is the loudest tell there is (§4.1).
    public private(set) var samples: [String: [Glyph]]
    public var style: StoredStyleStats
    public let capturedAt: Date

    public init(
        version: Int = GlyphBank.currentVersion,
        samples: [String: [Glyph]] = [:],
        style: StoredStyleStats = StoredStyleStats(StyleStats.unmeasured),
        capturedAt: Date
    ) {
        self.version = version
        self.samples = samples
        self.style = style
        self.capturedAt = capturedAt
    }

    public var characterCount: Int { samples.count }
    public var sampleCount: Int { samples.values.reduce(0) { $0 + $1.count } }

    public func samples(for character: Character) -> [Glyph] {
        samples[String(character)] ?? []
    }

    public func canRender(_ text: String) -> Bool {
        text.allSatisfy { $0 == " " || !samples(for: $0).isEmpty }
    }

    /// The characters in `text` that have no sample, so a caller can fall back per glyph
    /// or refuse the whole run.
    public func missingCharacters(in text: String) -> Set<Character> {
        Set(text.filter { $0 != " " && samples(for: $0).isEmpty })
    }

    public mutating func add(_ glyph: Glyph) {
        samples[glyph.character, default: []].append(glyph)
    }

    /// Drops every sample of a character, for the "retap any glyph to rewrite it" flow
    /// in `HANDWRITING.md` §3.2.
    public mutating func removeSamples(for character: Character) {
        samples[String(character)] = nil
    }
}

/// `StyleStats` is a measurement type in the synthesis path and deliberately not
/// `Codable`; this is its persisted form, so the two can change independently.
public struct StoredStyleStats: Codable, Equatable, Sendable {
    public let xHeight: CGFloat
    public let slant: CGFloat
    public let lineSpacing: CGFloat
    public let baselineDrift: CGFloat
    public let meanVelocity: CGFloat
    public let meanForce: CGFloat
    public let strokeWidth: CGFloat

    public init(_ stats: StyleStats) {
        xHeight = stats.xHeight
        slant = stats.slant
        lineSpacing = stats.lineSpacing
        baselineDrift = stats.baselineDrift
        meanVelocity = stats.meanVelocity
        meanForce = stats.meanForce
        strokeWidth = stats.strokeWidth
    }

    public var stats: StyleStats {
        StyleStats(
            xHeight: xHeight,
            slant: slant,
            lineSpacing: lineSpacing,
            baselineDrift: baselineDrift,
            meanVelocity: meanVelocity,
            meanForce: meanForce,
            strokeWidth: strokeWidth
        )
    }
}
