import Foundation

/// Why an Ask ended without ink.
public enum AskDiscardReason: String, Equatable, Sendable, CaseIterable {
    case rejected
    case cancelled
    /// The user started writing again, so the answer is no longer wanted
    /// (`ARCHITECTURE.md` §5).
    case userResumedWriting
    /// A new selection replaced this one before it finished.
    case superseded
}

/// The failure states from `AI_PIPELINE.md` §8, each of which needs its own copy.
public enum AskFailure: String, Equatable, Sendable, CaseIterable {
    /// `readConfidence` was too low, or the model declined. Show what it thinks it read.
    case unreadable
    case invalidSpec
    case offline
    case outOfCredits
    case noRoom
    case timeout
    case transport
}

/// The lifecycle of one Ask.
///
/// Modelled as an enum with associated values rather than a set of booleans, because the
/// illegal combinations — streaming while idle, awaiting a decision with nothing placed —
/// are exactly the bugs that scattered flags produce (`ARCHITECTURE.md` §5).
public enum AskState: Equatable, Sendable {
    case idle
    case extracting
    case classifying(SelectionContext)
    case requesting(SpecRequest)
    case streaming(SpecRequest)
    case rendering(ValidatedSpec)
    case awaitingDecision(ValidatedSpec, PlacementResult)
    case committed(ValidatedSpec, PlacementResult)
    case discarded(AskDiscardReason)
    case failed(AskFailure)

    /// A name safe to log. Carries no page content, no transcription, no answer
    /// (`AGENTS.md` §7).
    public var name: String {
        switch self {
        case .idle: "idle"
        case .extracting: "extracting"
        case .classifying: "classifying"
        case .requesting: "requesting"
        case .streaming: "streaming"
        case .rendering: "rendering"
        case .awaitingDecision: "awaitingDecision"
        case .committed: "committed"
        case .discarded(let reason): "discarded.\(reason.rawValue)"
        case .failed(let failure): "failed.\(failure.rawValue)"
        }
    }

    /// True once the Ask has finished, one way or another.
    public var isTerminal: Bool {
        switch self {
        case .committed, .discarded, .failed: true
        default: false
        }
    }

    /// Work is in flight and can still be abandoned.
    public var isCancellable: Bool {
        switch self {
        case .idle, .committed, .discarded, .failed: false
        default: true
        }
    }
}

/// What can happen to an Ask.
public enum AskEvent: Equatable, Sendable {
    case begin
    case contextExtracted(SelectionContext)
    case intentClassified(SpecRequest)
    case responseStarted
    case specValidated(ValidatedSpec)
    case placed(PlacementResult)
    case accept
    case reject
    case cancel(AskDiscardReason)
    case fail(AskFailure)

    /// A name safe to log, on the same terms as `AskState.name`.
    public var name: String {
        switch self {
        case .begin: "begin"
        case .contextExtracted: "contextExtracted"
        case .intentClassified: "intentClassified"
        case .responseStarted: "responseStarted"
        case .specValidated: "specValidated"
        case .placed: "placed"
        case .accept: "accept"
        case .reject: "reject"
        case .cancel(let reason): "cancel.\(reason.rawValue)"
        case .fail(let failure): "fail.\(failure.rawValue)"
        }
    }
}
