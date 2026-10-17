import SwiftUI
import UIKit

/// Bridges Apple Pencil hardware gestures to the Ask path.
///
/// Built against the current API only — `pencilInteractionDidTap:` has been deprecated
/// since iOS 17.5 in favour of `pencilInteraction(_:didReceiveTap:)`, and the deployment
/// target is iPadOS 26, so the deprecated path is not implemented at all.
///
/// **Cannot be exercised in a simulator.** `UIPencilInteraction` only fires for real
/// hardware, so what is verified here is the policy and the setup; the gestures
/// themselves are on the device checklist.
@MainActor
final class PencilInteractionCoordinator: NSObject, UIPencilInteractionDelegate {
    private let policy: PencilActionPolicy
    private let onArmAsk: () -> Void
    private let onToggleEraser: () -> Void

    init(
        policy: PencilActionPolicy = PencilActionPolicy(), onArmAsk: @escaping () -> Void = {},
        onToggleEraser: @escaping () -> Void = {}
    ) {
        self.policy = policy
        self.onArmAsk = onArmAsk
        self.onToggleEraser = onToggleEraser
    }

    /// Attaches to a view. On a Pencil 1 or with no Pencil at all this simply never
    /// fires — there is no capability to check and nothing to disable.
    func attach(to view: UIView) {
        view.addInteraction(UIPencilInteraction(delegate: self))
    }

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        perform(policy.actionForTap(systemPreference: UIPencilInteraction.preferredTapAction))
    }

    func pencilInteraction(
        _ interaction: UIPencilInteraction,
        didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
    ) {
        // A squeeze reports began/changed/ended; acting on anything but `ended` would fire
        // repeatedly through one squeeze and arm Ask several times over.
        guard squeeze.phase == .ended else { return }
        perform(policy.actionForSqueeze(systemPreference: UIPencilInteraction.preferredSqueezeAction))
    }

    private func perform(_ action: PencilAction) {
        switch action {
        case .armAsk: onArmAsk()
        case .toggleEraser: onToggleEraser()
        case .none: break
        }
    }
}

/// Puts the Pencil interaction on a view in the notebook so double-tap and squeeze reach the app.
///
/// Takes the tool binding rather than closures, so the coordinator (made once) always acts on the live value.
struct PencilInteractionHost: UIViewRepresentable {
    @Binding var tool: CanvasTool

    func makeCoordinator() -> PencilInteractionCoordinator {
        PencilInteractionCoordinator(
            onArmAsk: { tool = .lasso }, onToggleEraser: { tool = tool.afterPencilDoubleTap })
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}
