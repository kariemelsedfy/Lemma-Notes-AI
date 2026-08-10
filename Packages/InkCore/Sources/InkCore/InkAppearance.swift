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
    /// **Measured** (iOS 26 simulator, black `.pen`, peak alpha out of 255). The cutoff below
    /// 2.0pt does not move with render scale — it is a property of the ink, not of
    /// rasterisation — but everything above it does, and the page draws at device scale:
    ///
    ///     width  2.0  2.1  2.2  2.3  2.4  2.5  2.6
    ///     1×      40   55   72   90  108  128  147
    ///     2×      40   72  108  147  183  215  239
    ///     3×      40   90  146  200  240  255  255
    ///
    /// 2.6 is chosen against **2×**, the worst case a real page hits: solid at 3×, 239/255 at
    /// 2×, which includes export. Measuring at 1× instead is what first put this at 3.4 and
    /// made every answer bolder than it needed to be — the harness scale was not the page's.
    ///
    /// `.pencil` ink draws at any width, but it is textured and the user's own pen is
    /// `.pen`; generated ink that does not match the pen beside it is its own problem.
    public static let minimumStrokeWidth: CGFloat = 2.6

    /// **`PKStrokePoint.size` is not the width PencilKit draws.** Measured vertical extent of
    /// a horizontal `.pen` stroke, in points:
    ///
    ///     size   2.4  2.6  2.8  3.0  3.2  3.4  4.0  4.5  5.0  6.0  8.0  12.0
    ///     drawn  1.0  1.0  1.5  2.0  2.5  3.0  4.0  5.0  6.0  8.0  12.0 20.0
    ///
    /// Every one of those fits `drawn = 2 × size − 4`, and the cutoff falls exactly where
    /// that reaches zero, at 2.0.
    ///
    /// Anything reasoning about ink *geometry* — hatch spacing, how far to inset a fill, how
    /// wide a stem ends up — has to use the drawn width. Using `size` instead is why the
    /// first attempt at this laid 1pt-wide hatch lines 2.08pt apart and drew a `4` as a stack
    /// of disconnected bars (M2-13B).
    public static func drawnWidth(forSize size: CGFloat) -> CGFloat {
        max(0, 2 * size - 4)
    }

    /// The `PKStrokePoint.size` that draws `width` points wide. The inverse of the above.
    public static func size(forDrawnWidth width: CGFloat) -> CGFloat {
        max(minimumStrokeWidth, width / 2 + 2)
    }

    /// The thinnest line worth drawing: below this the pen fades rather than thins.
    public static let minimumDrawnWidth: CGFloat = 1.0
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
