import DesignSystem
import SwiftUI

/// The tour's full-screen cards: welcome, handwriting, and the AI disclosure.
struct OnboardingCards: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject var handwriting: HandwritingStyleStore
    @State private var calibrationPresented = false

    var body: some View {
        VStack(spacing: MarginSpacing.xLarge) {
            HStack {
                Spacer()
                Button("onboarding.skip") { coordinator.finish() }
                    .foregroundStyle(MarginColor.secondaryText)
            }
            Spacer(minLength: 0)
            card
            Spacer(minLength: 0)
            actions
        }
        .padding(MarginSpacing.xxLarge)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MarginColor.canvas)
        .sheet(
            isPresented: $calibrationPresented,
            onDismiss: { coordinator.next() },
            content: { CalibrationView(store: handwriting) })
    }

    @ViewBuilder
    private var card: some View {
        switch coordinator.step {
        case .handwriting:
            copy(symbol: "signature", title: "onboarding.handwriting.title", body: "onboarding.handwriting.body")
        case .disclosure:
            copy(symbol: "lock.shield", title: "onboarding.disclosure.title", body: "onboarding.disclosure.body")
        default:
            VStack(spacing: MarginSpacing.xLarge) {
                OnboardingDemoView()
                Text("onboarding.welcome.title")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("onboarding.welcome.body")
                    .font(.system(size: 18))
                    .foregroundStyle(MarginColor.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func copy(symbol: String, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        VStack(spacing: MarginSpacing.large) {
            Image(systemName: symbol)
                .font(.system(size: 52))
                .foregroundStyle(MarginColor.accent)
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text(body)
                .font(.system(size: 18))
                .foregroundStyle(MarginColor.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch coordinator.step {
        case .handwriting:
            VStack(spacing: MarginSpacing.small) {
                primary("onboarding.handwriting.teach") { calibrationPresented = true }
                secondary("onboarding.later") { coordinator.next() }
            }
        case .disclosure:
            VStack(spacing: MarginSpacing.small) {
                primary("onboarding.disclosure.accept") { coordinator.acceptDisclosure() }
                secondary("onboarding.disclosure.decline") { coordinator.declineDisclosure() }
            }
        default:
            primary("onboarding.continue") { coordinator.next() }
        }
    }

    private func primary(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.borderedProminent)
        .tint(MarginColor.accent)
        .controlSize(.large)
    }

    private func secondary(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 17))
            .foregroundStyle(MarginColor.secondaryText)
            .frame(minHeight: 44)
    }
}

/// The last step: an invitation, never a gate. The subscribe button has nothing to buy until StoreKit lands (M6),
/// so for now it ends the tour like "Maybe later" does; the free notebook is complete without it.
struct OnboardingInvitation: View {
    enum Choice { case annual, monthly }

    let onSubscribe: (Choice) -> Void
    let onLater: () -> Void
    @State private var choice = Choice.annual

    var body: some View {
        ScrollView {
            VStack(spacing: MarginSpacing.xLarge) {
                header
                benefits
                HStack(spacing: MarginSpacing.medium) {
                    planCard(
                        .annual, title: "onboarding.plan.annual", price: "onboarding.plan.annual.price",
                        note: "onboarding.plan.annual.per", badge: "onboarding.plan.annual.badge")
                    planCard(
                        .monthly, title: "onboarding.plan.monthly", price: "onboarding.plan.monthly.price",
                        note: "onboarding.plan.monthly.per", badge: nil)
                }
                VStack(spacing: MarginSpacing.small) {
                    Button {
                        onSubscribe(choice)
                    } label: {
                        Text("onboarding.cta")
                            .font(.system(size: 20, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MarginColor.accent)
                    .controlSize(.large)
                    Text(choice == .annual ? "onboarding.fine.annual" : "onboarding.fine.monthly")
                        .font(.system(size: 14))
                        .foregroundStyle(MarginColor.secondaryText)
                }
                Button("onboarding.later", action: onLater)
                    .font(.system(size: 15))
                    .foregroundStyle(MarginColor.secondaryText)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, MarginSpacing.xxLarge)
            .padding(.vertical, 48)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(MarginColor.canvas)
    }

    private var header: some View {
        VStack(spacing: MarginSpacing.medium) {
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(MarginColor.accent)
            Text("onboarding.subscribe.title")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("onboarding.subscribe.body")
                .font(.system(size: 18))
                .foregroundStyle(MarginColor.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: MarginSpacing.medium) {
            benefit("pencil.and.scribble", "onboarding.benefit.handwriting")
            benefit("text.bubble", "onboarding.benefit.explain")
            benefit("equal.square", "onboarding.benefit.solve")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MarginSpacing.large)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(MarginColor.surface))
    }

    private func benefit(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: MarginSpacing.medium) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(MarginColor.accent)
                .frame(width: 30)
            Text(text).font(.system(size: 17, weight: .medium))
        }
    }

    private func planCard(
        _ plan: Choice, title: LocalizedStringKey, price: LocalizedStringKey, note: LocalizedStringKey,
        badge: LocalizedStringKey?
    ) -> some View {
        let selected = choice == plan
        return Button {
            choice = plan
        } label: {
            VStack(spacing: MarginSpacing.xSmall) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(MarginColor.surface)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(MarginColor.accent))
                } else {
                    Spacer().frame(height: 22)
                }
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(price).font(.system(size: 22, weight: .bold, design: .rounded))
                Text(note).font(.system(size: 14)).foregroundStyle(MarginColor.secondaryText)
            }
            .foregroundStyle(MarginColor.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, MarginSpacing.large)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(selected ? MarginColor.accent.opacity(0.14) : MarginColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(selected ? MarginColor.accent : MarginColor.divider, lineWidth: selected ? 2.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Shows the tour over the library: starts it on first launch, covers the screen for the cards, and sheets the
/// invitation. A modifier of its own so the library view's body stays quick to type-check.
struct OnboardingPresentation: ViewModifier {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject var handwriting: HandwritingStyleStore
    let onStep: (OnboardingStep?) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { coordinator.startIfNeeded() }
            .onChange(of: coordinator.step) { _, step in onStep(step) }
            .fullScreenCover(isPresented: .constant(coordinator.showsCards)) {
                OnboardingCards(coordinator: coordinator, handwriting: handwriting)
            }
            .fullScreenCover(isPresented: .constant(coordinator.showsInvitation)) {
                OnboardingInvitation(onSubscribe: { _ in coordinator.finish() }, onLater: { coordinator.finish() })
            }
    }
}
