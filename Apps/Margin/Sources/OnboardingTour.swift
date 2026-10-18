import Foundation

/// The first-run tour (`PREMIUM_AND_ONBOARDING_PLAN.md` §3). Pure logic only: what the steps are, where the user
/// is in a practice step, and what has been shown. The screens read this and own none of these rules.
enum OnboardingStep: String, CaseIterable, Equatable {
    /// Cards, shown over the library.
    case welcome
    case handwriting
    case disclosure
    /// Practice steps, done on a real note with the real Ask.
    case explain
    case solve
    case plot
    case subscribe

    var isPractice: Bool { practiceVerb != nil }

    /// The Ask choice the user is being taught.
    var practiceVerb: AskVerb? {
        switch self {
        case .explain: .explain
        case .solve: .answer
        case .plot: .plot
        default: nil
        }
    }

    /// Practice steps whose answer comes from the hosted model.
    var isHosted: Bool { self == .explain || self == .solve }

    /// What the user is asked to write. Not localized: the example is the same in every language.
    var example: String? {
        switch self {
        case .explain: "photosynthesis is"
        case .solve: "2x + 3 = 11"
        case .plot: "y = x³ + cos(x)"
        default: nil
        }
    }
}

/// The order of steps for one run of the tour.
struct OnboardingTour: Equatable {
    private(set) var steps: [OnboardingStep]
    private(set) var index = 0

    /// - Parameter hostedAvailable: whether this install may use the hosted model. A free install without
    ///   a server-enforced allowance (App Attest) skips the hosted steps, so the tour never promises what
    ///   it cannot deliver. Declining the AI disclosure has the same effect.
    init(hostedAvailable: Bool) {
        steps = OnboardingStep.allCases.filter { hostedAvailable || !($0.isHosted || $0 == .disclosure) }
    }

    var current: OnboardingStep? { steps.indices.contains(index) ? steps[index] : nil }
    var isFinished: Bool { current == nil }
    /// Zero-based position among all steps, for the progress dots.
    var position: Int { min(index, steps.count) }

    mutating func advance() { index = min(index + 1, steps.count) }

    /// The user declined the AI disclosure: drop the hosted steps from here on.
    mutating func dropHostedSteps() {
        let done = steps.prefix(index + 1)
        let rest = steps.dropFirst(index + 1).filter { !$0.isHosted }
        steps = Array(done) + rest
    }
}

/// What happened on the canvas that a practice step cares about.
enum PracticeEvent: Equatable {
    /// Something is lassoed and the choices are showing.
    case selected
    case verbChosen(AskVerb)
    case answerShown
    case kept
    case failed
    /// The selection or the answer went away without being kept.
    case cleared
}

/// Where the user is inside one practice step.
struct PracticeProgress: Equatable {
    enum Stage: Equatable {
        /// Write the example, tap Ask, circle it.
        case write
        /// Choose the right verb.
        case choose
        case waiting
        /// The answer is on the page, waiting for Keep.
        case keep
        case done
    }

    let expected: AskVerb
    private(set) var stage = Stage.write
    /// The last Ask failed; the user can try again.
    private(set) var failed = false
    /// The user picked a different verb than the step teaches (still allowed, but nudged).
    private(set) var pickedOther = false

    init(expected: AskVerb) { self.expected = expected }

    mutating func apply(_ event: PracticeEvent) {
        guard stage != .done else { return }
        switch event {
        case .selected:
            stage = .choose
            failed = false
        case .verbChosen(let verb):
            pickedOther = verb != expected
            stage = pickedOther ? .choose : .waiting
            failed = false
        case .answerShown:
            // A different verb's answer still shows, but only the taught verb moves the tour on.
            stage = pickedOther ? .choose : .keep
        case .kept:
            if !pickedOther { stage = .done }
        case .failed:
            failed = true
            stage = .choose
        case .cleared:
            if stage != .waiting { stage = .write }
        }
    }
}

/// What the tour remembers between launches. One integer, so a later change can show only what is new.
struct OnboardingStore {
    static let currentVersion = 1
    static let completedKey = "onboarding.completedVersion"
    static let disclosureKey = "onboarding.aiDisclosureVersion"
    /// Bumped when the wording of the AI disclosure changes, so consent is asked again (ADR-029).
    static let disclosureVersion = 1

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var needsTour: Bool { defaults.integer(forKey: Self.completedKey) < Self.currentVersion }
    var hasAcknowledgedDisclosure: Bool { defaults.integer(forKey: Self.disclosureKey) >= Self.disclosureVersion }

    func markCompleted() { defaults.set(Self.currentVersion, forKey: Self.completedKey) }
    func acknowledgeDisclosure() { defaults.set(Self.disclosureVersion, forKey: Self.disclosureKey) }
    func reset() { defaults.removeObject(forKey: Self.completedKey) }
}

extension PracticeEvent {
    /// The tour's reading of a change in the Ask bar. `nil` for phases it has no use for.
    init?(phase: AskBarPhase, verb: AskVerb?) {
        switch phase {
        case .offeringVerbs: self = .selected
        case .working:
            guard let verb else { return nil }
            self = .verbChosen(verb)
        case .awaitingDecision: self = .answerShown
        case .failed: self = .failed
        case .hidden: self = .cleared
        }
    }
}
