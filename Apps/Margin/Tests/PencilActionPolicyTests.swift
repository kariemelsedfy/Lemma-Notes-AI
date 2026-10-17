import UIKit
import XCTest

@testable import Margin

/// `UIPencilInteraction` never fires in a simulator, so the policy is the only part of
/// M2-04 that can be verified without hardware. It is deliberately where all the
/// decisions live.
@MainActor
final class PencilActionPolicyTests: XCTestCase {
    func testDoubleTapSwitchesBetweenPenAndEraserWhateverTheSystemPreference() {
        let policy = PencilActionPolicy()

        // Owner decision 2026-10-17: this app always switches, unlike the system default.
        for preference in [
            UIPencilPreferredAction.switchEraser, .showColorPalette, .switchPrevious, .runSystemShortcut,
        ] {
            XCTAssertEqual(policy.actionForTap(systemPreference: preference), .toggleEraser, "\(preference)")
        }
    }

    func testAnExplicitIgnoreIsStillHonoured() {
        XCTAssertEqual(PencilActionPolicy().actionForTap(systemPreference: .ignore), .none)
    }

    func testTheToolAfterADoubleTapAlternatesBetweenPenAndEraser() {
        XCTAssertEqual(CanvasTool.pen.afterPencilDoubleTap, .eraser)
        XCTAssertEqual(CanvasTool.eraser.afterPencilDoubleTap, .pen)
        XCTAssertEqual(CanvasTool.lasso.afterPencilDoubleTap, .eraser)
    }

    func testSqueezeArmsAsk() {
        let policy = PencilActionPolicy()

        XCTAssertEqual(policy.actionForSqueeze(systemPreference: .showContextualPalette), .armAsk)
        XCTAssertEqual(policy.actionForSqueeze(systemPreference: .runSystemShortcut), .armAsk)
    }

    func testSqueezeHonoursAnExplicitOptOut() {
        let policy = PencilActionPolicy()

        // `.ignore` is the user saying "do nothing when I squeeze". Arming Ask anyway
        // would be the app deciding it knows better.
        XCTAssertEqual(policy.actionForSqueeze(systemPreference: .ignore), .none)
    }

    func testAttachingToAViewAddsAnInteraction() {
        let view = UIView()
        let coordinator = PencilInteractionCoordinator {}

        coordinator.attach(to: view)

        // Pencil 1 and no-Pencil are graceful by construction: the interaction attaches
        // and simply never fires. There is no capability flag to branch on.
        XCTAssertTrue(view.interactions.contains { $0 is UIPencilInteraction })
    }
}
