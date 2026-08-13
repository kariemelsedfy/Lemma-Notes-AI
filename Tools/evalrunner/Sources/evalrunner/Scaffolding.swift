import CoreGraphics
import Foundation
import InkCore
import Intelligence

/// A stand-in model that answers from the local reading it was handed.
///
/// **It is not a quality baseline and its numbers mean nothing about any model.** It exists so
/// the harness itself can be exercised end to end — cases load, requests are built, specs
/// validate, metrics compute, JSON is written — before a real provider exists to plug in.
/// It reads perfectly by construction, so a read accuracy below 100% here means the *harness*
/// is broken, which is exactly the signal wanted from a run against a stub.
struct CannedEvalProvider: SpecProvider {
    let tier = ModelTier.mock

    func spec(for request: SpecRequest) async throws -> ValidatedSpec {
        let transcript = request.selectedAreaReading?.transcript ?? ""

        // The 5% of the golden set that is deliberate scrawl: a model that answers it anyway is
        // the failure §9's decline rate exists to catch, so the stub must be able to decline.
        guard !Self.isGarbage(transcript) else {
            // **A decline is "no blocks", not "low confidence".** `AI_PIPELINE.md` §10 tells the
            // model to signal an unreadable selection by setting `readConfidence` low *and*
            // returning no blocks — but `SpecValidator` fails closed below 0.6, so that exact
            // combination throws instead of arriving as a decline the UI can show. Filed as
            // M4-11; until it is resolved, the only representable decline is a confident one,
            // which is why this reads oddly.
            return try SpecValidator.validate(
                Spec(read: transcript, readConfidence: 0.95, intent: request.intent ?? .answer, blocks: [])
            )
        }

        return try SpecValidator.validate(
            Spec(
                read: transcript,
                readConfidence: 0.95,
                intent: request.intent ?? .answer,
                blocks: [
                    SpecBlock(
                        placement: .atAnchor,
                        content: .inline(SpecRun(kind: .text, value: Self.answer(for: transcript)))
                    )
                ]
            )
        )
    }

    /// Garbage is labelled in the case file; this only has to agree with the label, and it does
    /// so by looking for the same thing a person would — no readable words.
    private static func isGarbage(_ transcript: String) -> Bool {
        let letters = transcript.filter { $0.isLetter || $0.isNumber }
        return letters.count < 2
    }

    /// Deliberately trivial. A stub that tried to be clever would produce numbers someone
    /// eventually quotes.
    private static func answer(for transcript: String) -> String {
        "see the working above"
    }
}

/// A synthetic selection, so the runner has a context to build requests from.
///
/// The golden set will carry real crops and real strokes once a human captures it (M4-06B);
/// until then every case shares this one, which is fine because nothing in the metrics depends
/// on the geometry — read, intent and decline all come from the reading.
enum EvalContext {
    static func make() throws -> SelectionContext {
        let strokes = (0..<3).map { index -> InkStroke in
            let left = CGFloat(100 + index * 40)
            return InkStroke(points: [
                InkPoint(location: CGPoint(x: left, y: 100), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
                InkPoint(
                    location: CGPoint(x: left + 20, y: 160), timeOffset: 0.1, force: 0.5, altitude: 1, azimuth: 0),
            ])
        }
        guard
            let context = SelectionContextBuilder.build(
                strokes: strokes,
                loop: [
                    CGPoint(x: 80, y: 80), CGPoint(x: 420, y: 80),
                    CGPoint(x: 420, y: 210), CGPoint(x: 80, y: 210),
                ],
                pageSize: CGSize(width: 1_668, height: 2_388)
            )
        else {
            throw EvalCommandError.noCases("could not build a selection context")
        }
        return context
    }
}
