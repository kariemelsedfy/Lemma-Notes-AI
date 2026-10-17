import DesignSystem
import SwiftUI

/// Something on the notebook screen the tour can point at.
enum TourTarget: Hashable {
    /// The blank page, where to write.
    case writeHere
    case ask
    case verb(AskVerb)
    case keep
}

extension PracticeProgress {
    /// What the bouncing arrow should point at. `hasInk` is whether anything is written yet, `lassoArmed`
    /// whether the writer is mid-way through circling (the lasso bar already tells them what to do then).
    func pointerTarget(hasInk: Bool, lassoArmed: Bool) -> TourTarget? {
        switch stage {
        case .write:
            if lassoArmed { return nil }
            return hasInk ? .ask : .writeHere
        case .choose: return .verb(expected)
        case .keep: return .keep
        case .waiting, .done: return nil
        }
    }
}

struct TourTargetKey: PreferenceKey {
    static var defaultValue: [TourTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourTarget: Anchor<CGRect>], nextValue: () -> [TourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Reports this view's frame so the tour can point at it. Costs nothing when no tour is running.
    func tourTarget(_ target: TourTarget) -> some View {
        anchorPreference(key: TourTargetKey.self, value: .bounds) { [target: $0] }
    }
}

/// A finger-sized arrow that bounces towards the thing to use next.
struct BouncingArrow: View {
    let label: LocalizedStringKey?
    @State private var bouncing = false

    var body: some View {
        VStack(spacing: 2) {
            if let label {
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MarginColor.surface)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(MarginColor.accent))
            }
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 30))
                .foregroundStyle(MarginColor.accent)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
        }
        .offset(y: bouncing ? 8 : -8)
        .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: bouncing)
        .onAppear { bouncing = true }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Draws the arrow over the notebook screen, above whatever it points at.
struct TourPointerOverlay: ViewModifier {
    let target: TourTarget?

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(TourTargetKey.self) { anchors in
            GeometryReader { proxy in
                if let target {
                    arrow(for: target, anchors: anchors, in: proxy)
                        .id(target)
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func arrow(
        for target: TourTarget, anchors: [TourTarget: Anchor<CGRect>], in proxy: GeometryProxy
    ) -> some View {
        if target == .writeHere {
            BouncingArrow(label: "onboarding.pointer.write")
                .position(x: proxy.size.width * 0.28, y: proxy.size.height * 0.2)
        } else if let anchor = anchors[target] {
            let frame = proxy[anchor]
            BouncingArrow(label: Self.label(for: target))
                .position(x: frame.midX, y: frame.minY - 44)
        }
    }

    private static func label(for target: TourTarget) -> LocalizedStringKey? {
        switch target {
        case .ask: "onboarding.pointer.ask"
        case .keep: "onboarding.pointer.keep"
        default: nil
        }
    }
}
