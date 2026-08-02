import UIKit

/// What a Pencil hardware gesture should do.
enum PencilAction: Equatable {
    /// Arm the Ask lasso.
    case armAsk
    /// Let the system's own behaviour stand; the app does nothing.
    case deferToSystem
    /// The user asked for nothing to happen.
    case none
}

/// Maps Apple Pencil hardware gestures onto app behaviour.
///
/// Pure and separate from the interaction itself, because `UIPencilInteraction` cannot
/// fire in a simulator — the *decision* is the part that can be tested, so it is kept
/// where a test can reach it.
///
/// `PROJECT_PLAN.md` §3.1: squeeze is the fast path to Ask for people who have a Pencil
/// Pro; double-tap defaults to the system setting and is only taken over if the user
/// opts in during onboarding, because the HIG expects apps to respect that preference.
struct PencilActionPolicy: Equatable {
    /// Set when the user chose "use double-tap for Ask" during onboarding.
    let overridesDoubleTap: Bool

    init(overridesDoubleTap: Bool = false) {
        self.overridesDoubleTap = overridesDoubleTap
    }

    /// Double-tap. Hijacking this by default would override a system-wide choice the user
    /// made for every app, which is exactly what the HIG asks apps not to do.
    func actionForTap(systemPreference: UIPencilPreferredAction) -> PencilAction {
        overridesDoubleTap ? .armAsk : .deferToSystem
    }

    /// Squeeze.
    ///
    /// Taken as the Ask shortcut unless the user set the system squeeze action to
    /// `.ignore` — that is an explicit "do nothing", and it deserves to be honoured even
    /// though it costs us the fastest entry point on the hardware that has it.
    ///
    /// There is no system preference value that means "Ask", so an app cannot map this
    /// perfectly; worth revisiting against the HIG once someone has used it on a Pencil Pro.
    func actionForSqueeze(systemPreference: UIPencilPreferredAction) -> PencilAction {
        systemPreference == .ignore ? .none : .armAsk
    }
}
