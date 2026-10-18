import SwiftUI

@main
struct MarginApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var library = NotebookLibrary()
    @StateObject private var premium = PremiumStore(uploadTransaction: { signed in
        // A failure is not final: the next refresh sends it again.
        await PilotCloudConfiguration.standard.installs.flatMap { $0 as? InstallSession }?.uploadIgnoringFailure(signed)
    })

    var body: some Scene {
        WindowGroup {
            NotebookLibraryView(library: library)
                .environmentObject(premium)
                .task { await premium.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the foreground is the last reliable moment to write. The autosave's
            // quiet period is an optimisation, never a promise about unsaved work.
            guard phase != .active else { return }
            Task { await library.autosave.flush() }
        }
    }
}
