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
    }

    private struct CharacterColumn {
        var low: Double
        var high: Double
        var members: [StrokeReference]
    }

    /// Groups an element's strokes into characters by horizontal overlap, measured on the drawing as it was
    /// before the erase (a removed stroke is only in `previous`).
    private static func characters(of refs: [StrokeReference], in drawing: [StoredStroke]) -> [[StrokeReference]] {
        var spans: [Span] = []
        for reference in refs where drawing.indices.contains(reference.index) {
            let columns = drawing[reference.index].points.map(\.horizontal)
            if let low = columns.min(), let high = columns.max() {
                spans.append(Span(reference: reference, low: low, high: high))
            }
        }
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
