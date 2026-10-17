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

/// The last step: an invitation, never a gate. There is no purchase button until StoreKit lands (M6); the free
/// notebook is complete without it.
struct OnboardingInvitation: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: MarginSpacing.large) {
            Image(systemName: "sparkles")
                .font(.system(size: 52))
                .foregroundStyle(MarginColor.accent)
            Text("onboarding.subscribe.title")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("onboarding.subscribe.body")
                .font(.system(size: 18))
                .foregroundStyle(MarginColor.secondaryText)
                .multilineTextAlignment(.center)
            VStack(spacing: MarginSpacing.xSmall) {
                Text("onboarding.subscribe.trial").font(.system(size: 20, weight: .semibold))
                Text("onboarding.subscribe.price").foregroundStyle(MarginColor.secondaryText)
            }
            Button(action: onDone) {
                Text("onboarding.later")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
        .tint(MarginColor.accent)
            .controlSize(.large)
        }
        .padding(MarginSpacing.xxLarge)
        .frame(maxWidth: 560)
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }
}
