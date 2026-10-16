/// Tracks the explicit Ask entry point independently of Pencil hardware.
///
enum AskCaptureStage: Equatable {
    case idle
    case question
}

/// One explicit path owns the selection gesture so toolbar, keyboard, and Pencil entry points behave alike.
///
/// There is no answer-area step any more: once the question is circled, the answer appears as a ghost box
/// directly below it and the writer drags it where they want it.
struct AskPathState: Equatable {
    private(set) var stage: AskCaptureStage = .idle
    private(set) var invocationCount = 0

    var isArmed: Bool { stage != .idle }

    mutating func invoke() {
        stage = .question
        invocationCount += 1
    }

    mutating func questionDidComplete() {
        guard stage == .question else { return }
        stage = .idle
    }

    mutating func cancel() {
        stage = .idle
    }
}
