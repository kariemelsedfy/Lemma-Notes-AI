import DesignSystem
import InkCore
import SwiftUI

/// How a notebook fills the screen: pages run edge to edge and scroll under the translucent bar, like Notability, and
/// the tool board floats over them wherever it is docked.
extension VirtualizedPageStack {
    /// Breathing room kept below the bar when a notebook opens, so the first page starts clear of its buttons.
    private static var barClearance: CGFloat { 6 }
    /// Room after the last page, so it can be scrolled up clear of a bottom-docked board.
    private static var endClearance: CGFloat { 150 }

    var pagesScrollView: some View {
        let fit = PageFit.scale(viewportWidth: viewportWidth, pageWidth: pageSize.width)
        return ScrollView {
            // A flexible, empty base gives the scroll content the screen's width and the scaled height; the column
            // is drawn over it. Sizing the scroll content by the 768-point column instead made the whole notebook
            // 768 points wide, wider than an iPad mini's screen, and pushed the page and the board off its edges.
            Rectangle()
                .fill(.clear)
                .frame(height: pageLayout.totalHeight * fit)
                .overlay(alignment: .top) {
                    pageColumn
                        .frame(width: pageSize.width)
                        .scaleEffect(fit, anchor: .top)
                }
        }
        .contentMargins(.top, topInset + Self.barClearance, for: .scrollContent)
        .contentMargins(.bottom, Self.endClearance, for: .scrollContent)
        .ignoresSafeArea(.container, edges: .top)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            viewportWidth = $0
        }
        // A drag that starts on the answer's outline moves the answer, not the page.
        .scrollDisabled(ghostDragging || editDragging)
        .scrollPosition(id: $visiblePageID)
        // No snapping: the notebook stays wherever it is left, so a page seam can sit mid-screen.
        .scrollIndicators(.hidden)
    }

    private var pageColumn: some View {
        LazyVStack(spacing: PageStackLayout.spacing) {
            ForEach(pageIDs, id: \.self) { pageID in
                pageView(for: pageID)
                    .frame(
                        width: pageSizes[pageID]?.width ?? pageSize.width,
                        height: pageSizes[pageID]?.height ?? pageSize.height
                    )
                    .id(pageID)
            }
        }
        .frame(maxWidth: .infinity)
        // The pending answer floats over the whole column so it can be dragged across a page boundary.
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                ghostOverlay
                editOverlay
            }
        }
        .scrollTargetLayout()
    }

    /// The Ask bar, the lasso prompt and their kin: what sits just above the board (or at the foot of the screen
    /// when the board is elsewhere).
    var askCompanion: some View {
        VStack(spacing: 8) {
            if askModel.phase != .hidden {
                AskBar(
                    phase: askModel.phase,
                    explanation: askModel.explanation,
                    failureOverride: askModel.failureMessage,
                    failureDetail: askModel.failureDetail,
                    onVerb: { ask($0) },
                    onCancel: { cancelAsk() },
                    onAccept: { acceptSuggestion() },
                    onReject: { rejectSuggestion() },
                    onRetry: { retryAsk() },
                    onDismiss: { askModel.dismissFailure() },
                    onEditReading: plotEditAction,
                    needsSubscription: askModel.needsSubscription,
                    onSeePremium: premium.offersUpgrade ? { premium.showPaywall() } : nil
                )
            }
            if askPath.isArmed {
                LassoHintBar(hint: askPath.stage.hintKey, onCancel: cancelSelection)
            }
            lassoEditHint
        }
    }
}
