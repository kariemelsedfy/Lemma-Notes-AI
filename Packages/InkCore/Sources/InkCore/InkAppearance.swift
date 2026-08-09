import Foundation
import PencilKit

#if os(iOS)
    import UIKit
#endif

/// What the on-page renderer can actually draw.
///
/// Ink is rasterised by two different things in this project, and they do not agree.
/// `InkRasterizer` (the OCR harness) uses `CGContext.setLineWidth` and draws any width you
/// ask for. The page uses PencilKit, which will not draw a hairline: it fades a `.pen` out
/// below roughly 3.4pt and renders *nothing at all* below 1.5.
///
/// Anything that picks a stroke width has to respect this, or it will look correct in every
/// measurement and be invisible on the page — which is exactly what shipped in M3-00B and
/// was found by a user, not by the suite (M2-13).
public enum InkRenderingLimits {
    /// The narrowest stroke the page renderer draws at full strength.
    ///
    /// **Measured** (iOS 26 simulator, black `.pen`, peak alpha out of 255):
    ///
    ///     1.4pt → 0    1.8pt → 16    2.2pt → 72    2.6pt → 147   3.0pt → 215   3.4pt → 253
    ///     1.6pt → 2    2.0pt → 40    2.4pt → 108   2.8pt → 183   3.2pt → 239   3.6pt → 255
    ///
    /// `.pencil` ink draws at any width, but it is textured and the user's own pen is
    /// `.pen`; generated ink that does not match the pen beside it is its own problem.
    public static let minimumStrokeWidth: CGFloat = 3.4
}

#if os(iOS)
    /// The appearance ink is drawn in, which is not the appearance the app is in.
    ///
    /// PencilKit renders a *stored* colour through the *current* appearance: in a dark trait
    /// environment it lightens dark ink so it stays visible on a dark background. That is the
    /// right default for an app whose canvas follows the system, and the wrong one for Margin,
    /// whose page is paper — `MarginColor.paper` is deliberately fixed light in both
    /// appearances. Inverted there, black ink becomes white ink on a white page.
    ///
    /// Pinning the stored colour to a non-dynamic black is a separate fix and does not help:
    /// that controls what gets *saved*, this controls what gets *drawn*. Every path that shows
    /// or rasterises a `PKDrawing` needs to opt out, so they all go through here.
    public enum InkAppearance {
        /// Paper is light whatever the system is doing.
        public static let paper = UITraitCollection(userInterfaceStyle: .light)

        /// Runs `body` with `paper` as the current trait collection.
        public static func onPaper<T>(_ body: () -> T) -> T {
            var result: T?
            // Synchronous, so `result` is always assigned by the time this returns.
            paper.performAsCurrent { result = body() }
            guard let result else {
                preconditionFailure("performAsCurrent did not run its closure")
            }
            return result
        }

        /// Stops a view from inverting the ink it draws.
        ///
        /// Applies to subviews too, which is intended: everything inside a canvas — selection
        /// outlines included — is sitting on the page.
        public static func applyPaperAppearance(to view: UIView) {
            view.overrideUserInterfaceStyle = .light
        }
    }
#endif
