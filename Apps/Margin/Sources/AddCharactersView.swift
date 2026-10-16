import DesignSystem
import Handwriting
import SwiftUI

/// "Teach it just these characters" (the quicker alternative to calibrating from the start).
///
/// The writer types or pastes the characters they want to add or redo, or taps to use every standard
/// character their handwriting is currently missing. Writing then happens on repair sheets only, and the
/// result is merged into the existing bank.
struct AddCharactersView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: HandwritingStyleStore

    @State private var typed = ""
    @State private var chosen: [Character]?

    var body: some View {
        if let chosen {
            CalibrationView(store: store, characters: chosen)
        } else {
            NavigationStack {
                Form {
                    Section {
                        TextField("calibration.add.placeholder", text: $typed)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("calibration.add.title")
                    } footer: {
                        Text("calibration.add.footer")
                    }
                    if !missingStandard.isEmpty {
                        Section {
                            Text(String(missingStandard))
                                .font(MarginTypography.body)
                            Button("calibration.add.use-missing \(missingStandard.count)") {
                                typed = String(missingStandard)
                            }
                        } header: {
                            Text("calibration.add.missing")
                        }
                    }
                    Section {
                        Button("calibration.add.start") { chosen = requested }
                            .disabled(requested.isEmpty)
                    }
                }
                .navigationTitle("calibration.add.nav")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("library.cancel") { dismiss() }
                    }
                }
            }
        }
    }

    /// What the writer asked for: unique, non-space characters in the order typed.
    private var requested: [Character] {
        var seen: Set<Character> = []
        return typed.filter { !$0.isWhitespace && seen.insert($0).inserted }.map { $0 }
    }

    /// Standard calibration characters the current bank has no sample of.
    private var missingStandard: [Character] {
        guard let bank = store.bank else { return [] }
        return CalibrationSheet.standardCharacters.filter { bank.samples(for: $0).isEmpty }
    }
}
