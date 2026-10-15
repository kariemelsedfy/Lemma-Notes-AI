import SwiftUI

/// Owner-facing pilot settings (ADR-027/028). Interim consent copy until M6's consent flow replaces it.
struct PilotCloudSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    private let configuration: PilotCloudConfiguration

    @State private var consent: Bool
    @State private var serverText: String
    @State private var tokenDraft = ""
    @State private var hasToken: Bool
    @State private var tokenSaveFailed = false

    init(configuration: PilotCloudConfiguration = .standard) {
        self.configuration = configuration
        _consent = State(initialValue: configuration.consentGranted)
        _serverText = State(initialValue: configuration.serverText)
        _hasToken = State(initialValue: configuration.hasToken)
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
                Section("cloud.server.title") {
                    TextField("cloud.server.placeholder", text: $serverText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .onChange(of: serverText) { _, newValue in configuration.serverText = newValue }
                    if PilotCloudConfiguration.validatedURL(serverText) == nil {
                        Text("cloud.server.invalid").foregroundStyle(.red).font(.caption)
                    }
                }
                Section {
                    SecureField("cloud.token.placeholder", text: $tokenDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("cloud.token.save") { saveToken() }
                        .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if hasToken {
                        Button("cloud.token.remove", role: .destructive) { removeToken() }
                    }
                } header: {
                    Text("cloud.token.title")
                } footer: {
                    Text(hasToken ? "cloud.token.saved" : "cloud.token.missing")
                }
                Section {
                    Text(isReady ? "cloud.status.ready" : "cloud.status.off")
                }
            }
            .navigationTitle("cloud.title")
            .toolbar {
                Button("library.ok") { dismiss() }
            }
            .alert("cloud.token.failed", isPresented: $tokenSaveFailed) {
                Button("library.ok", role: .cancel) {}
            }
        }
    }

    private var isReady: Bool {
        consent && PilotCloudConfiguration.validatedURL(serverText) != nil && hasToken
    }

    private func saveToken() {
        if configuration.setToken(tokenDraft) {
            hasToken = configuration.hasToken
        } else {
            tokenSaveFailed = true
        }
        tokenDraft = ""
    }

    private func removeToken() {
        configuration.setToken(nil)
        hasToken = configuration.hasToken
    }
}
