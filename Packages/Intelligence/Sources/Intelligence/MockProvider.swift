import Foundation

/// A provider that answers from canned specs.
///
/// This is what CI runs the pipeline against. Every stage above it — placement,
/// synthesis, the request state machine, the Ask bar — can then be tested for latency,
/// cancellation and failure handling without a network, an API key, or a device.
public actor MockProvider: SpecProvider {
    /// How the mock behaves before it answers.
    public struct Behavior: Equatable, Sendable {
        public static let immediate = Behavior()

        /// Simulated round-trip time. The wait is cancellable, which is what lets callers
        /// prove the §5 requirement that a user writing again kills the in-flight request.
        public let latency: Duration
        /// When set, the mock fails this way instead of answering.
        public let failure: ProviderError?
        /// When true, the canned spec is returned unvalidated-looking — the mock still
        /// runs it through `SpecValidator`, so the caller sees a real validation error.
        public let corruptsSpec: Bool

        public init(latency: Duration = .zero, failure: ProviderError? = nil, corruptsSpec: Bool = false) {
            self.latency = latency
            self.failure = failure
            self.corruptsSpec = corruptsSpec
        }
    }

    public nonisolated let tier = ModelTier.mock

    private var fixtures: [String: Spec]
    private var behavior: Behavior
    private var requestKeys: [String] = []

    public init(fixtures: [String: Spec] = [:], behavior: Behavior = .immediate) {
        self.fixtures = fixtures
        self.behavior = behavior
    }

    /// Every fixture key requested so far, in order. Lets a test assert that a stage
    /// cancelled rather than re-issued, without reaching into the provider's internals.
    public var requestedKeys: [String] { requestKeys }

    public func register(_ spec: Spec, for key: String) {
        fixtures[key] = spec
    }

    public func setBehavior(_ behavior: Behavior) {
        self.behavior = behavior
    }

    public func spec(for request: SpecRequest) async throws -> ValidatedSpec {
        let key = request.cacheKey
        requestKeys.append(key)

        if behavior.latency > .zero {
            try await Task.sleep(for: behavior.latency)
        }
        if let failure = behavior.failure {
            throw failure
        }
        guard let spec = fixtures[key] else {
            throw ProviderError.unknownFixture(key)
        }
        return try SpecValidator.validate(behavior.corruptsSpec ? Self.corrupted(spec) : spec)
    }

    /// The canned failure mode from `AI_PIPELINE.md` §8: a well-formed response the
    /// validator must still refuse. Confidence is dropped below the floor.
    private static func corrupted(_ spec: Spec) -> Spec {
        Spec(
            version: spec.version,
            read: spec.read,
            readConfidence: 0.1,
            intent: spec.intent,
            blocks: spec.blocks,
            explanation: spec.explanation,
            warnings: spec.warnings
        )
    }
}
