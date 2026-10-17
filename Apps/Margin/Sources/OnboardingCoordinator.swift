import SwiftUI

/// Runs the first-run tour: which step is showing, and how far the user is through a practice step.
///
/// The rules live in `OnboardingTour` and `PracticeProgress`; this type only holds them where the screens can
/// observe them and remembers when the tour has been seen.
@MainActor
final class OnboardingCoordinator: ObservableObject {
    @Published private(set) var tour: OnboardingTour?
    @Published private(set) var progress: PracticeProgress?
    /// The "Welcome" note the practice steps happen in, once it exists.
    @Published var practiceNoteID: UUID?

    private let store: OnboardingStore
    private let hostedAvailable: () -> Bool

    init(store: OnboardingStore = OnboardingStore(), hostedAvailable: @escaping () -> Bool = { false }) {
        self.store = store
        self.hostedAvailable = hostedAvailable
    }

    var step: OnboardingStep? { tour?.current }
    var isRunning: Bool { tour != nil }
    /// The cards (welcome, handwriting, disclosure) cover the library; practice happens on a note.
    var showsCards: Bool {
        guard let step else { return false }
        return !step.isPractice && step != .subscribe
    }
    var showsInvitation: Bool { step == .subscribe }
    var hasAcknowledgedDisclosure: Bool { store.hasAcknowledgedDisclosure }

    func startIfNeeded() {
        guard tour == nil, store.needsTour else { return }
        start()
    }

    func start() {
        tour = OnboardingTour(hostedAvailable: hostedAvailable())
        enterStep()
    }

    func next() {
        tour?.advance()
        enterStep()
    }

    func acceptDisclosure() {
        store.acknowledgeDisclosure()
        next()
    }

    func declineDisclosure() {
        tour?.dropHostedSteps()
        next()
    }

    /// Leaves the tour wherever it is, and does not show it again.
    func finish() {
        store.markCompleted()
        tour = nil
        progress = nil
    }

    func handle(_ event: PracticeEvent) {
        guard progress != nil else { return }
        progress?.apply(event)
    }

    private func enterStep() {
        guard let current = tour?.current else {
            finish()
            return
        }
        if current == .disclosure, store.hasAcknowledgedDisclosure {
            next()
            return
        }
        progress = current.practiceVerb.map { PracticeProgress(expected: $0) }
    }
}
