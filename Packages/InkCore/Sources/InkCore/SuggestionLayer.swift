import Foundation

/// Generated ink that the user has accepted, and the record of where it came from.
///
/// The app writes this into page metadata as an element so the provenance survives
/// reload (`ARCHITECTURE.md` §3.1). Provenance is permanent: once generated ink is on the
/// page it stays marked as generated, however much it is later edited.
public struct AcceptedSuggestion: Equatable, Sendable {
    public let requestID: String
    public let strokeIDs: [InkStrokeID]
    public let bounds: CGRect
    public let acceptedAt: Date

    public init(requestID: String, strokeIDs: [InkStrokeID], bounds: CGRect, acceptedAt: Date) {
        self.requestID = requestID
        self.strokeIDs = strokeIDs
        self.bounds = bounds
        self.acceptedAt = acceptedAt
    }
}

/// Holds generated ink separately from the page until the user accepts it.
///
/// `ARCHITECTURE.md` §4: the suggestion is its own drawing, so rejecting is a discard
/// rather than an edit, and accepting appends in a single undo group — which is what
/// makes "one undo removes the whole generation" true without any bookkeeping.
@MainActor
public final class SuggestionLayer {
    /// The alpha generated ink is drawn at before it is accepted.
    public static let previewAlpha: CGFloat = 0.7

    /// The ink currently being offered. Empty when nothing is pending.
    public private(set) var strokes: [InkStroke] = []
    /// Identifies the AI request that produced the pending ink.
    public private(set) var requestID: String?

    public init() {}

    public var isPresenting: Bool { !strokes.isEmpty }

    /// The union of the pending strokes' bounds, or `.null` when nothing is pending.
    public var bounds: CGRect { InkLineGrouping.bounds(of: strokes) }

    /// Offers new ink, replacing anything already pending.
    ///
    /// Replacing rather than accumulating is deliberate: two overlapping suggestions on
    /// screen at once is never what the user asked for, and the request state machine
    /// only ever has one response in flight.
    public func present(_ strokes: [InkStroke], requestID: String) {
        self.strokes = strokes
        self.requestID = strokes.isEmpty ? nil : requestID
    }

    /// Throws the pending ink away. Nothing reaches the page.
    public func discard() {
        strokes = []
        requestID = nil
    }

    /// Commits the pending ink to the page in one undo group.
    ///
    /// Returns nil when there was nothing pending, so an accidental double-accept is a
    /// no-op rather than a second copy of the answer.
    @discardableResult
    public func accept(into engine: any InkEngine, at acceptedAt: Date = Date()) -> AcceptedSuggestion? {
        let pending = strokes
        guard let accepted = acceptWithoutInserting(at: acceptedAt) else { return nil }
        engine.insertProgrammatic(strokes: pending)
        return accepted
    }

    /// Records the acceptance and clears the layer, leaving the insertion to the caller.
    ///
    /// `accept(into:)` is the right entry point when an `InkEngine` owns the page. The
    /// canvas commits into a `PKDrawing` it holds directly, so it takes the record and
    /// does the insertion itself — routing that through a throwaway engine would be a
    /// fiction, and a fiction in the one place provenance is decided.
    @discardableResult
    public func acceptWithoutInserting(at acceptedAt: Date = Date()) -> AcceptedSuggestion? {
        guard let requestID, !strokes.isEmpty else { return nil }

        let accepted = AcceptedSuggestion(
            requestID: requestID,
            strokeIDs: strokes.map(\.id),
            bounds: bounds,
            acceptedAt: acceptedAt
        )
        discard()
        return accepted
    }
}
