import SwiftUI

@main
struct MarginApp: App {
    var body: some Scene {
        WindowGroup {
            Rectangle()
                .fill(.background)
                .ignoresSafeArea()
        }
    }
}
