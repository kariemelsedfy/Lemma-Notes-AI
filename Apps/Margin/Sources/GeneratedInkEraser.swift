import DocumentStore

/// Turns PencilKit's per-stroke vector erasure into answer-level erasure for generated ink.
///
/// Fingerprints are used instead of stroke indices because PencilKit reindexes the drawing
/// after every edit. Ambiguous fingerprints are never removed: preserving user ink is more
/// important than cleaning up a malformed generated group.
enum GeneratedInkEraser {
    struct Resolution {
        let strokeIndicesToRemove: Set<Int>
        let metadata: PageMetadata
    }

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
        let removedElementIDs = Set(
            validMetadata.elements.compactMap { element -> String? in
                guard element.kind == .generated, !element.strokeReferences.isEmpty else { return nil }
                let lostAStroke = element.strokeReferences.contains { reference in
                    currentIndices[reference.fingerprint] == nil
                }
                return lostAStroke ? element.id : nil
            })

        guard !removedElementIDs.isEmpty else {
            return Resolution(
                strokeIndicesToRemove: [],
                metadata: validMetadata.repairingStrokeIndices(using: current)
            )
        }

        let referencesToRemove = validMetadata.elements
            .filter { removedElementIDs.contains($0.id) }
            .flatMap(\.strokeReferences)
        let strokeIndicesToRemove = Set(
            referencesToRemove.compactMap { reference -> Int? in
                guard let matches = currentIndices[reference.fingerprint], matches.count == 1 else { return nil }
                return matches[0]
            })
        let finalStrokes = current.enumerated().compactMap { index, stroke in
            strokeIndicesToRemove.contains(index) ? nil : stroke
        }
        var updatedMetadata = validMetadata
        updatedMetadata.elements.removeAll { removedElementIDs.contains($0.id) }

        return Resolution(
            strokeIndicesToRemove: strokeIndicesToRemove,
            metadata: updatedMetadata.repairingStrokeIndices(using: finalStrokes)
        )
    }
}
