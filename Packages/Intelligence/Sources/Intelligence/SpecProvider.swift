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

    /// A name safe to log. `unknownFixture` carries a cache key derived from page geometry,
    /// so the associated value stays out of logs and metrics files (`AGENTS.md` §7).
    public var name: String {
        switch self {
        case .transport: "transport"
        case .timeout: "timeout"
        case .unknownFixture: "unknownFixture"
        case .thirdPartyConsentRequired: "thirdPartyConsentRequired"
        }
    }
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

public enum ProxyTransportFailure: Error, Equatable, Sendable, CaseIterable {
    case offline, timeout, refused, unauthorized, overBudget
}

public enum ProxyProviderFailure: Error, Equatable, Sendable {
    case invalidRequest, invalidResponse, offline, refused, unauthorized, budgetExceeded
}

public struct ProxyClientRequest: Encodable, Sendable {
    public let requestID: UUID
    public let cropPNG: Data
    public let neighborhoodPNG: Data
    public let transcript: String
    public let intent: SpecIntent
    public let maxOutputTokens: Int
}

public protocol ProxyClientTransport: Sendable {
    func response(to request: ProxyClientRequest) async throws -> Data
}

public struct ProxySpecProvider: SpecProvider {
    public let tier = ModelTier.frontierCloud
    private let transport: any ProxyClientTransport

    private init(transport: any ProxyClientTransport) {
        self.transport = transport
    }

    public static func consentGated(
        transport: any ProxyClientTransport,
        isConsentGranted: @escaping @Sendable () -> Bool
    ) -> ConsentGatedProvider {
        Self(transport: transport).gated(by: isConsentGranted)
    }

    public func spec(for request: SpecRequest) async throws -> ValidatedSpec {
        try Task.checkCancellation()
        let wire = try Self.wireRequest(for: request)
        let response = try await send(wire)
        try Task.checkCancellation()
        return try Self.validate(response, intent: wire.intent)
    }

    private static func wireRequest(for request: SpecRequest) throws -> ProxyClientRequest {
        guard let raster = request.rasterizedSelection, let intent = request.intent else {
            throw ProxyProviderFailure.invalidRequest
        }
        let crop = raster.crop
        let neighborhood = raster.neighborhood
        let cropPixels = Double(crop.size.width * crop.size.height * crop.scale * crop.scale)
        let nearbyPixels = Double(
            neighborhood.size.width * neighborhood.size.height * neighborhood.scale * neighborhood.scale
        )
        let transcript = request.selectedAreaReading?.transcript ?? ""
        guard !crop.data.isEmpty, crop.data.count <= 1_000_000,
            !neighborhood.data.isEmpty, neighborhood.data.count <= 500_000,
            cropPixels.isFinite, (1...1_500_000).contains(cropPixels),
            nearbyPixels.isFinite, (1...500_000).contains(nearbyPixels),
            transcript.utf8.count <= 256
        else { throw ProxyProviderFailure.invalidRequest }
        return ProxyClientRequest(
            requestID: UUID(), cropPNG: crop.data, neighborhoodPNG: neighborhood.data,
            transcript: transcript, intent: intent, maxOutputTokens: 256
        )
    }

    private func send(_ wire: ProxyClientRequest) async throws -> Data {
        do {
            return try await transport.response(to: wire)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ProxyTransportFailure {
            switch error {
            case .timeout: throw ProviderError.timeout
            case .offline: throw ProxyProviderFailure.offline
            case .refused: throw ProxyProviderFailure.refused
            case .unauthorized: throw ProxyProviderFailure.unauthorized
            case .overBudget: throw ProxyProviderFailure.budgetExceeded
            }
        } catch {
            throw ProviderError.transport
        }
    }

    private static func validate(_ response: Data, intent: SpecIntent) throws -> ValidatedSpec {
        guard response.count <= 65_536 else { throw ProxyProviderFailure.invalidResponse }
        let spec: ValidatedSpec
        do {
            spec = try SpecValidator.validate(response)
        } catch {
            throw ProxyProviderFailure.invalidResponse
        }
        guard spec.intent == intent else { throw ProxyProviderFailure.invalidResponse }
        return spec
    }
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
