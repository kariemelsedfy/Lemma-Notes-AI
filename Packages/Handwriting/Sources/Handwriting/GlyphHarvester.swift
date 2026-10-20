import CoreGraphics
import Foundation
import InkCore

/// Where one recognised character sits on the page, in page points.
public struct CharacterRegion: Equatable, Sendable {
    public let character: Character
    public let box: CGRect

    public init(character: Character, box: CGRect) {
        self.character = character
        self.box = box
    }
}

/// Learns more of a writer's characters from what they write, so answers vary the way real writing does.
///
/// The calibration sheet captures a few samples of each character; reusing one `e` for every `e` is the loudest
/// tell there is (`HANDWRITING.md` §4.1). Each Ask already gives us a reading of the lasso with a box per
/// character, so the writer's own ink can supply more samples without asking them to do anything.
///
/// **Conservative on purpose.** A wrong sample makes every later answer look worse, and a missed one costs
/// nothing. So a character is kept only when its strokes are unambiguous (no stroke shared with, or half
/// inside, a neighbour's box), its size fits the writer's own samples of it, and it is closer in shape to that
/// character's existing samples than to any other character's. Only characters the bank already holds are
/// learned: that gives the scale reference, and a writer's missing characters are what "Add characters" is for.
///
/// **On-device, always.** This reads and returns glyphs; it has no way to send anything anywhere.
public enum GlyphHarvester {
    /// A character with this many samples is done: more variants stop adding variety.
    public static let samplesPerCharacterLimit = 20
    /// One selection may add at most this many of the same character, so a word like "eeeee" cannot dominate.
    public static let samplesPerCharacterPerSelection = 2
    /// When the model that answered has confirmed what the writing says, a little more is safe to take.
    public static let confirmedSamplesPerCharacterPerSelection = 3

    public struct Outcome: Equatable, Sendable {
        public var glyphs: [Glyph]
        /// Characters that had a clean group of strokes to consider (content-free counts, for diagnostics).
        public var considered: Int

        public static let none = Outcome(glyphs: [], considered: 0)
    }

    /// New samples for `bank` from `strokes`, which must be the writer's own ink (never generated ink).
    ///
    /// - Parameter confirmedText: what the model that answered the question read in this writing. Where it lines up
    ///   with the recogniser's boxes it names each character (an `A` the recogniser called a `4` is an `A`), and a
    ///   character named this way can be learned even if the bank has none of it yet.
    public static func harvest(
        strokes: [InkStroke], regions: [CharacterRegion], bank: GlyphBank, confirmedText: String? = nil
    ) -> Outcome {
        guard !strokes.isEmpty else { return .none }
        let (named, confirmed) = naming(regions, from: confirmedText)
        let groups = cleanGroups(strokes: strokes, regions: named, confirmed: confirmed, bank: bank)
        guard let scale = localScale(of: groups, bank: bank) else { return .none }

        var accepted: [Glyph] = []
        var taken: [String: Int] = [:]
        for group in groups {
            let key = String(group.character)
            let existing = bank.samples(for: group.character)
            let allowed = group.isConfirmed ? confirmedSamplesPerCharacterPerSelection : samplesPerCharacterPerSelection
            guard existing.count + taken[key, default: 0] < samplesPerCharacterLimit, taken[key, default: 0] < allowed,
                let glyph = try? GlyphNormalizer.glyph(for: group.character, from: group.strokes, xHeight: scale),
                isAcceptable(glyph, group: group, existing: existing, bank: bank),
                isNovel(glyph, among: existing + accepted.filter { $0.character == key })
            else { continue }
            accepted.append(glyph)
            taken[key, default: 0] += 1
        }
        return Outcome(glyphs: accepted, considered: groups.count)
    }

    /// The regions with the model's characters where they line up, and which regions were named that way.
    private static func naming(_ regions: [CharacterRegion], from text: String?) -> ([CharacterRegion], Set<Int>) {
        guard let text, let labels = ReadingAlignment.labels(seen: regions.map(\.character), confirmed: text) else {
            return (regions, [])
        }
        let named = regions.enumerated().map { index, region in
            CharacterRegion(character: labels[index] ?? region.character, box: region.box)
        }
        return (named, Set(labels.keys))
    }

    /// Whether a normalised glyph is a believable sample of the character it is claimed to be. A character the model
    /// confirmed skips the shape comparison (that exists to catch the recogniser's misreads) and, if the bank has none
    /// of it, only has to be a sensible size.
    private static func isAcceptable(_ glyph: Glyph, group: Group, existing: [Glyph], bank: GlyphBank) -> Bool {
        if existing.isEmpty { return group.isConfirmed && isPlausibleSize(glyph) }
        return fitsSize(glyph, among: existing) && (group.isConfirmed || isClosestToClaimed(glyph, in: bank))
    }

    private static func isPlausibleSize(_ glyph: Glyph) -> Bool {
        let box = glyph.bounds
        guard !box.isNull else { return false }
        return (0.15...3.5).contains(box.height) && box.width <= 4
    }

    // MARK: - Grouping

    private struct Group {
        let character: Character
        let strokes: [InkStroke]
        let bounds: CGRect
        /// Named by the model that answered, not only by the recogniser.
        let isConfirmed: Bool
    }

    static func isLearnable(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }

    /// Strokes assigned to exactly one character, with that character's group sitting on its box.
    private static func cleanGroups(
        strokes: [InkStroke], regions: [CharacterRegion], confirmed: Set<Int>, bank: GlyphBank
    ) -> [Group] {
        let usable = regions.enumerated().filter { index, region in
            isLearnable(region.character) && region.box.width > 0 && region.box.height > 0
                && (confirmed.contains(index) || !bank.samples(for: region.character).isEmpty)
        }.map { (region: $0.element, isConfirmed: confirmed.contains($0.offset)) }
        guard !usable.isEmpty else { return [] }
        let padded = usable.map {
            $0.region.box.insetBy(dx: -$0.region.box.width * 0.12, dy: -$0.region.box.height * 0.08)
        }

        var assigned = [[InkStroke]](repeating: [], count: usable.count)
        var spoiled = Set<Int>()
        for stroke in strokes {
            let box = InkLineGrouping.bounds(of: [stroke])
            guard !box.isNull else { continue }
            let shares = padded.map { share(of: box, inside: $0) }
            guard let best = shares.indices.max(by: { shares[$0] < shares[$1] }) else { continue }
            let rivals = shares.indices.filter { $0 != best && shares[$0] >= 0.35 }
            if shares[best] >= 0.6 {
                // A stroke that two boxes both claim cannot be told apart from either's own.
                if rivals.isEmpty { assigned[best].append(stroke) } else { spoiled.formUnion([best] + rivals) }
            } else if shares[best] >= 0.25 {
                // Half in the box: this character's group is incomplete or overlaps a neighbour.
                spoiled.insert(best)
            }
        }

        var groups: [Group] = []
        for (index, item) in usable.enumerated() where !spoiled.contains(index) {
            let own = assigned[index]
            guard (1...4).contains(own.count) else { continue }
            let bounds = InkLineGrouping.bounds(of: own)
            guard !bounds.isNull, intersectionOverUnion(bounds, item.region.box) >= 0.35 else { continue }
            groups.append(
                Group(character: item.region.character, strokes: own, bounds: bounds, isConfirmed: item.isConfirmed))
        }
        return groups
    }

    /// How much of `box` lies inside `region`, treating a flat stroke as having a hair of height.
    private static func share(of box: CGRect, inside region: CGRect) -> CGFloat {
        let thick = box.insetBy(dx: -0.5, dy: -0.5)
        let overlap = thick.intersection(region)
        guard !overlap.isNull else { return 0 }
        return (overlap.width * overlap.height) / (thick.width * thick.height)
    }

    private static func intersectionOverUnion(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let overlap = first.intersection(second)
        guard !overlap.isNull else { return 0 }
        let shared = overlap.width * overlap.height
        let total = first.width * first.height + second.width * second.height - shared
        return total > 0 ? shared / total : 0
    }

    // MARK: - Scale

    /// The writer's x-height in this writing, in the same convention the bank was captured in: each clean group
    /// of a character the bank knows says "this character's height is my x-height times its stored height", and
    /// the median of those is the answer. At least two characters have to agree on something.
    private static func localScale(of groups: [Group], bank: GlyphBank) -> CGFloat? {
        let estimates = groups.compactMap { group -> CGFloat? in
            guard let stored = median(bank.samples(for: group.character).map { $0.bounds.height }), stored > 0.05,
                group.bounds.height > 0
            else { return nil }
            return group.bounds.height / stored
        }
        guard estimates.count >= 2, let scale = median(estimates), scale > 2 else { return nil }
        return scale
    }

    private static func median(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }

    // MARK: - Checks

    /// The new sample is about as big as the writer's others of this character (relative to their x-height).
    private static func fitsSize(_ glyph: Glyph, among existing: [Glyph]) -> Bool {
        let box = glyph.bounds
        guard !box.isNull, box.height > 0 else { return false }
        guard let height = median(existing.map { $0.bounds.height }),
            let width = median(existing.map { $0.bounds.width }), height > 0
        else { return false }
        // Widths are loose: a straight `l` or `1` is nearly zero wide and its slant alone changes that a lot.
        return (0.6...1.6).contains(box.height / height) && box.width <= width * 2 + 0.3
            && box.width >= width * 0.5 - 0.15
    }

    /// Closer in shape to its claimed character than to any other: a misread letter fails here without any
    /// threshold having to be tuned to the writer.
    private static func isClosestToClaimed(_ glyph: Glyph, in bank: GlyphBank) -> Bool {
        var claimed = Double.infinity
        var other = Double.infinity
        for (character, samples) in bank.samples {
            for sample in samples {
                let distance = GlyphShape.distance(glyph, sample)
                if character == glyph.character {
                    claimed = min(claimed, distance)
                } else {
                    other = min(other, distance)
                }
            }
        }
        return claimed <= other
    }

    /// Not a near-copy of a sample the bank already holds.
    private static func isNovel(_ glyph: Glyph, among existing: [Glyph]) -> Bool {
        !existing.contains { GlyphShape.distance(glyph, $0) < GlyphShape.duplicateDistance }
    }
}

/// A shape comparison between two glyphs in normalised glyph space.
enum GlyphShape {
    /// Closer than this, in x-heights, and two samples are the same sample.
    static let duplicateDistance = 0.04

    private static let pointCount = 40

    /// Symmetric chamfer distance between the ink of two glyphs: how far, on average, a point of one is from the
    /// nearest point of the other. Independent of stroke order and stroke count.
    static func distance(_ first: Glyph, _ second: Glyph) -> Double {
        let firstPoints = points(of: first)
        let secondPoints = points(of: second)
        guard !firstPoints.isEmpty, !secondPoints.isEmpty else { return .infinity }
        return (meanNearest(from: firstPoints, to: secondPoints) + meanNearest(from: secondPoints, to: firstPoints)) / 2
    }

    private static func meanNearest(from source: [CGPoint], to target: [CGPoint]) -> Double {
        let total = source.reduce(0.0) { sum, point in
            sum + target.map { hypot(Double($0.x - point.x), Double($0.y - point.y)) }.min()!
        }
        return total / Double(source.count)
    }

    /// Points spread evenly along all the ink of a glyph.
    private static func points(of glyph: Glyph) -> [CGPoint] {
        let paths = glyph.strokes.map { $0.points.map(\.location) }.filter { !$0.isEmpty }
        let lengths = paths.map(pathLength)
        let total = lengths.reduce(0, +)
        guard total > 0 else { return paths.flatMap { $0 } }
        return zip(paths, lengths).flatMap { path, length -> [CGPoint] in
            let count = max(2, Int((Double(pointCount) * Double(length / total)).rounded()))
            return sample(path, count: count)
        }
    }

    private static func pathLength(_ path: [CGPoint]) -> CGFloat {
        zip(path, path.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    private static func sample(_ path: [CGPoint], count: Int) -> [CGPoint] {
        let length = pathLength(path)
        guard path.count > 1, length > 0 else { return [path[0]] }
        var result: [CGPoint] = []
        var segment = 0
        var travelled: CGFloat = 0
        for index in 0..<count {
            let target = length * CGFloat(index) / CGFloat(max(count - 1, 1))
            while segment < path.count - 2 {
                let span = distance(path[segment], path[segment + 1])
                guard travelled + span < target else { break }
                travelled += span
                segment += 1
            }
            let from = path[segment]
            let next = path[segment + 1]
            let span = distance(from, next)
            let fraction = span > 0 ? min(max((target - travelled) / span, 0), 1) : 0
            result.append(CGPoint(x: from.x + (next.x - from.x) * fraction, y: from.y + (next.y - from.y) * fraction))
        }
        return result
    }

    private static func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(second.x - first.x, second.y - first.y)
    }
}
