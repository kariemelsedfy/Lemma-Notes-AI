import DocumentStore
import Handwriting
import InkCore
import SwiftUI

#if DEBUG
    /// Debug builds only: `-margin.openNewNote` creates a note and opens it at launch, so a Simulator screenshot of
    /// the notebook screen needs no taps. Never compiled into a release build.
    struct DebugOpenNewNote: ViewModifier {
        let open: () -> Void

        func body(content: Content) -> some View {
            content.task {
                guard ProcessInfo.processInfo.arguments.contains("-margin.openNewNote") else { return }
                try? await Task.sleep(for: .milliseconds(600))
                open()
            }
        }
    }
#endif

extension View {
    @ViewBuilder
    func debugOpenNewNote(_ open: @escaping () -> Void) -> some View {
        #if DEBUG
            modifier(DebugOpenNewNote(open: open))
        #else
            self
        #endif
    }
}

#if DEBUG
    /// A synthetic handwriting bank (typeset letters, sheared a little differently for each variant) so the gallery
    /// can be screenshotted without calibrating. Never reaches a release build.
    enum DebugBank {
        static func sample() -> GlyphBank {
            let reference = CGRect(x: 0, y: 0, width: 120, height: 120)
            var bank = GlyphBank(capturedAt: Date(timeIntervalSince1970: 0))
            let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+-=()?!.,")
            guard let xStrokes = try? TypesetStyle.strokes(for: "x", in: reference) else { return bank }
            let xHeight = InkLineGrouping.bounds(of: xStrokes).height
            bank.normalizationXHeight = xHeight
            for (index, character) in characters.enumerated() {
                guard let strokes = try? TypesetStyle.strokes(for: String(character), in: reference) else { continue }
                for variant in 0..<(1 + (index + 1) % 3) {
                    let shear = CGFloat(variant) * 0.12 - 0.05
                    let slanted = strokes.map { stroke in
                        InkStroke(
                            points: stroke.points.map {
                                InkPoint(
                                    location: CGPoint(x: $0.location.x - $0.location.y * shear, y: $0.location.y),
                                    timeOffset: $0.timeOffset, force: $0.force, altitude: $0.altitude,
                                    azimuth: $0.azimuth, size: $0.size)
                            })
                    }
                    if let glyph = try? GlyphNormalizer.glyph(for: character, from: slanted, xHeight: xHeight) {
                        bank.add(glyph)
                    }
                }
            }
            return bank
        }
    }

    /// Debug builds only: `-margin.scenario <name>` stages the app for a Simulator screenshot or recording with no taps
    /// (README media). `seed` fills the library with sample notes and folders; `paywall` opens Premium;
    /// `tour-welcome`, `tour-handwriting`, `tour-disclosure` and `tour-subscribe` jump to a step of the first-run tour.
    private struct SampleNote {
        let title: String
        let paper: PaperStyle
        let folder: UUID?
        let favorite: Bool

        init(_ title: String, _ paper: PaperStyle, _ folder: UUID?, _ favorite: Bool = false) {
            self.title = title
            self.paper = paper
            self.folder = folder
            self.favorite = favorite
        }
    }

    struct DebugScenario: ViewModifier {
        let library: NotebookLibrary
        let onboarding: OnboardingCoordinator
        let premium: PremiumStore
        let handwriting: HandwritingStyleStore
        let showGallery: () -> Void

        func body(content: Content) -> some View {
            content.task { await run() }
        }

        @MainActor
        private func run() async {
            let arguments = ProcessInfo.processInfo.arguments
            guard let flag = arguments.firstIndex(of: "-margin.scenario"), flag + 1 < arguments.count else { return }
            try? await Task.sleep(for: .milliseconds(500))
            switch arguments[flag + 1] {
            case "seed": seed()
            case "paywall": premium.showPaywall()
            case "gallery":
                handwriting.save(DebugBank.sample())
                showGallery()
            case "tour-welcome": jump(to: .welcome)
            case "tour-handwriting": jump(to: .handwriting)
            case "tour-disclosure": jump(to: .disclosure)
            case "tour-subscribe": jump(to: .subscribe)
            default: break
            }
        }

        private func jump(to step: OnboardingStep) {
            onboarding.start()
            while onboarding.step != step, onboarding.step != nil { onboarding.next() }
        }

        private func seed() {
            guard library.notebooks.isEmpty else { return }
            let biology = library.createFolder(name: "Biology", colorHex: 0x0B_5227)
            let calculus = library.createFolder(name: "Calculus", colorHex: 0x2C_63E0)
            let reading = library.createFolder(name: "Reading", colorHex: 0xAB_1E4A)
            let size = PageSizePreset.default.size
            let samples = [
                SampleNote("Photosynthesis", .ruled, biology?.id, true),
                SampleNote("Derivatives", .grid5Millimeters, calculus?.id, true),
                SampleNote("Limits and continuity", .grid5Millimeters, calculus?.id),
                SampleNote("Cell respiration", .ruled, biology?.id),
                SampleNote("Essay outline", .ruled, reading?.id),
                SampleNote("Sketches", .dotted, nil),
                SampleNote("Problem set 4", .grid5Millimeters, calculus?.id),
                SampleNote("Lecture notes", .blank, nil),
            ]
            for sample in samples {
                guard
                    let note = library.create(
                        title: sample.title, paper: sample.paper, size: size, folderID: sample.folder)
                else { continue }
                if sample.favorite { library.setFavorite(true, notebook: note.id) }
            }
        }
    }
#endif

extension View {
    @ViewBuilder
    func debugScenario(
        _ library: NotebookLibrary, _ tour: OnboardingCoordinator, _ store: PremiumStore,
        _ handwriting: HandwritingStyleStore, showGallery: @escaping () -> Void
    ) -> some View {
        #if DEBUG
            modifier(
                DebugScenario(
                    library: library, onboarding: tour, premium: store, handwriting: handwriting,
                    showGallery: showGallery))
        #else
            self
        #endif
    }
}
