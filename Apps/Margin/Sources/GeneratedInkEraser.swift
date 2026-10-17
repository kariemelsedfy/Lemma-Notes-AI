import DocumentStore
import Foundation

/// Turns PencilKit's per-stroke vector erasure into **character-level** erasure for generated ink.
///
/// PencilKit removes whichever single stroke the eraser touched. For answer ink that leaves half a
/// character behind (one bar of an `=`), so the eraser finishes the job: it removes every stroke of the
/// character that was touched, and nothing else. The rest of the answer stays, still attributed to its
/// request. (Until 2026-10-16 this removed the whole answer, which made `x = 5` impossible to edit.)
///
/// Characters are recovered from geometry rather than stored: strokes are grouped by horizontal overlap,
/// because the two bars of an `=`, the stem and dot of an `i`, or the hatch lines of a typeset stand-in all
/// share a column while neighbouring characters do not. This needs no change to the document format. Two
/// neighbours that lean into each other can be grouped together, in which case erasing one removes both —
/// the safe failure, since it never leaves a fragment.
///
/// Fingerprints are used instead of stroke indices because PencilKit reindexes the drawing
/// after every edit. Ambiguous fingerprints are never removed: preserving user ink is more
/// important than cleaning up a malformed generated group.
enum GeneratedInkEraser {
    struct Resolution {
        let strokeIndicesToRemove: Set<Int>
        let metadata: PageMetadata
    }

    /// How much of the narrower stroke's width must overlap a character's column to join it.
    private static let joinOverlap = 0.3

    static func resolve(
        previous: [StoredStroke],
        current: [StoredStroke],
        metadata: PageMetadata
    ) -> Resolution {
        let validMetadata = metadata.repairingStrokeIndices(using: previous)
        let currentIndices = Dictionary(
            grouping: current.indices,
            by: { StrokeFingerprint(stroke: current[$0]) }
        )

        var referencesToRemove: [StrokeReference] = []
        var updatedElements: [PageElement] = []
        for element in validMetadata.elements {
            guard element.kind == .generated, !element.strokeReferences.isEmpty else {
                updatedElements.append(element)
                continue
            }
            let lost = element.strokeReferences.filter { currentIndices[$0.fingerprint] == nil }
            guard !lost.isEmpty else {
                updatedElements.append(element)
                continue
            }
            // Every stroke of every character that lost a stroke goes with it.
            let doomed = Self.characters(of: element.strokeReferences, in: previous)
                .filter { character in character.contains { reference in lost.contains(reference) } }
                .flatMap { $0 }
            referencesToRemove.append(contentsOf: doomed)

            var remaining = element
            remaining.strokeReferences = element.strokeReferences.filter { !doomed.contains($0) }
            if !remaining.strokeReferences.isEmpty {
                updatedElements.append(remaining)
            }
        }

        let strokeIndicesToRemove = Set(
            referencesToRemove.compactMap { reference -> Int? in
                guard let matches = currentIndices[reference.fingerprint], matches.count == 1 else { return nil }
                return matches[0]
            })
        guard !referencesToRemove.isEmpty else {
            return Resolution(
                strokeIndicesToRemove: [],
                metadata: validMetadata.repairingStrokeIndices(using: current)
            )
        }

        let finalStrokes = current.enumerated().compactMap { index, stroke in
            strokeIndicesToRemove.contains(index) ? nil : stroke
        }
        var updatedMetadata = validMetadata
        updatedMetadata.elements = updatedElements

        return Resolution(
            strokeIndicesToRemove: strokeIndicesToRemove,
            metadata: updatedMetadata.repairingStrokeIndices(using: finalStrokes)
        )
    }

    private struct Span {
        let reference: StrokeReference
        var low: Double
        var high: Double
        /// Vertical centre and height of the stroke, to tell which line of the answer it is on.
        var middle: Double
        var height: Double
    }

    private struct CharacterColumn {
        var low: Double
        var high: Double
        var members: [StrokeReference]
    }

    /// Groups an element's strokes into characters, measured on the drawing as it was before the erase (a
    /// removed stroke is only in `previous`).
    ///
    /// **Line by line first.** A multi-line answer has characters stacked in the same columns, so grouping by
    /// horizontal overlap across the whole answer made erasing one letter take the letter above and below it
    /// (found on device 2026-10-17). Strokes are split into text lines by their vertical centres, then
    /// grouped into characters by horizontal overlap within a line.
    private static func characters(of refs: [StrokeReference], in drawing: [StoredStroke]) -> [[StrokeReference]] {
        var spans: [Span] = []
        for reference in refs where drawing.indices.contains(reference.index) {
            let points = drawing[reference.index].points
            let columns = points.map(\.horizontal)
            let rows = points.map(\.vertical)
            if let low = columns.min(), let high = columns.max(), let top = rows.min(), let bottom = rows.max() {
                spans.append(
                    Span(
                        reference: reference, low: low, high: high, middle: (top + bottom) / 2,
                        height: bottom - top))
            }
        }
        return textLines(of: spans).flatMap(columns(of:))
    }

    /// Splits strokes into lines of writing: neighbours in vertical-centre order belong to the same line until
    /// a gap wider than most of a stroke's height opens, which is far smaller than the gap between lines and
    /// far larger than the wobble of ascenders and descenders within one.
    private static func textLines(of spans: [Span]) -> [[Span]] {
        guard !spans.isEmpty else { return [] }
        let heights = spans.map(\.height).sorted()
        let threshold = max(heights[heights.count / 2] * 0.6, 1)
        var lines: [[Span]] = []
        for span in spans.sorted(by: { $0.middle < $1.middle }) {
            if let last = lines.last?.last, span.middle - last.middle <= threshold {
                lines[lines.count - 1].append(span)
            } else {
                lines.append([span])
            }
        }
        return lines
    }

    /// Groups one line's strokes into characters by horizontal overlap.
    private static func columns(of line: [Span]) -> [[StrokeReference]] {
        var spans = line
        spans.sort { $0.low < $1.low }

        var groups: [CharacterColumn] = []
        for span in spans {
            if var last = groups.last, span.low <= last.high {
                let overlap = min(span.high, last.high) - span.low
                let narrower = min(span.high - span.low, last.high - last.low)
                if overlap >= narrower * joinOverlap {
                    last.low = min(last.low, span.low)
                    last.high = max(last.high, span.high)
                    last.members.append(span.reference)
                    groups[groups.count - 1] = last
                    continue
                }
            }
            groups.append(CharacterColumn(low: span.low, high: span.high, members: [span.reference]))
        }
        return groups.map(\.members)
    }
}
