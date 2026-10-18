import Foundation
import Intelligence

/// Premium plot reading: the model looks at the handwriting and says which function it is, and the app draws it.
///
/// On-device handwriting recognition is poor at math (`cos` comes back as `(US`, a raised 3 as `x13`), so for an
/// entitled install the image goes to the hosted model, which only **reads** the function. Drawing stays local
/// (`HandPlotRenderer`), so nothing about the curve itself is requested from the model and plotting a typed formula
/// costs nothing. Any hosted failure, a decline, or a reply the local parser cannot evaluate falls back to reading
/// the function on the device, so a plot never fails just because the network or the model did.
struct HostedPlotSpecProvider: SpecProvider {
    let hosted: any SpecProvider
    let local: any SpecProvider
    /// Whether this install may use the hosted model right now (entitlement, valid address, token).
    let isReady: @Sendable () -> Bool

    var tier: ModelTier { isReady() ? hosted.tier : local.tier }

    func spec(for request: SpecRequest) async throws -> ValidatedSpec {
        // A formula the writer typed is exact; there is nothing for a model to read.
        guard isReady(), request.selectedAreaReading?.isCorrection != true else {
            return try await local.spec(for: request)
        }
        do {
            let reply = try await hosted.spec(for: request)
            if let plot = Self.checked(reply) { return plot }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Offline, over budget, refused, undecodable: read it on the device instead.
        }
        try Task.checkCancellation()
        return try await local.spec(for: request)
    }

    /// The reply as a plot the device can evaluate, or nil (so the on-device reading is used).
    static func checked(_ reply: ValidatedSpec) -> ValidatedSpec? {
        guard !reply.isDecline, reply.intent == .plot,
            case .plot(let plot)? = reply.blocks.first?.content
        else { return nil }
        var functions: [SpecPlotFunction] = []
        for function in plot.functions {
            guard let parsed = PlotExpression(function.expression) else { return nil }
            functions.append(SpecPlotFunction(expression: parsed.text, domain: function.domain, style: function.style))
        }
        let drawn = SpecPlot(
            functions: functions, xRange: plot.xRange, yRange: plot.yRange, xLabel: plot.xLabel, yLabel: plot.yLabel,
            gridStyle: plot.gridStyle)
        let spec = Spec(
            read: reply.read,
            readConfidence: reply.readConfidence,
            intent: .plot,
            blocks: [SpecBlock(placement: .belowSelection, content: .plot(drawn))],
            explanation: String(
                format: NSLocalizedString("ask.plot.reading", comment: ""),
                functions.map(\.expression).joined(separator: ", ")))
        return try? SpecValidator.validate(spec)
    }
}
