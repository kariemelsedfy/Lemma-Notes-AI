import Foundation

/// The first persisted schema version for a `.margin` document package.
public enum DocumentSchema {
    public static let currentVersion = 1
}

/// The top-level metadata stored in a document package's `manifest.json`.
public struct MarginManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public var modifiedAt: Date
    public var pageOrder: [UUID]
    public var settings: DocumentSettings

    public init(
        schemaVersion: Int = DocumentSchema.currentVersion,
        id: UUID,
        title: String,
        createdAt: Date,
        modifiedAt: Date,
        pageOrder: [UUID],
        settings: DocumentSettings
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.pageOrder = pageOrder
        self.settings = settings
    }
}

/// Settings that apply across all pages unless a page overrides them.
public struct DocumentSettings: Codable, Equatable, Sendable {
    public var defaultPaper: PaperStyle

    public init(defaultPaper: PaperStyle) {
        self.defaultPaper = defaultPaper
    }
}

/// The supported paper backgrounds for a page.
public enum PaperStyle: String, Codable, Equatable, Sendable {
    case blank
    case ruled
    case grid5Millimeters = "grid-5mm"
    case dotted
}

/// The page dimensions expressed in document points.
public struct PageSize: Codable, Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// A rectangular semantic element bound, expressed in document coordinates.
public struct PageBounds: Codable, Equatable, Sendable {
    public let horizontal: Double
    public let vertical: Double
    public let width: Double
    public let height: Double

    public init(horizontal: Double, vertical: Double, width: Double, height: Double) {
        self.horizontal = horizontal
        self.vertical = vertical
        self.width = width
        self.height = height
    }

    private enum CodingKeys: String, CodingKey {
        case horizontal = "x"
        case vertical = "y"
        case width
        case height
    }
}

/// The page-level metadata stored alongside the opaque PencilKit drawing blob.
public struct PageMetadata: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let pageID: UUID
    public var size: PageSize
    public var paper: PaperStyle
    public var elements: [PageElement]

    public init(
        schemaVersion: Int = DocumentSchema.currentVersion,
        pageID: UUID,
        size: PageSize,
        paper: PaperStyle,
        elements: [PageElement]
    ) {
        self.schemaVersion = schemaVersion
        self.pageID = pageID
        self.size = size
        self.paper = paper
        self.elements = elements
    }

    /// Repairs semantic stroke references after the drawing's ordered strokes change.
    ///
    /// A fingerprint is the durable proof that a reference still belongs to its original
    /// stroke; stale or ambiguous references are removed rather than attributed incorrectly.
    public func repairingStrokeIndices(using strokes: [StoredStroke]) -> PageMetadata {
        let indicesByFingerprint = Dictionary(grouping: strokes.indices, by: { StrokeFingerprint(stroke: strokes[$0]) })
        var repaired = self
        repaired.elements = elements.map { element in
            var repairedElement = element
            repairedElement.strokeReferences = element.strokeReferences.compactMap { reference in
                guard let matches = indicesByFingerprint[reference.fingerprint], matches.count == 1,
                    let index = matches.first
                else {
                    return nil
                }
                return StrokeReference(index: index, fingerprint: reference.fingerprint)
            }
            return repairedElement
        }
        return repaired
    }
}

/// A semantic element that has a permanent relationship to one or more ink strokes.
public struct PageElement: Codable, Equatable, Sendable {
    public let id: String
    public let kind: PageElementKind
    public var bounds: PageBounds
    public var strokeReferences: [StrokeReference]
    public var requestID: String?
    public var acceptedAt: Date?

    public init(
        id: String,
        kind: PageElementKind,
        bounds: PageBounds,
        strokeReferences: [StrokeReference],
        requestID: String? = nil,
        acceptedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.bounds = bounds
        self.strokeReferences = strokeReferences
        self.requestID = requestID
        self.acceptedAt = acceptedAt
    }
}

/// Categorises page elements without tying the persisted model to a rendering framework.
public enum PageElementKind: String, Codable, Equatable, Sendable {
    case handwritten
    case generated
    case text
    case image
    case shape
}

/// An indexed stroke reference paired with a durable fingerprint for repair on load.
public struct StrokeReference: Codable, Equatable, Sendable {
    public let index: Int
    public let fingerprint: StrokeFingerprint

    public init(index: Int, fingerprint: StrokeFingerprint) {
        self.index = index
        self.fingerprint = fingerprint
    }
}

/// Minimal stroke data used to calculate persisted, framework-independent fingerprints.
public struct StoredStroke: Equatable, Sendable {
    public let points: [StoredStrokePoint]

    public init(points: [StoredStrokePoint]) {
        self.points = points
    }
}

/// A point used only for deterministic stroke identity, not for rendering.
public struct StoredStrokePoint: Equatable, Sendable {
    public let horizontal: Double
    public let vertical: Double

    public init(horizontal: Double, vertical: Double) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
}

/// A deterministic stroke signature based on its first and last points and point count.
public struct StrokeFingerprint: Codable, Equatable, Hashable, Sendable {
    public let value: String

    public init(stroke: StoredStroke) {
        var hasher = FNV1a64()
        hasher.combine(UInt64(stroke.points.count))
        if let first = stroke.points.first {
            hasher.combine(first.horizontal.bitPattern)
            hasher.combine(first.vertical.bitPattern)
        }
        if let last = stroke.points.last {
            hasher.combine(last.horizontal.bitPattern)
            hasher.combine(last.vertical.bitPattern)
        }
        value = String(hasher.value, radix: 16)
    }
}

private struct FNV1a64 {
    private static let offsetBasis: UInt64 = 14_695_981_039_346_656_037
    private static let prime: UInt64 = 1_099_511_628_211

    private(set) var value = offsetBasis

    mutating func combine(_ number: UInt64) {
        var littleEndian = number.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            for byte in bytes {
                value ^= UInt64(byte)
                value &*= Self.prime
            }
        }
    }
}

/// The serializable contents of a `.margin` package, excluding UIKit document lifecycle.
public struct StoredDocument: Equatable, Sendable {
    public let manifest: MarginManifest
    public let pages: [StoredPage]
    public let assets: [DocumentAsset]
    public let glyphBankData: Data?
    public let thumbnails: [UUID: Data]

    public init(
        manifest: MarginManifest,
        pages: [StoredPage],
        assets: [DocumentAsset] = [],
        glyphBankData: Data? = nil,
        thumbnails: [UUID: Data] = [:]
    ) {
        self.manifest = manifest
        self.pages = pages
        self.assets = assets
        self.glyphBankData = glyphBankData
        self.thumbnails = thumbnails
    }
}

/// A page's metadata paired with its opaque PencilKit drawing representation.
public struct StoredPage: Equatable, Sendable {
    public let metadata: PageMetadata
    public let inkData: Data

    public init(metadata: PageMetadata, inkData: Data) {
        self.metadata = metadata
        self.inkData = inkData
    }
}

/// An imported asset that is stored in the package's `assets` directory.
public struct DocumentAsset: Equatable, Sendable {
    public let id: UUID
    public let fileExtension: String
    public let data: Data

    public init(id: UUID, fileExtension: String, data: Data) {
        self.id = id
        self.fileExtension = fileExtension
        self.data = data
    }
}

/// Errors emitted while reading or writing a package whose layout is owned by the app.
public enum DocumentPackageError: Error, Equatable, Sendable {
    case invalidAssetExtension(String)
    case missingPageMetadata(UUID)
    case missingPageInk(UUID)
    case malformedAssetFilename(String)
}
