import DesignSystem
import SwiftUI

/// The places a free user is invited to upgrade. Each one is quiet, opens the same Premium screen, and goes away
/// the moment the plan is no longer free (`PremiumStore.offersUpgrade`).
struct UpgradeBanner: View {
    @EnvironmentObject private var premium: PremiumStore
    @State private var dismissed = false

    var body: some View {
        if premium.offersUpgrade, !dismissed {
            HStack(spacing: MarginSpacing.medium) {
                Image(systemName: "sparkles")
                    .font(.system(size: 26))
                    .foregroundStyle(MarginColor.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("upgrade.banner.title")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("upgrade.banner.subtitle")
                        .font(.system(size: 14))
                        .foregroundStyle(MarginColor.secondaryText)
                }
                Spacer(minLength: MarginSpacing.small)
                Button("upgrade.try") { premium.showPaywall() }
                    .buttonStyle(.filledPill)
                Button {
                    withAnimation { dismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MarginColor.secondaryText)
                        .frame(width: 32, height: 44)
                }
                .accessibilityLabel("upgrade.dismiss")
            }
            .padding(MarginSpacing.large)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(MarginColor.accent.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(MarginColor.accent.opacity(0.3)))
        }
    }
}

/// A compact card for the bottom of the sidebar.
struct UpgradeSidebarCard: View {
    @EnvironmentObject private var premium: PremiumStore

    var body: some View {
        if premium.offersUpgrade {
            Button {
                premium.showPaywall()
            } label: {
                HStack(spacing: MarginSpacing.medium) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20))
                        .foregroundStyle(MarginColor.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("upgrade.sidebar.title").font(.system(size: 15, weight: .semibold))
                        Text("upgrade.sidebar.subtitle")
                            .font(.system(size: 12))
                            .foregroundStyle(MarginColor.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(MarginColor.primaryText)
                .padding(MarginSpacing.medium)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MarginColor.accent.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .padding(MarginSpacing.medium)
        }
    }
}

/// The small pill in a notebook's top bar.
struct UpgradeToolbarButton: View {
    @EnvironmentObject private var premium: PremiumStore

    var body: some View {
        if premium.offersUpgrade {
            Button {
                premium.showPaywall()
            } label: {
                Label("upgrade.toolbar", systemImage: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MarginColor.accent)
            }
        }
    }
}
