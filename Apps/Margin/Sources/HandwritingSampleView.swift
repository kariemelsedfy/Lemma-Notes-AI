#if DEBUG

    import DesignSystem
    import Handwriting
    import InkCore
    import SwiftUI

    /// Write a line, see the same line in your synthesized hand, export both (M3-24).
    ///
    /// **Debug-only, deliberately.** It exists to produce material for the M3-10 panel and to be
    /// the first place anyone has ever seen a *sentence* in their own synthesized handwriting.
    /// Whether a version of this belongs in the shipping app is a product question — it would
    /// make a good "see what calibration bought you" moment (M3-13) — and it should be designed
    /// rather than inherited from a diagnostic screen.
    struct HandwritingSampleView: View {
        @ObservedObject var store: HandwritingStyleStore
        @Environment(\.dismiss) private var dismiss

        @State private var text = HandwritingSample.suggestions[0]
        @State private var written: [InkStroke] = []
        @State private var canvasGeneration = 0
        @State private var generated: [InkStroke] = []
        @State private var problem: String?
        @State private var pendingShare: ShareItem?

        var body: some View {
            NavigationStack {
                Form {
                    Section("sample.line") {
                        TextField("sample.line", text: $text)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Picker("sample.suggestion", selection: $text) {
                            ForEach(HandwritingSample.suggestions, id: \.self) { Text($0).tag($0) }
                        }
                    }

                    Section("sample.yours") {
                        CalibrationCanvas(generation: canvasGeneration) { strokes in
                            written = strokes
                            regenerate()
                        }
                        .frame(height: 140)
                        .background(MarginColor.paper)
                        Button("sample.clear") {
                            canvasGeneration += 1
                            written = []
                            generated = []
                        }
                    }

                    Section("sample.generated") {
                        if let problem {
                            Text(problem).foregroundStyle(MarginColor.accent)
                        } else if generated.isEmpty {
                            Text("sample.write.first").foregroundStyle(.secondary)
                        } else {
                            SampleInkView(strokes: generated)
                                .frame(height: 140)
                                .background(MarginColor.paper)
                        }
                    }

                    Section {
                        Button("sample.share.generated") { share(generated) }
                            .disabled(generated.isEmpty)
                        Button("sample.share.mine") { share(written) }
                            .disabled(written.isEmpty)
                    } footer: {
                        Text("sample.panel.hint")
                    }
                }
                .onChange(of: text) { _, _ in regenerate() }
                .navigationTitle("sample.title")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("sample.done") { dismiss() }
                    }
                }
                .sheet(item: $pendingShare) { ShareSheet(fileURL: $0.url) }
            }
        }

        private func regenerate() {
            problem = nil
            guard !written.isEmpty else {
                generated = []
                return
            }
            do {
                generated = try HandwritingSample.generated(text, bank: store.bank, matching: written)
            } catch HandwritingSample.Error.missingCharacters(let characters) {
                generated = []
                problem = String(
                    format: NSLocalizedString("sample.missing", comment: ""),
                    characters.sorted().map(String.init).joined(separator: " ")
                )
            } catch {
                generated = []
                problem = NSLocalizedString("sample.failed", comment: "")
            }
        }

        private func share(_ strokes: [InkStroke]) {
            guard let data = try? HandwritingSample.image(of: strokes) else { return }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("margin-sample-\(UUID().uuidString).png")
            guard (try? data.write(to: url)) != nil else { return }
            pendingShare = ShareItem(url: url)
        }
    }

    /// Draws ink as plain paths. Not a `PKCanvasView`: this is a picture of ink, nothing here is
    /// editable, and a canvas would invite the user to write on their own sample.
    private struct SampleInkView: View {
        let strokes: [InkStroke]

        var body: some View {
            GeometryReader { geometry in
                let bounds = InkLineGrouping.bounds(of: strokes)
                let scale = bounds.width > 0 ? min(geometry.size.width / bounds.width, 1) : 1
                Canvas { context, _ in
                    for stroke in strokes {
                        var path = Path()
                        let points = stroke.points.map {
                            CGPoint(
                                x: ($0.location.x - bounds.minX) * scale,
                                y: ($0.location.y - bounds.minY) * scale
                            )
                        }
                        guard let first = points.first else { continue }
                        path.move(to: first)
                        for point in points.dropFirst() { path.addLine(to: point) }
                        context.stroke(
                            path,
                            with: .color(MarginColor.ink),
                            style: StrokeStyle(
                                lineWidth: InkRenderingLimits.drawnWidth(
                                    forSize: stroke.points[0].size.width) * scale,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    /// A wrapper rather than a retroactive `Identifiable` on `URL`: conforming someone else's
    /// type to someone else's protocol is a collision waiting for the next SDK, and the lint
    /// rule that catches it is right.
    private struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

#endif
