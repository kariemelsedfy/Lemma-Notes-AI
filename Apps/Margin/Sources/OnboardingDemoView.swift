import DesignSystem
import SwiftUI

/// A prewritten, looping picture of the whole idea: write, circle, and the answer comes back in handwriting,
/// first for a sentence and then for an equation. Drawn in SwiftUI so there is no video to ship and it follows
/// Dark Mode and Dynamic Type.
struct OnboardingDemoView: View {
    struct Scene {
        let verb: AskVerb
        let question: String
        let answer: String
    }

    static let scenes = [
        Scene(verb: .explain, question: "what is photosynthesis", answer: "how plants turn light into food"),
        Scene(verb: .answer, question: "2x + 3 = 11", answer: "x = 4"),
    ]
    static let sceneLength: Double = 7.5
    private static let handwriting = "Noteworthy-Light"

    var body: some View {
        TimelineView(.animation) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            let cycle = Self.sceneLength * Double(Self.scenes.count)
            let time = seconds.truncatingRemainder(dividingBy: cycle)
            let index = min(Int(time / Self.sceneLength), Self.scenes.count - 1)
            page(Self.scenes[index], at: time - Double(index) * Self.sceneLength)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("onboarding.welcome.title")
    }

    private func page(_ scene: Scene, at time: Double) -> some View {
        let wrote = Self.progress(time, from: 0.3, to: 2.4)
        let circled = Self.progress(time, from: 2.8, to: 3.8)
        let answered = Self.progress(time, from: 4.6, to: 6.2)
        let tag = Self.progress(time, from: 3.8, to: 4.2)
        let visibility = min(
            1 - Self.progress(time, from: Self.sceneLength - 0.5, to: Self.sceneLength),
            Self.progress(time, from: 0, to: 0.4))
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(MarginColor.paper)
            VStack(alignment: .leading, spacing: 18) {
                writing(scene.question, color: MarginColor.ink, reveal: wrote)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .overlay {
                        Capsule()
                            .trim(from: 0, to: circled)
                            .stroke(
                                MarginColor.accent,
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [7, 6]))
                    }
                writing(scene.answer, color: MarginColor.accent, reveal: answered)
                    .padding(.leading, 16)
            }
            .padding(.leading, 12)
            .padding(.top, 22)
            Text(scene.verb.titleKey)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MarginColor.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(MarginColor.accent.opacity(0.16)))
                .opacity(tag)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .padding(14)
        }
        .frame(height: 190)
        .opacity(visibility)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MarginColor.divider))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
    }

    /// Handwriting that appears left to right, as if being written.
    private func writing(_ text: String, color: Color, reveal: Double) -> some View {
        Text(text)
            .font(.custom(Self.handwriting, size: 32))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .mask(alignment: .leading) { Rectangle().scaleEffect(x: reveal, anchor: .leading) }
    }

    /// 0 before `start`, 1 after `end`, eased in between.
    static func progress(_ time: Double, from start: Double, to end: Double) -> Double {
        let raw = (time - start) / (end - start)
        let clamped = min(max(raw, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}
