import DesignSystem
import Handwriting
import SwiftUI

/// "Teach it just some characters" (the quicker alternative to calibrating from the start).
///
/// Goes straight to the writing grid for whatever the writer's handwriting is missing. When nothing is
/// missing, the writer taps the characters they want to redo instead. The result is merged into the
/// existing bank, so nothing else they have taught is lost.
struct AddCharactersView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: HandwritingStyleStore

    private enum Route {
        case characters([Character])
        case startOver
    }

    @State private var route: Route?
    @State private var picked: Set<Character> = []

    var body: some View {
        switch route ?? initialRoute {
        case .characters(let characters):
            CalibrationView(store: store, characters: characters)
        case .startOver:
            CalibrationView(store: store)
        case nil:
            picker
        }
    }

    /// Straight to writing when something is missing; a bank saved before the normalization size was recorded
    /// cannot take new characters at the right scale, so it is offered a full pass instead.
    private var initialRoute: Route? {
        guard let bank = store.bank else { return .startOver }
        guard bank.normalizationXHeight != nil else { return nil }
        let missing = CalibrationSheet.standardCharacters.filter { bank.samples(for: $0).isEmpty }
        return missing.isEmpty ? nil : .characters(missing)
    }

    private var canAddToBank: Bool { store.bank?.normalizationXHeight != nil }

    private var picker: some View {
        NavigationStack {
            Group {
                if canAddToBank {
                    ScrollView {
                        VStack(alignment: .leading, spacing: MarginSpacing.large) {
                            Text("calibration.add.pick")
                                .font(MarginTypography.body)
                                .foregroundStyle(MarginColor.secondaryText)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
                                ForEach(CalibrationSheet.standardCharacters, id: \.self) { character in
                                    characterButton(character)
                                }
                            }
                            Button("calibration.add.start") {
                                route = .characters(
                                    CalibrationSheet.standardCharacters.filter { picked.contains($0) })
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(picked.isEmpty)
                        }
                        .padding(MarginSpacing.xLarge)
                    }
                } else {
                    VStack(spacing: MarginSpacing.large) {
                        Text("calibration.add.legacy")
                            .font(MarginTypography.body)
                        Button("calibration.start") { route = .startOver }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(MarginSpacing.xLarge)
                }
            }
            .background(MarginColor.canvas)
            .navigationTitle("calibration.add.nav")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("library.cancel") { dismiss() }
                }
            }
        }
    }

    private func characterButton(_ character: Character) -> some View {
        let isPicked = picked.contains(character)
        return Button {
            if isPicked { picked.remove(character) } else { picked.insert(character) }
        } label: {
            Text(String(character))
                .font(.title3)
                .frame(minWidth: 44, minHeight: 44)
                .background(isPicked ? MarginColor.accent.opacity(0.25) : MarginColor.paper)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }
}
