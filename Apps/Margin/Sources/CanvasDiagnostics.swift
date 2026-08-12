import Foundation

/// Temporary instrumentation for the canvas/store disagreement behind the undo defects.
///
/// **Records counts and revisions only — never ink, never text.** AGENTS §7 forbids user
/// content in logs, and a stroke count is the whole question here anyway: which of the canvas
/// and the store is ahead, and at which callback they diverge.
///
/// Written to the app container so a device session needs no tether; pull it with
/// `devicectl device copy from --domain-type appDataContainer`. Remove this file once the
/// canvas contract is settled — it is a diagnostic, not a feature.
enum CanvasDiagnostics {
    static let isEnabled = true

    private static let fileURL: URL? = {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("canvas-diagnostics.log")
    }()

    private static let started = Date()

    static func record(
        _ event: String,
        canvasStrokes: Int? = nil,
        storeStrokes: Int? = nil,
        pageRevision: Int? = nil,
        appliedRevision: Int? = nil,
        note: String = ""
    ) {
        guard isEnabled, let fileURL else { return }
        var line = String(format: "%8.3f %@", Date().timeIntervalSince(started), event)
        if let canvasStrokes { line += " canvas=\(canvasStrokes)" }
        if let storeStrokes { line += " store=\(storeStrokes)" }
        if let pageRevision { line += " rev=\(pageRevision)" }
        if let appliedRevision { line += " applied=\(appliedRevision)" }
        if !note.isEmpty { line += " \(note)" }
        line += "\n"

        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }
}
