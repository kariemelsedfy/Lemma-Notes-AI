import DocumentStore
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
