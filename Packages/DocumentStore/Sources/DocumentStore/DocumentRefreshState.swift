/// The safe refresh status of a document package presented by the file system.
///
/// A conflict is deliberately terminal until a person chooses a version. The app must never
/// infer a field-level merge for opaque ink data.
public enum DocumentRefreshState: Equatable, Sendable {
    case current
    case refreshRequired
    case conflict
}

/// Events emitted by the document lifecycle when a package changes outside the current editor.
public enum DocumentRefreshEvent: Sendable {
    case externalChange
    case reloadCompleted
    case conflictDetected
    case conflictResolvedByUser
}

/// Small, framework-independent transition model for iCloud-backed document refresh.
///
/// Keeping this state machine independent of `UIDocument` makes the no-automatic-merge policy
/// testable on macOS while UIKit supplies the real file-presenter notifications on iPad.
public struct DocumentRefreshStateMachine: Sendable {
    public private(set) var state: DocumentRefreshState = .current

    public init() {}

    public mutating func apply(_ event: DocumentRefreshEvent) {
        switch event {
        case .conflictDetected:
            state = .conflict
        case .conflictResolvedByUser:
            if state == .conflict {
                state = .refreshRequired
            }
        case .externalChange:
            if state == .current {
                state = .refreshRequired
            }
        case .reloadCompleted:
            if state == .refreshRequired {
                state = .current
            }
        }
    }
}
