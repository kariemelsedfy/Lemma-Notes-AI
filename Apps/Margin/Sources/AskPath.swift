/// Tracks the explicit Ask entry point independently of Pencil hardware.
///
enum AskCaptureStage: Equatable {
    case idle
    case question
    case answerArea
}

/// One explicit path owns the two selection gestures so toolbar, keyboard, and Pencil
/// entry points cannot skip the answer-area step.
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
        stage = .answerArea
    }

    mutating func answerAreaDidComplete() {
        guard stage == .answerArea else { return }
        stage = .idle
    }

    mutating func retryAnswerArea() {
        stage = .answerArea
    }

    mutating func cancel() {
        stage = .idle
    }
}
