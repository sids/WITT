import Foundation

public enum PhotoCaptureSource: String, Hashable, Sendable {
    case camera
    case photoLibrary = "photo-library"
}

public struct CapturedPhoto: Hashable, Sendable {
    public let data: Data
    public let contentType: String
    public let source: PhotoCaptureSource
    public let capturedAt: Date?

    nonisolated public init(
        data: Data,
        contentType: String,
        source: PhotoCaptureSource,
        capturedAt: Date? = nil
    ) {
        self.data = data
        self.contentType = contentType
        self.source = source
        self.capturedAt = capturedAt
    }
}

public struct PhotoDimensions: Hashable, Sendable {
    public let width: Int
    public let height: Int

    nonisolated public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct NormalizedPhoto: Hashable, Sendable {
    public let jpegData: Data
    public let thumbnailJPEGData: Data
    public let dimensions: PhotoDimensions
    public let contentType: String
    public let byteSize: Int
    public let source: PhotoCaptureSource
    public let capturedAt: Date?

    nonisolated public init(
        jpegData: Data,
        thumbnailJPEGData: Data,
        dimensions: PhotoDimensions,
        contentType: String = "image/jpeg",
        source: PhotoCaptureSource,
        capturedAt: Date? = nil
    ) {
        self.jpegData = jpegData
        self.thumbnailJPEGData = thumbnailJPEGData
        self.dimensions = dimensions
        self.contentType = contentType
        self.byteSize = jpegData.count
        self.source = source
        self.capturedAt = capturedAt
    }

    public var photoInput: PhotoInput {
        PhotoInput(
            data: jpegData,
            contentType: contentType,
            dimensions: .init(width: dimensions.width, height: dimensions.height)
        )
    }

    nonisolated public var persistenceMetadata: PhotoAssetMetadata {
        PhotoAssetMetadata(
            contentType: contentType,
            pixelWidth: dimensions.width,
            pixelHeight: dimensions.height,
            byteSize: byteSize,
            kind: "original",
            source: source.rawValue,
            capturedAt: capturedAt
        )
    }
}

public struct PhotoAssetMetadata: Hashable, Sendable {
    public let contentType: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let byteSize: Int
    public let kind: String
    public let source: String
    public let capturedAt: Date?

    nonisolated public init(
        contentType: String,
        pixelWidth: Int,
        pixelHeight: Int,
        byteSize: Int,
        kind: String,
        source: String,
        capturedAt: Date?
    ) {
        self.contentType = contentType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteSize = byteSize
        self.kind = kind
        self.source = source
        self.capturedAt = capturedAt
    }
}
