import Foundation

public enum PhotoCaptureSource: String, Hashable, Sendable {
    case camera
    case photoLibrary = "photo-library"
}

public struct CapturedPhoto: Hashable, Sendable {
    public let data: Data
    public let source: PhotoCaptureSource
    public let capturedAt: Date?

    nonisolated public init(
        data: Data,
        source: PhotoCaptureSource,
        capturedAt: Date? = nil
    ) {
        self.data = data
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
    public let source: PhotoCaptureSource
    public let capturedAt: Date?

    nonisolated public init(
        jpegData: Data,
        thumbnailJPEGData: Data,
        dimensions: PhotoDimensions,
        source: PhotoCaptureSource,
        capturedAt: Date? = nil
    ) {
        self.jpegData = jpegData
        self.thumbnailJPEGData = thumbnailJPEGData
        self.dimensions = dimensions
        self.source = source
        self.capturedAt = capturedAt
    }

    nonisolated public var contentType: String { "image/jpeg" }
    nonisolated public var byteSize: Int { jpegData.count }

    public var photoInput: PhotoInput {
        PhotoInput(
            data: jpegData,
            contentType: contentType,
            dimensions: .init(width: dimensions.width, height: dimensions.height)
        )
    }

}
