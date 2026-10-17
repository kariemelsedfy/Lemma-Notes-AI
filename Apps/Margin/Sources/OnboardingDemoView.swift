import DesignSystem
import SwiftUI

/// A prewritten, looping picture of the whole idea: write, circle, and the answer comes back in handwriting.
/// Drawn in SwiftUI so there is no video to ship and it follows Dark Mode and Dynamic Type.
struct OnboardingDemoView: View {
    private static let cycle: Double = 7
    private static let writing = "what is 12 + 30"
    private static let answer = "= 42"

    var body: some View {
        TimelineView(.animation) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            let time = seconds.truncatingRemainder(dividingBy: Self.cycle)
            page(at: time)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("onboarding.welcome.title")
    }

    private func page(at time: Double) -> some View {
        let wrote = Self.progress(time, from: 0.3, to: 2.4)
        let circled = Self.progress(time, from: 2.8, to: 3.8)
        let answered = Self.progress(time, from: 4.4, to: 5.6)
        let fade = min(1 - Self.progress(time, from: 6.5, to: 7), Self.progress(time, from: 0, to: 0.4))
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(MarginColor.paper)
            Text(Self.writing)
                .font(.custom("Noteworthy-Light", size: 34))
                .foregroundStyle(MarginColor.ink)
                .mask(alignment: .leading) { Rectangle().scaleEffect(x: wrote, anchor: .leading) }
                .padding(.leading, 28)
                .padding(.top, 36)
            Capsule()
                .trim(from: 0, to: circled)
                .stroke(MarginColor.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [7, 6]))
                .frame(width: 290, height: 66)
                .padding(.leading, 16)
                .padding(.top, 24)
            Text(Self.answer)
                .font(.custom("Noteworthy-Light", size: 34))
                .foregroundStyle(MarginColor.accent)
                .mask(alignment: .leading) { Rectangle().scaleEffect(x: answered, anchor: .leading) }
                .padding(.leading, 28)
                .padding(.top, 108)
        }
        .frame(height: 190)
        .opacity(fade)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MarginColor.divider))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
    }

    /// 0 before `start`, 1 after `end`, eased in between.
    static func progress(_ time: Double, from start: Double, to end: Double) -> Double {
        let raw = (time - start) / (end - start)
        let clamped = min(max(raw, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}
