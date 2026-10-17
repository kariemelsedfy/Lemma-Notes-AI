import UIKit

/// What a Pencil hardware gesture should do.
enum PencilAction: Equatable {
    /// Arm the Ask lasso.
    case armAsk
    /// Switch between the pen and the eraser.
    case toggleEraser
    /// The user asked for nothing to happen.
    case none
}

/// Maps Apple Pencil hardware gestures onto app behaviour.
///
/// Pure and separate from the interaction itself, because `UIPencilInteraction` cannot
/// fire in a simulator — the *decision* is the part that can be tested, so it is kept
/// where a test can reach it.
///
/// **Double-tap switches between the pen and the eraser (owner decision 2026-10-17).** This replaces the
/// earlier "defer to the system unless opted in" stance: the owner wants the same behaviour in this app
/// whatever the system setting says. A system setting of "ignore" is still honoured, because that is an
/// explicit "do nothing" and the cost of respecting it is small.
/// Squeeze (Pencil Pro) is the fast path to the Ask lasso.
struct PencilActionPolicy: Equatable {
    func actionForTap(systemPreference: UIPencilPreferredAction) -> PencilAction {
        systemPreference == .ignore ? .none : .toggleEraser
    }

    /// Squeeze.
    ///
    /// Taken as the Ask shortcut unless the user set the system squeeze action to
    /// `.ignore` — that is an explicit "do nothing", and it deserves to be honoured even
    /// though it costs us the fastest entry point on the hardware that has it.
    func actionForSqueeze(systemPreference: UIPencilPreferredAction) -> PencilAction {
        systemPreference == .ignore ? .none : .armAsk
    }
}
