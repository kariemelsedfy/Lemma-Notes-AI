#if os(iOS)
    import UIKit

    /// The UIKit document lifecycle adapter for a `.margin` package.
    ///
    /// Package serialization stays in `DocumentPackageStore`; this type supplies UIKit's
    /// coordinated autosave and conflict-state lifecycle around that framework-independent core.
    public final class MarginDocument: UIDocument {
        public private(set) var content: StoredDocument?
        public private(set) var hasUnresolvedConflict = false
        public private(set) var refreshState: DocumentRefreshState = .current

        private let store: DocumentPackageStore
        private var stateObserver: NSObjectProtocol?
        private var refreshStateMachine = DocumentRefreshStateMachine()

        public init(fileURL: URL, store: DocumentPackageStore = DocumentPackageStore()) {
            self.store = store
            super.init(fileURL: fileURL)
            stateObserver = NotificationCenter.default.addObserver(
                forName: UIDocument.stateChangedNotification,
                object: self,
                queue: .main
            ) { [weak self] _ in
                self?.refreshDocumentState()
            }
        }

        deinit {
            if let stateObserver {
                NotificationCenter.default.removeObserver(stateObserver)
            }
        }

        /// Replaces the in-memory document content and makes it eligible for UIKit autosave.
        public func replaceContent(with content: StoredDocument) {
            self.content = content
            updateChangeCount(.done)
        }

        public override func read(from url: URL) throws {
            content = try store.read(from: url)
            refreshDocumentState(reloadCompleted: true)
        }

        /// Receives file-presenter changes from coordinated external writers, including iCloud.
        public override func presentedItemDidChange() {
            super.presentedItemDidChange()
            applyRefreshEvent(.externalChange)
        }

        public override func contents(forType typeName: String) throws -> Any {
            FileWrapper(directoryWithFileWrappers: [:])
        }

        public override func writeContents(
            _ contents: Any,
            to url: URL,
            for saveOperation: UIDocument.SaveOperation,
            originalContentsURL: URL?
        ) throws {
            guard let content else {
                return
            }
            try store.write(content, to: url)
        }

        private func refreshDocumentState(reloadCompleted: Bool = false) {
            if documentState.contains(.inConflict) {
                hasUnresolvedConflict = true
                applyRefreshEvent(.conflictDetected)
                return
            }

            if hasUnresolvedConflict {
                hasUnresolvedConflict = false
                applyRefreshEvent(.conflictResolvedByUser)
            }
            if reloadCompleted {
                applyRefreshEvent(.reloadCompleted)
            }
        }

        private func applyRefreshEvent(_ event: DocumentRefreshEvent) {
            refreshStateMachine.apply(event)
            refreshState = refreshStateMachine.state
        }
    }
#endif
