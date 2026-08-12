import Foundation

/// Which model answered a request.
///
/// Mirrors `Analytics.AIModelTier`, deliberately duplicated rather than shared: the
/// dependency rule (`ARCHITECTURE.md` §2) forbids `Intelligence` from importing
/// `Analytics`, and the app maps between them at the one place it reports an event.
public enum ModelTier: String, Sendable, Equatable, CaseIterable {
    case onDevice
    case privateCloudCompute
    case frontierCloud
    /// Never routed to in a shipping build; exists so CI can exercise the pipeline.
    case mock
}

/// One Ask, ready to send.
public struct SpecRequest: Equatable, Sendable {
    public let context: SelectionContext
    /// The locally predicted verb (`AI_PIPELINE.md` §2), sent as a hint only.
    public let intent: SpecIntent?
    /// Ephemeral crop and neighborhood pixels. Providers may transmit these for the
    /// current request but must not log or retain them.
    public let rasterizedSelection: RasterizedSelection?
    /// Vision's on-device best effort for the selected crop.
    public let selectedAreaReading: SelectionReading?

    public init(
        context: SelectionContext,
        intent: SpecIntent? = nil,
        rasterizedSelection: RasterizedSelection? = nil,
        selectedAreaReading: SelectionReading? = nil
    ) {
        self.context = context
        self.intent = intent
        self.rasterizedSelection = rasterizedSelection
        self.selectedAreaReading = selectedAreaReading
    }

    /// A stable digest of everything that can change the answer.
    ///
    /// Used as the response cache key (`AI_PIPELINE.md` §7) and as the mock's fixture
    /// key. Deliberately *not* built from `Hashable`: Swift seeds `Hasher` per process,
    /// so a `hashValue`-derived key would miss the cache on every launch.
    public var cacheKey: String {
        var digest = FNV1a()
        digest.combine(intent?.rawValue ?? "-")
        digest.combine(context.selectionBounds)
        digest.combine(context.crop.bounds)
        digest.combine(context.crop.scale)
        for stroke in context.strokes {
            for point in stroke.points {
                digest.combine(point.location)
            }
            digest.combine("|")
        }
        if let rasterizedSelection {
            digest.combine(rasterizedSelection.crop.data)
            digest.combine(rasterizedSelection.neighborhood.data)
        }
        return digest.value
    }
}

/// Why a provider could not answer.
public enum ProviderError: Error, Equatable, Sendable {
    /// The request never reached a model.
    case transport
    /// The model did not answer inside the deadline (`AI_PIPELINE.md` §8).
    case timeout
    /// The mock was asked for a fixture it does not have.
    case unknownFixture(String)
    /// The request would have sent the user's work to a third party without their agreement
    /// (App Store 5.1.2(i), invariant 8). Asserted in the provider layer so a new call site
    /// cannot bypass it — see `ConsentGatedProvider`.
    case thirdPartyConsentRequired
}

/// The app's boundary to any model.
///
/// Providers return a **validated** spec. Validation therefore cannot be skipped by
/// adding a new provider, which is the whole point of the `ValidatedSpec` type.
public protocol SpecProvider: Sendable {
    var tier: ModelTier { get }

    /// Answers one ephemeral request. Crop pixels and transcript must not be logged or
    /// retained after this call finishes (`AGENTS.md` §7).
    func spec(for request: SpecRequest) async throws -> ValidatedSpec
}

/// A tiny, deterministic 64-bit string digest.
private struct FNV1a {
    private var state: UInt64 = 0xCBF2_9CE4_8422_2325

    var value: String { String(state, radix: 36) }

    mutating func combine(_ text: String) {
        for byte in text.utf8 {
            state ^= UInt64(byte)
            state = state &* 0x0000_0100_0000_01B3
        }
    }

    mutating func combine(_ number: CGFloat) {
        // Quantized to a hundredth of a point: sub-pixel jitter must not miss the cache.
        combine(String(Int((number * 100).rounded())))
    }

    mutating func combine(_ point: CGPoint) {
        combine(point.x)
        combine(point.y)
    }

    mutating func combine(_ rect: CGRect) {
        combine(rect.origin)
        combine(rect.width)
        combine(rect.height)
    }

    mutating func combine(_ data: Data) {
        for byte in data {
            state ^= UInt64(byte)
            state = state &* 0x0000_0100_0000_01B3
        }
    }
}
