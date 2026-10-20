import SwiftUI
import UIKit

/// A navigation bar that lets touches fall through the empty parts of it to what is behind.
///
/// The page runs under the bar and the tool board can sit on the bar's level, but a bar swallows every touch inside
/// its frame, buttons or not, which would leave the top of the board dead. This answers only for its own buttons.
/// It adds no stored properties, which is what makes switching an existing bar to it safe.
final class PassThroughNavigationBar: UINavigationBar {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/// Switches the enclosing navigation controller's bar to `PassThroughNavigationBar` once the screen has appeared.
struct NavigationBarPassThrough: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let bar = navigationController?.navigationBar, !(bar is PassThroughNavigationBar) else { return }
            object_setClass(bar, PassThroughNavigationBar.self)
        }
    }
}
