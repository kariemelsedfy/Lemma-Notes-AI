import DesignSystem
import SwiftUI

/// The instruction strip over a practice note: one line of what to do next, matching the Ask board's style.
struct PracticeCoachBar: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    var body: some View {
        if let step = coordinator.step, let progress = coordinator.progress {
            HStack(spacing: 12) {
                Image(systemName: progress.stage == .done ? "checkmark.circle.fill" : "graduationcap")
                    .font(.system(size: 20))
                    .foregroundStyle(MarginColor.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.titleKey(step)).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MarginColor.secondaryText)
                    Text(Self.instruction(step: step, progress: progress))
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(MarginColor.primaryText)
                }
                Spacer(minLength: 8)
                if progress.stage == .done {
                    pill("onboarding.continue", filled: true) { coordinator.next() }
                } else {
                    pill("onboarding.skip", filled: false) { coordinator.finish() }
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .animation(.easeOut(duration: 0.2), value: progress)
        }
    }

    private func pill(_ title: LocalizedStringKey, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(filled ? MarginColor.surface : MarginColor.accent)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(filled ? MarginColor.accent : MarginColor.accent.opacity(0.16))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    static func titleKey(_ step: OnboardingStep) -> LocalizedStringKey {
        LocalizedStringKey(titleName(step))
    }

    static func titleName(_ step: OnboardingStep) -> String { "onboarding.\(step.rawValue).title" }

    /// Built as a `String`, never an interpolated `LocalizedStringKey` (that is looked up as a format key and
    /// never found).
    static func instructionName(step: OnboardingStep, progress: PracticeProgress) -> String {
        if progress.failed { return "onboarding.coach.failed" }
        switch progress.stage {
        case .write: return "onboarding.coach.write"
        case .choose:
            return progress.pickedOther ? "onboarding.coach.other" : "onboarding.coach.choose.\(step.rawValue)"
        case .waiting: return "onboarding.coach.waiting"
        case .keep: return "onboarding.coach.keep"
        case .done: return "onboarding.coach.done"
        }
    }

    static func instruction(step: OnboardingStep, progress: PracticeProgress) -> String {
        let text = NSLocalizedString(instructionName(step: step, progress: progress), comment: "")
        guard progress.stage == .write, let example = step.example else { return text }
        let hint = step == .plot ? " " + NSLocalizedString("onboarding.coach.plot.hint", comment: "") : ""
        return String(format: text, example) + hint
    }
}
