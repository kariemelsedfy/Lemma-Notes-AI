import SwiftUI

/// Owner-facing pilot settings (ADR-027/028). Interim consent copy until M6's consent flow replaces it.
/// The server address and token are provisioned at build time, so the only choice left here is consent.
struct PilotCloudSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    private let configuration: PilotCloudConfiguration

    @State private var consent: Bool

    init(configuration: PilotCloudConfiguration = .standard) {
        self.configuration = configuration
        _consent = State(initialValue: configuration.consentGranted)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("cloud.consent.toggle", isOn: $consent)
                        .onChange(of: consent) { _, newValue in configuration.consentGranted = newValue }
                } footer: {
                    Text("cloud.consent.disclosure")
                }
                Section {
                    Text(statusKey)
                }
            }
            .navigationTitle("cloud.title")
            .toolbar {
                Button("library.ok") { dismiss() }
            }
        }
    }

    private var statusKey: LocalizedStringKey {
        if !configuration.hasToken { return "cloud.status.unavailable" }
        return consent ? "cloud.status.ready" : "cloud.status.off"
    }
}
