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

/// Remembers where a Pencil double-tap came from, so erasing can hand the writer straight back.
///
/// Double-tap goes to the eraser from any other tool and, from the eraser, back to where it came from. If the
/// writer then erases something, the eraser was a detour: once the ink stops changing they are returned to
/// the tool they were on (owner request 2026-10-17). Choosing a tool by hand forgets the detour, and so does
/// leaving the eraser by double-tap.
struct PencilToolSwitcher: Equatable {
    private var restore: CanvasTool?
    /// The tool this switcher last selected itself, so its own change is not mistaken for the writer's.
    private var expected: CanvasTool?

    /// A double-tap: the tool to select.
    mutating func doubleTap(current: CanvasTool) -> CanvasTool {
        let next: CanvasTool
        if current == .eraser {
            next = restore ?? .pen
            restore = nil
        } else {
            restore = current
            next = .eraser
        }
        expected = next
        return next
    }

    /// The ink changed and has now been still for a moment: the tool to return to, if the eraser is a detour.
    mutating func inkSettled(current: CanvasTool) -> CanvasTool? {
        guard current == .eraser, let back = restore else { return nil }
        restore = nil
        expected = back
        return back
    }

    /// The selected tool changed. A change this switcher did not make is the writer's own choice.
    mutating func toolChanged(to tool: CanvasTool) {
        if tool == expected {
            expected = nil
        } else {
            restore = nil
            expected = nil
        }
    }

    var isOnDetour: Bool { restore != nil }
}

/// Puts the Pencil interaction on a view in the notebook so double-tap and squeeze reach the app.
///
/// Takes bindings rather than closures, so the coordinator (made once) always acts on the live values.
struct PencilInteractionHost: UIViewRepresentable {
    @Binding var tool: CanvasTool
    @Binding var switcher: PencilToolSwitcher

    func makeCoordinator() -> PencilInteractionCoordinator {
        PencilInteractionCoordinator(
            onArmAsk: {
                switcher.toolChanged(to: .lasso)
                tool = .lasso
            },
            onToggleEraser: { tool = switcher.doubleTap(current: tool) })
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}
