import XCTest

@testable import Margin

final class MarginTests: XCTestCase {
    func testAppModuleLoads() {
        XCTAssertNotNil(MarginApp.self)
    }

    func testRuledPaperLinePositionsRespectInsetsAndSpacing() {
        let positions = PaperLineLayout.positions(
            from: 0,
            to: 200,
            inset: 20,
            spacing: 40
        )

        XCTAssertEqual(positions, [20, 60, 100, 140, 180])
    }

    func testPaperLineLayoutRejectsNonPositiveSpacing() {
        let positions = PaperLineLayout.positions(
            from: 0,
            to: 100,
            inset: 10,
            spacing: 0
        )

        XCTAssertTrue(positions.isEmpty)
    }

    func testLiveWindowContainsOnlyTheVisiblePageAndImmediateNeighbors() {
        let pageIDs = PageLiveWindow.pageIndices(around: 5, pageCount: 12)

        XCTAssertEqual(pageIDs, [4, 5, 6])
    }

    func testLiveWindowClampsToDocumentBounds() {
        XCTAssertEqual(PageLiveWindow.pageIndices(around: -4, pageCount: 3), [0, 1])
        XCTAssertEqual(PageLiveWindow.pageIndices(around: 9, pageCount: 3), [1, 2])
    }

    func testPerformanceFixtureVisitsEveryPageInAOneHundredPageDocument() {
        XCTAssertEqual(PagePerformanceFixture.pageTurnSequence.count, 100)
        XCTAssertEqual(PagePerformanceFixture.pageTurnSequence, Array(0..<100))
    }

    func testPerformanceFixtureNeverKeepsMoreThanThreePagesLiveDuringPageTurns() {
        for pageID in PagePerformanceFixture.pageTurnSequence {
            let livePages = PageLiveWindow.pageIndices(
                around: pageID,
                pageCount: PagePerformanceFixture.pageCount
            )

            XCTAssertLessThanOrEqual(livePages.count, 3)
            XCTAssertTrue(livePages.contains(pageID))
        }
    }

    func testCanvasToolsHaveUniqueSymbols() {
        XCTAssertEqual(Set(CanvasTool.allCases.map(\.symbolName)).count, CanvasTool.allCases.count)
    }

    func testAskPathArmsTheSelectionLassoAndCountsInvocations() {
        var path = AskPathState()

        path.invoke()
        path.invoke()

        XCTAssertTrue(path.isArmed)
        XCTAssertEqual(path.invocationCount, 2)
    }

    func testAskPathDisarmsAfterASelectionCompletes() {
        var path = AskPathState()
        path.invoke()

        path.selectionDidComplete()

        XCTAssertFalse(path.isArmed)
    }

    func testPageSelectionComputesBoundsForItsLoop() {
        let selection = PageSelection(
            pageID: UUID(),
            loop: [
                CGPoint(x: 10, y: 20),
                CGPoint(x: 60, y: 30),
                CGPoint(x: 40, y: 90),
            ]
        )

        XCTAssertEqual(selection.bounds, CGRect(x: 10, y: 20, width: 50, height: 70))
    }

    @MainActor
    func testSelectionStorePublishesAndClearsPageSelection() {
        let store = PageSelectionStore()
        let selection = PageSelection(pageID: UUID(), loop: [CGPoint(x: 4, y: 8)])

        store.select(selection)
        XCTAssertEqual(store.selection, selection)

        store.clear()
        XCTAssertNil(store.selection)
    }

    @MainActor
    func testNotebookLibraryCreatesStableNotebookSummary() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let library = NotebookLibrary(rootURL: rootURL)
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        let notebook = try XCTUnwrap(library.create(title: "Calculus", now: now))

        XCTAssertEqual(library.notebooks, [notebook])
        XCTAssertEqual(notebook.title, "Calculus")
        XCTAssertEqual(notebook.createdAt, now)
        XCTAssertEqual(notebook.modifiedAt, now)
        XCTAssertEqual(notebook.pageCount, 1)
    }

    @MainActor
    func testNotebookLibraryRenamesAndDeletesNotebook() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let library = NotebookLibrary(rootURL: rootURL)
        let notebook = try XCTUnwrap(library.create(title: "Draft", now: .distantPast))
        let renamedAt = Date(timeIntervalSinceReferenceDate: 2_000)

        library.rename(id: notebook.id, to: "Linear Algebra", now: renamedAt)

        XCTAssertEqual(library.notebooks.first?.title, "Linear Algebra")
        XCTAssertEqual(library.notebooks.first?.modifiedAt, renamedAt)

        library.delete(id: notebook.id)

        XCTAssertTrue(library.notebooks.isEmpty)
    }
}
