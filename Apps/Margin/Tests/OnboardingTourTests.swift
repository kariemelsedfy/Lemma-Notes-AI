import XCTest

@testable import Margin

final class OnboardingTourTests: XCTestCase {
    func testAFullTourHasEveryStepInOrder() {
        let tour = OnboardingTour(hostedAvailable: true)
        XCTAssertEqual(tour.steps, [.welcome, .handwriting, .disclosure, .explain, .solve, .plot, .subscribe])
        XCTAssertEqual(tour.current, .welcome)
    }

    func testWithoutHostedAccessTheTourSkipsTheDisclosureAndTheHostedSteps() {
        let tour = OnboardingTour(hostedAvailable: false)
        XCTAssertEqual(tour.steps, [.welcome, .handwriting, .plot, .subscribe])
    }

    func testDecliningTheDisclosureDropsOnlyTheHostedSteps() {
        var tour = OnboardingTour(hostedAvailable: true)
        tour.advance()
        tour.advance()
        XCTAssertEqual(tour.current, .disclosure)
        tour.dropHostedSteps()
        tour.advance()
        XCTAssertEqual(tour.current, .plot)
    }

    func testAdvancingPastTheEndFinishes() {
        var tour = OnboardingTour(hostedAvailable: false)
        for _ in 0..<10 { tour.advance() }
        XCTAssertTrue(tour.isFinished)
        XCTAssertNil(tour.current)
    }

    func testPracticeStepsTeachTheRightVerbs() {
        XCTAssertEqual(OnboardingStep.explain.practiceVerb, .explain)
        XCTAssertEqual(OnboardingStep.solve.practiceVerb, .answer)
        XCTAssertEqual(OnboardingStep.plot.practiceVerb, .plot)
        XCTAssertNil(OnboardingStep.welcome.practiceVerb)
        XCTAssertEqual(OnboardingStep.plot.example, "y = x^3 + cos(x)")
    }

    func testPracticeWalksFromWritingToDone() {
        var progress = PracticeProgress(expected: .plot)
        XCTAssertEqual(progress.stage, .write)
        progress.apply(.selected)
        XCTAssertEqual(progress.stage, .choose)
        progress.apply(.verbChosen(.plot))
        XCTAssertEqual(progress.stage, .waiting)
        progress.apply(.answerShown)
        XCTAssertEqual(progress.stage, .keep)
        progress.apply(.kept)
        XCTAssertEqual(progress.stage, .done)
    }

    func testAnotherVerbDoesNotMoveTheStepOn() {
        var progress = PracticeProgress(expected: .explain)
        progress.apply(.selected)
        progress.apply(.verbChosen(.plot))
        XCTAssertTrue(progress.pickedOther)
        progress.apply(.answerShown)
        progress.apply(.kept)
        XCTAssertEqual(progress.stage, .choose)
    }

    func testAFailureLetsTheUserTryAgain() {
        var progress = PracticeProgress(expected: .answer)
        progress.apply(.selected)
        progress.apply(.verbChosen(.answer))
        progress.apply(.failed)
        XCTAssertTrue(progress.failed)
        XCTAssertEqual(progress.stage, .choose)
        progress.apply(.verbChosen(.answer))
        XCTAssertFalse(progress.failed)
    }

    func testDiscardingAnAnswerGoesBackToWriting() {
        var progress = PracticeProgress(expected: .plot)
        progress.apply(.selected)
        progress.apply(.verbChosen(.plot))
        progress.apply(.answerShown)
        progress.apply(.cleared)
        XCTAssertEqual(progress.stage, .write)
    }

    func testTheStoreRemembersCompletionAndConsentByVersion() {
        let suite = "onboarding.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OnboardingStore(defaults: defaults)
        XCTAssertTrue(store.needsTour)
        XCTAssertFalse(store.hasAcknowledgedDisclosure)
        store.markCompleted()
        store.acknowledgeDisclosure()
        XCTAssertFalse(store.needsTour)
        XCTAssertTrue(store.hasAcknowledgedDisclosure)
        store.reset()
        XCTAssertTrue(store.needsTour)
    }
}

final class OnboardingCopyTests: XCTestCase {
    func testEveryPieceOfOnboardingCopyExists() {
        var keys = [
            "onboarding.skip", "onboarding.continue", "onboarding.later", "onboarding.replay",
            "onboarding.welcome.title", "onboarding.welcome.body", "onboarding.handwriting.title",
            "onboarding.handwriting.body", "onboarding.handwriting.teach", "onboarding.disclosure.title",
            "onboarding.disclosure.body", "onboarding.disclosure.accept", "onboarding.disclosure.decline",
            "onboarding.subscribe.title", "onboarding.subscribe.body", "onboarding.subscribe.trial",
            "onboarding.subscribe.price", "onboarding.note.title", "onboarding.coach.plot.hint",
        ]
        for step in [OnboardingStep.explain, .solve, .plot] {
            keys.append(PracticeCoachBar.titleName(step))
            var progress = PracticeProgress(expected: step.practiceVerb ?? .plot)
            for event in [PracticeEvent.selected, .verbChosen(step.practiceVerb ?? .plot), .answerShown, .kept] {
                keys.append(PracticeCoachBar.instructionName(step: step, progress: progress))
                progress.apply(event)
            }
            keys.append(PracticeCoachBar.instructionName(step: step, progress: progress))
            progress.apply(.failed)
            keys.append(PracticeCoachBar.instructionName(step: step, progress: progress))
        }
        for key in keys {
            XCTAssertNotEqual(NSLocalizedString(key, comment: ""), key, key)
        }
    }

    func testTheWriteInstructionNamesTheExample() {
        let text = PracticeCoachBar.instruction(step: .plot, progress: PracticeProgress(expected: .plot))
        XCTAssertTrue(text.contains("y = x^3 + cos(x)"))
        XCTAssertTrue(text.contains("^"))
    }
}
