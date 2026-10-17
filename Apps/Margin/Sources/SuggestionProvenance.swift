import DocumentStore
import Foundation
import InkCore

/// Records where generated ink came from, permanently.
///
/// `ARCHITECTURE.md` §3.1 puts the semantic element index in page metadata, and the
/// dependency rule forbids `DocumentStore` from importing `InkCore` — so the translation
/// between an accepted suggestion and a `PageElement` lives here, in the one target
/// allowed to see both.
///
/// Provenance is permanent. Once ink is marked generated it stays marked, however much
/// the user later edits around it.
enum SuggestionProvenance {
    /// Adds the element that records an accepted suggestion.
    ///
    /// `pageStrokes` must be the page's strokes *after* the suggestion was inserted; the
    /// indices are positions in that array.
    static func recording(
        _ accepted: AcceptedSuggestion,
        into metadata: PageMetadata,
        pageStrokes: [InkStroke]
    ) -> PageMetadata {
        guard let element = element(for: accepted, in: pageStrokes) else { return metadata }
        var updated = metadata
        updated.elements.append(element)
        return updated
    }

    /// The element for one accepted suggestion, or nil when none of its strokes are on
    /// the page — which means the caller passed the wrong page, not that provenance is
    /// optional.
    static func element(for accepted: AcceptedSuggestion, in pageStrokes: [InkStroke]) -> PageElement? {
        let indicesByID = Dictionary(uniqueKeysWithValues: pageStrokes.enumerated().map { ($1.id, $0) })
        let references = accepted.strokeIDs.compactMap { strokeID -> StrokeReference? in
            guard let index = indicesByID[strokeID] else { return nil }
            return StrokeReference(index: index, fingerprint: StrokeFingerprint(stroke: stored(pageStrokes[index])))
        }
        guard !references.isEmpty else { return nil }

        return PageElement(
            id: identifier(for: accepted),
            kind: .generated,
            bounds: bounds(of: accepted.bounds),
            strokeReferences: references,
            requestID: accepted.requestID,
            acceptedAt: accepted.acceptedAt
        )
    }

    /// A stable identifier derived from the request and the moment it was accepted.
    ///
    /// Deterministic rather than a fresh UUID so that re-deriving an element for the same
    /// acceptance — after a failed save, say — does not produce a second one.
    private static func identifier(for accepted: AcceptedSuggestion) -> String {
        var hasher = FNV1a()
        hasher.combine(accepted.requestID)
        hasher.combine(String(accepted.acceptedAt.timeIntervalSince1970))
        return "el_\(hasher.value)"
    }

    /// Indices into `pageStrokes` of ink the app generated, so nothing that is not the writer's own hand is ever
    /// learned from (a kept answer is drawn from their glyphs; learning from it would only feed it back).
    static func generatedStrokeIndices(metadata: PageMetadata?, pageStrokes: [InkStroke]) -> Set<Int> {
        guard let metadata else { return [] }
        let repaired = metadata.repairingStrokeIndices(using: pageStrokes.map(stored))
        return Set(
            repaired.elements.filter { $0.kind == .generated }.flatMap(\.strokeReferences).map(\.index)
                .filter { pageStrokes.indices.contains($0) })
    }

    /// After the strokes at `movedIndices` changed shape in place, points their elements' references at the new
    /// fingerprints and refreshes each element's bounds, so provenance survives a resize.
    static func refreshing(_ metadata: PageMetadata, movedIndices: Set<Int>, strokes: [InkStroke]) -> PageMetadata {
        var updated = metadata
        updated.elements = metadata.elements.map { element in
            guard element.strokeReferences.contains(where: { movedIndices.contains($0.index) }) else { return element }
            var changed = element
            changed.strokeReferences = element.strokeReferences.compactMap { reference in
                guard strokes.indices.contains(reference.index) else { return nil }
                guard movedIndices.contains(reference.index) else { return reference }
                return StrokeReference(
                    index: reference.index, fingerprint: StrokeFingerprint(stroke: stored(strokes[reference.index])))
            }
            let referenced = changed.strokeReferences.compactMap {
                strokes.indices.contains($0.index) ? strokes[$0.index] : nil
            }
            let box = InkLineGrouping.bounds(of: referenced)
            if !box.isNull { changed.bounds = bounds(of: box) }
            return changed
        }
        return updated
    }

    static func storedStroke(_ stroke: InkStroke) -> StoredStroke { stored(stroke) }

    private static func stored(_ stroke: InkStroke) -> StoredStroke {
        StoredStroke(
            points: stroke.points.map {
                StoredStrokePoint(horizontal: Double($0.location.x), vertical: Double($0.location.y))
            }
        )
    }

    private static func bounds(of rect: CGRect) -> PageBounds {
        guard !rect.isNull, !rect.isInfinite else {
            return PageBounds(horizontal: 0, vertical: 0, width: 0, height: 0)
        }
        return PageBounds(
            horizontal: Double(rect.minX),
            vertical: Double(rect.minY),
            width: Double(rect.width),
            height: Double(rect.height)
        )
    }
}

/// A short, stable digest. Not `hashValue`: `Hasher` is seeded per process, so element
/// identifiers would change between launches.
private struct FNV1a {
    private var state: UInt64 = 0xCBF2_9CE4_8422_2325

    var value: String { String(state, radix: 16) }

    mutating func combine(_ text: String) {
        for byte in text.utf8 {
            state ^= UInt64(byte)
            state = state &* 0x0000_0100_0000_01B3
        }
    }
}
