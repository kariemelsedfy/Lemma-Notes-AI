import UIKit
import XCTest

@testable import Margin

/// `UIPencilInteraction` never fires in a simulator, so the policy is the only part of
/// M2-04 that can be verified without hardware. It is deliberately where all the
/// decisions live.
@MainActor
final class PencilActionPolicyTests: XCTestCase {
    func testDoubleTapDefersToTheSystemByDefault() {
        let policy = PencilActionPolicy()

        // Taking this over by default would override a choice the user made for every
        // app on the device.
        XCTAssertEqual(policy.actionForTap(systemPreference: .switchEraser), .deferToSystem)
        XCTAssertEqual(policy.actionForTap(systemPreference: .showColorPalette), .deferToSystem)
        XCTAssertEqual(policy.actionForTap(systemPreference: .ignore), .deferToSystem)
    }

    func testDoubleTapArmsAskOnlyWhenTheUserOptedIn() {
        let policy = PencilActionPolicy(overridesDoubleTap: true)

        XCTAssertEqual(policy.actionForTap(systemPreference: .switchEraser), .armAsk)
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

    func testOptingIntoDoubleTapDoesNotChangeSqueeze() {
        let opted = PencilActionPolicy(overridesDoubleTap: true)
        let notOpted = PencilActionPolicy()

        XCTAssertEqual(
            opted.actionForSqueeze(systemPreference: .switchEraser),
            notOpted.actionForSqueeze(systemPreference: .switchEraser)
        )
    }

    func testEveryPreferredActionIsHandled() {
        let policy = PencilActionPolicy()
        let preferences: [UIPencilPreferredAction] = [
            .ignore, .switchEraser, .switchPrevious, .showColorPalette,
            .showInkAttributes, .showContextualPalette, .runSystemShortcut,
        ]

        // A new case in a future SDK should not silently become "arm Ask" for taps.
        for preference in preferences {
            XCTAssertEqual(policy.actionForTap(systemPreference: preference), .deferToSystem, "\(preference)")
        }
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
