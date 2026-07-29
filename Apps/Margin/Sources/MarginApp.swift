import SwiftUI

@main
struct MarginApp: App {
    var body: some Scene {
        WindowGroup {
            PaperCanvas(style: .ruled)
                .background(.background)
                .ignoresSafeArea()
        }
    }
}
