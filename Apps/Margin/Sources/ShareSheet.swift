import SwiftUI
import UIKit

/// Bridges the platform activity controller so exported files use every configured share destination.
struct ShareSheet: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
