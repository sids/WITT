import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct PhotoNormalizer: Hashable, Sendable {
    public let maximumLongEdge: Int
    public let thumbnailLongEdge: Int
    public let jpegQuality: Double
    public let thumbnailJPEGQuality: Double

    nonisolated public init(
        maximumLongEdge: Int = 2_048,
        thumbnailLongEdge: Int = 320,
        jpegQuality: Double = 0.82,
        thumbnailJPEGQuality: Double = 0.72
    ) {
        precondition(maximumLongEdge > 0)
        precondition(thumbnailLongEdge > 0)
        precondition((0 ... 1).contains(jpegQuality))
        precondition((0 ... 1).contains(thumbnailJPEGQuality))

        self.maximumLongEdge = maximumLongEdge
        self.thumbnailLongEdge = thumbnailLongEdge
        self.jpegQuality = jpegQuality
        self.thumbnailJPEGQuality = thumbnailJPEGQuality
    }

    nonisolated public func normalize(_ capturedPhoto: CapturedPhoto) throws -> NormalizedPhoto {
        guard let source = CGImageSourceCreateWithData(capturedPhoto.data as CFData, nil) else {
            throw PhotoNormalizationError.invalidImageData
        }
        guard CGImageSourceGetCount(source) > 0 else {
            throw PhotoNormalizationError.invalidImageData
        }

        let normalizedImage = try makeImage(from: source, maximumLongEdge: maximumLongEdge)
        let thumbnailImage = try makeImage(from: source, maximumLongEdge: thumbnailLongEdge)
        let jpegData = try encodeJPEG(normalizedImage, quality: jpegQuality)
        let thumbnailData = try encodeJPEG(thumbnailImage, quality: thumbnailJPEGQuality)

        return NormalizedPhoto(
            jpegData: jpegData,
            thumbnailJPEGData: thumbnailData,
            dimensions: PhotoDimensions(
                width: normalizedImage.width,
                height: normalizedImage.height
            ),
            source: capturedPhoto.source,
            capturedAt: capturedPhoto.capturedAt
        )
    }

    nonisolated private func makeImage(
        from source: CGImageSource,
        maximumLongEdge: Int
    ) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumLongEdge
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PhotoNormalizationError.decodingFailed
        }
        return image
    }

    nonisolated private func encodeJPEG(_ image: CGImage, quality: Double) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw PhotoNormalizationError.encodingFailed
        }

        // Supplying only encoding quality intentionally drops source metadata.
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw PhotoNormalizationError.encodingFailed
        }
        return data as Data
    }
}

public enum PhotoNormalizationError: Error, Equatable, LocalizedError, Sendable {
    case invalidImageData
    case decodingFailed
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidImageData, .decodingFailed:
            "That file is not a readable image."
        case .encodingFailed:
            "WITT could not prepare that photo."
        }
    }
}
