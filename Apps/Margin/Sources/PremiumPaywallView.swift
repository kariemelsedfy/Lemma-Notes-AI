import DesignSystem
import SwiftUI

/// The Premium screen: shown at the end of the tour, when a free user asks for something hosted, and from the
/// gear menu. Prices and the trial come from the App Store; the strings below are only what shows before they load.
struct PremiumPaywallView: View {
    @EnvironmentObject private var store: PremiumStore
    @State private var choice = PremiumProduct.yearly
    @State private var acknowledged = OnboardingStore().hasAcknowledgedDisclosure
    @State private var notice: LocalizedStringKey?

    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: MarginSpacing.xLarge) {
                header
                benefits
                HStack(spacing: MarginSpacing.medium) {
                    planCard(.yearly)
                    planCard(.monthly)
                }
                VStack(spacing: MarginSpacing.small) {
                    disclosure
                    subscribeButton
                    Text(finePrint)
                        .font(.system(size: 14))
                        .foregroundStyle(MarginColor.secondaryText)
                        .multilineTextAlignment(.center)
                    if let notice {
                        Text(notice)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(MarginColor.accent)
                            .multilineTextAlignment(.center)
                    }
                }
                footer
            }
            .padding(.horizontal, MarginSpacing.xxLarge)
            .padding(.vertical, 48)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(MarginColor.canvas)
        .task { await store.start() }
        .onChange(of: store.plan) { _, plan in if plan != .free { onClose() } }
    }

    // MARK: - Pieces

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

    private func planCard(_ product: PremiumProduct) -> some View {
        let selected = choice == product
        let isYearly = product == .yearly
        return Button {
            choice = product
        } label: {
            VStack(spacing: MarginSpacing.xSmall) {
                if isYearly {
                    Text("onboarding.plan.annual.badge")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(MarginColor.surface)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(MarginColor.accent))
                } else {
                    Spacer().frame(height: 22)
                }
                Text(isYearly ? "onboarding.plan.annual" : "onboarding.plan.monthly")
                    .font(.system(size: 17, weight: .semibold))
                Text(price(of: product))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(isYearly ? "onboarding.plan.annual.per" : "onboarding.plan.monthly.per")
                    .font(.system(size: 14))
                    .foregroundStyle(MarginColor.secondaryText)
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

    /// The App Store's own price, in the user's currency, once it has loaded.
    private func price(of product: PremiumProduct) -> String {
        store.offer(for: product)?.displayPrice ?? NSLocalizedString(Self.fallbackPriceKey(product), comment: "")
    }

    static func fallbackPriceKey(_ product: PremiumProduct) -> String {
        product == .yearly ? "onboarding.plan.annual.price" : "onboarding.plan.monthly.price"
    }

    /// AI disclosure (ADR-029, App Store 5.1.2(i)): consent is separate from the purchase and is recorded.
    private var disclosure: some View {
        Toggle(isOn: $acknowledged) {
            Text("premium.disclosure")
                .font(.system(size: 14))
                .foregroundStyle(MarginColor.secondaryText)
        }
        .tint(MarginColor.accent)
    }

    private var subscribeButton: some View {
        Button(action: subscribe) {
            HStack {
                if store.phase == .purchasing { ProgressView().tint(MarginColor.surface) }
                Text(hasTrial ? "onboarding.cta" : "premium.cta.plain")
                    .font(.system(size: 20, weight: .bold))
            }
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.borderedProminent)
        .tint(MarginColor.accent)
        .controlSize(.large)
        .disabled(!acknowledged || store.phase == .purchasing || store.phase == .restoring)
    }

    /// Shows the trial unless the App Store has told us this plan has none.
    private var hasTrial: Bool { store.offer(for: choice)?.hasFreeTrial ?? true }

    private var finePrint: LocalizedStringKey {
        choice == .yearly ? "onboarding.fine.annual" : "onboarding.fine.monthly"
    }

    private var footer: some View {
        VStack(spacing: MarginSpacing.xSmall) {
            Button("premium.restore") { Task { await restore() } }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(MarginColor.accent)
                .frame(minHeight: 44)
            Button("onboarding.later", action: onClose)
                .font(.system(size: 15))
                .foregroundStyle(MarginColor.secondaryText)
                .frame(minHeight: 44)
        }
    }

    // MARK: - Actions

    private func subscribe() {
        guard acknowledged else { return }
        OnboardingStore().acknowledgeDisclosure()
        notice = nil
        Task {
            switch await store.purchase(choice) {
            case .purchased?, .cancelled?: break
            case .pending?: notice = "premium.pending"
            case nil: notice = "premium.error"
            }
        }
    }

    private func restore() async {
        notice = nil
        await store.restore()
        if store.phase == .failed {
            notice = "premium.error"
        } else if store.restoreFoundNothing {
            notice = "premium.restore.none"
        }
    }
}
