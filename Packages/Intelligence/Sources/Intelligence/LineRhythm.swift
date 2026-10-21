import CoreGraphics

/// The uneven spacing between the lines of an answer, so a block does not read as a ruled table.
///
/// Placement reserves room for every line at the full spacing; each gap actually drawn is a random share of it, from
/// two thirds to all (the writer asked for gaps between half and three quarters of their own spacing, and the full
/// spacing here is three quarters). The gaps are different from one another, fixed by the seed so redrawing the same
/// answer gives the same page, and never below `floor`, which keeps a descender off the next line's ascenders.
enum LineRhythm {
    static let smallestShare: CGFloat = 2.0 / 3.0

    /// Where each line sits below the first, measured down the block: `offsets[0]` is 0 and each later entry adds one
    /// randomly chosen gap. The total never exceeds `count - 1` full gaps, so the drawing stays inside what was
    /// reserved.
    static func offsets(count: Int, spacing: CGFloat, floor: CGFloat, seed: UInt64) -> [CGFloat] {
        guard count > 0 else { return [] }
        var generator = Generator(seed: seed)
        var result: [CGFloat] = [0]
        for _ in 1..<max(count, 1) {
            let share = smallestShare + (1 - smallestShare) * generator.unit()
            let gap = min(spacing, max(spacing * share, floor))
            result.append((result.last ?? 0) + gap)
        }
        return result
    }

    /// SplitMix64: small, fast and good enough to make eight gaps look unrelated.
    private struct Generator {
        private var state: UInt64

        init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

        mutating func unit() -> CGFloat {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            value ^= value >> 31
            return CGFloat(value >> 11) / CGFloat(1 << 53)
        }
    }
}
