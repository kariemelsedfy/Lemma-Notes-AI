import SwiftUI

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// Shared visual tokens and components for Margin's interface.
public enum DesignSystemModule {}

/// Semantic colors with light and dark adaptive variants.
public enum MarginColor {
    public static let canvas = Color(light: 0xFCFCFE, dark: 0x121216)
    public static let surface = Color(light: 0xFFFFFF, dark: 0x1C1C21)
    public static let primaryText = Color(light: 0x17171C, dark: 0xF3F2F7)
    public static let secondaryText = Color(light: 0x666570, dark: 0xAAA8B4)
    public static let accent = Color(light: 0x5C5CE2, dark: 0x9A9AFF)
    public static let divider = Color(light: 0xE5E4EB, dark: 0x36353E)
}

/// The spacing scale keeps rhythm consistent across components.
public enum MarginSpacing {
    public static let xSmall: CGFloat = 4
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 16
    public static let xLarge: CGFloat = 24
    public static let xxLarge: CGFloat = 32
}

/// Typography roles instead of call-site-specific font choices.
public enum MarginTypography {
    public static let title = Font.system(.title2, design: .rounded).weight(.semibold)
    public static let body = Font.system(.body, design: .rounded)
    public static let caption = Font.system(.caption, design: .rounded)
}

/// SF Symbol names owned by the design system.
public enum MarginIcon: String, CaseIterable, Sendable {
    case ask = "sparkles"
    case pen = "pencil.tip"
    case eraser = "eraser"
    case library = "books.vertical"
    case settings = "gearshape"
}

/// A lightweight gallery for reviewing every currently available token.
public struct DesignSystemGallery: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MarginSpacing.xLarge) {
                Text("Margin design system")
                    .font(MarginTypography.title)
                    .foregroundStyle(MarginColor.primaryText)
                tokenSection("Colors") {
                    HStack(spacing: MarginSpacing.small) {
                        colorToken("Canvas", color: MarginColor.canvas)
                        colorToken("Surface", color: MarginColor.surface)
                        colorToken("Accent", color: MarginColor.accent)
                        colorToken("Primary", color: MarginColor.primaryText)
                        colorToken("Secondary", color: MarginColor.secondaryText)
                        colorToken("Divider", color: MarginColor.divider)
                    }
                }
                tokenSection("Typography") {
                    VStack(alignment: .leading, spacing: MarginSpacing.small) {
                        Text("Title").font(MarginTypography.title)
                        Text("Body text").font(MarginTypography.body)
                        Text("Caption").font(MarginTypography.caption)
                    }
                }
                tokenSection("Icons") {
                    HStack(spacing: MarginSpacing.large) {
                        ForEach(MarginIcon.allCases, id: \.self) { icon in
                            Image(systemName: icon.rawValue).accessibilityLabel(icon.rawValue)
                        }
                    }
                    .foregroundStyle(MarginColor.accent)
                }
                tokenSection("Spacing") {
                    HStack(alignment: .bottom, spacing: MarginSpacing.medium) {
                        spacingToken("XS", value: MarginSpacing.xSmall)
                        spacingToken("S", value: MarginSpacing.small)
                        spacingToken("M", value: MarginSpacing.medium)
                        spacingToken("L", value: MarginSpacing.large)
                        spacingToken("XL", value: MarginSpacing.xLarge)
                        spacingToken("XXL", value: MarginSpacing.xxLarge)
                    }
                }
            }
            .padding(MarginSpacing.xLarge)
        }
        .background(MarginColor.canvas)
    }

    @ViewBuilder
    private func tokenSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MarginSpacing.small) {
            Text(title).font(MarginTypography.caption).foregroundStyle(MarginColor.secondaryText)
            content()
        }
        .padding(MarginSpacing.large)
        .background(MarginColor.surface, in: RoundedRectangle(cornerRadius: MarginSpacing.medium))
    }

    private func colorToken(_ name: String, color: Color) -> some View {
        VStack(spacing: MarginSpacing.xSmall) {
            RoundedRectangle(cornerRadius: MarginSpacing.small)
                .fill(color)
                .frame(width: 48, height: 48)
                .overlay(RoundedRectangle(cornerRadius: MarginSpacing.small).stroke(MarginColor.divider))
            Text(name).font(MarginTypography.caption)
        }
    }

    private func spacingToken(_ name: String, value: CGFloat) -> some View {
        VStack(spacing: MarginSpacing.xSmall) {
            RoundedRectangle(cornerRadius: MarginSpacing.xSmall)
                .fill(MarginColor.accent)
                .frame(width: value, height: value)
                .frame(height: MarginSpacing.xxLarge)
            Text(name).font(MarginTypography.caption)
        }
    }
}

extension Color {
    fileprivate init(light: UInt32, dark: UInt32) {
        #if os(iOS)
            self.init(uiColor: UIColor { traits in rgb(traits.userInterfaceStyle == .dark ? dark : light) })
        #elseif os(macOS)
            self.init(
                nsColor: NSColor(name: nil) { appearance in
                    let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    return rgb(isDark ? dark : light)
                })
        #endif
    }
}

private func rgb(_ value: UInt32) -> PlatformColor {
    PlatformColor(
        red: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
    )
}

#if os(iOS)
    private typealias PlatformColor = UIColor
#elseif os(macOS)
    private typealias PlatformColor = NSColor
#endif
