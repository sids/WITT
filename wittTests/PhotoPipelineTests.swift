import AVFoundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import witt

final class PhotoPipelineTests: XCTestCase {
    func testCameraAuthorizationStateMapsEverySystemStatus() {
        XCTAssertEqual(
            CameraAuthorizationState(isCameraAvailable: true, authorizationStatus: .notDetermined),
            .notDetermined
        )
        XCTAssertEqual(
            CameraAuthorizationState(isCameraAvailable: true, authorizationStatus: .authorized),
            .authorized
        )
        XCTAssertEqual(
            CameraAuthorizationState(isCameraAvailable: true, authorizationStatus: .denied),
            .denied
        )
        XCTAssertEqual(
            CameraAuthorizationState(isCameraAvailable: true, authorizationStatus: .restricted),
            .restricted
        )
    }

    func testUnavailableCameraTakesPriorityOverAuthorization() {
        XCTAssertEqual(
            CameraAuthorizationState(isCameraAvailable: false, authorizationStatus: .authorized),
            .unavailable
        )
    }

    func testSettingsRecoveryIsOfferedOnlyForDeniedAndRestrictedAccess() {
        XCTAssertTrue(CameraAuthorizationState.denied.offersSettingsRecovery)
        XCTAssertTrue(CameraAuthorizationState.restricted.offersSettingsRecovery)
        XCTAssertFalse(CameraAuthorizationState.notDetermined.offersSettingsRecovery)
        XCTAssertFalse(CameraAuthorizationState.authorized.offersSettingsRecovery)
        XCTAssertFalse(CameraAuthorizationState.unavailable.offersSettingsRecovery)
    }

    func testNormalizerCapsLongEdgeAndCreatesThumbnail() throws {
        let inputData = try makeJPEG(width: 3_000, height: 1_500)
        let normalized = try PhotoNormalizer().normalize(
            CapturedPhoto(
                data: inputData,
                source: .camera
            )
        )

        XCTAssertEqual(normalized.dimensions, PhotoDimensions(width: 2_048, height: 1_024))
        XCTAssertEqual(try dimensions(of: normalized.jpegData), normalized.dimensions)
        XCTAssertEqual(
            try dimensions(of: normalized.thumbnailJPEGData),
            PhotoDimensions(width: 320, height: 160)
        )
        XCTAssertEqual(normalized.byteSize, normalized.jpegData.count)
        XCTAssertEqual(normalized.contentType, "image/jpeg")
    }

    func testNormalizerDoesNotUpscaleSmallImages() throws {
        let inputData = try makeJPEG(width: 100, height: 50)
        let normalized = try PhotoNormalizer().normalize(
            CapturedPhoto(
                data: inputData,
                source: .photoLibrary
            )
        )

        XCTAssertEqual(normalized.dimensions, PhotoDimensions(width: 100, height: 50))
        XCTAssertEqual(
            try dimensions(of: normalized.thumbnailJPEGData),
            PhotoDimensions(width: 100, height: 50)
        )
    }

    func testNormalizerAppliesSourceOrientationAndDropsItFromOutput() throws {
        let inputData = try makeJPEG(width: 120, height: 80, orientation: 6)
        let inputProperties = try imageProperties(of: inputData)
        let inputEXIF = inputProperties[kCGImagePropertyExifDictionary] as? NSDictionary
        XCTAssertNotNil(inputEXIF?[kCGImagePropertyExifUserComment as String])

        let normalized = try PhotoNormalizer().normalize(
            CapturedPhoto(
                data: inputData,
                source: .camera
            )
        )

        XCTAssertEqual(normalized.dimensions, PhotoDimensions(width: 80, height: 120))
        let outputProperties = try imageProperties(of: normalized.jpegData)
        XCTAssertNil(outputProperties[kCGImagePropertyOrientation])
        let outputEXIF = outputProperties[kCGImagePropertyExifDictionary] as? NSDictionary
        XCTAssertNil(outputEXIF?[kCGImagePropertyExifUserComment as String])

        let thumbnailProperties = try imageProperties(of: normalized.thumbnailJPEGData)
        XCTAssertNil(thumbnailProperties[kCGImagePropertyOrientation])
        let thumbnailEXIF = thumbnailProperties[kCGImagePropertyExifDictionary] as? NSDictionary
        XCTAssertNil(thumbnailEXIF?[kCGImagePropertyExifUserComment as String])
    }

    func testNormalizedPhotoExposesAIAndPersistenceValues() throws {
        let capturedAt = Date(timeIntervalSince1970: 1_234_567)
        let normalized = try PhotoNormalizer().normalize(
            CapturedPhoto(
                data: try makeJPEG(width: 640, height: 480),
                source: .photoLibrary,
                capturedAt: capturedAt
            )
        )

        XCTAssertEqual(normalized.photoInput.data, normalized.jpegData)
        XCTAssertEqual(normalized.photoInput.contentType, "image/jpeg")
        XCTAssertEqual(normalized.photoInput.dimensions, .init(width: 640, height: 480))

        XCTAssertEqual(normalized.contentType, "image/jpeg")
        XCTAssertEqual(normalized.dimensions.width, 640)
        XCTAssertEqual(normalized.dimensions.height, 480)
        XCTAssertEqual(normalized.byteSize, normalized.jpegData.count)
        XCTAssertEqual(normalized.source, .photoLibrary)
        XCTAssertEqual(normalized.capturedAt, capturedAt)
    }

    func testNormalizerRejectsInvalidImageData() {
        XCTAssertThrowsError(
            try PhotoNormalizer().normalize(
                CapturedPhoto(
                    data: Data([0x00, 0x01]),
                    source: .camera
                )
            )
        ) { error in
            XCTAssertEqual(error as? PhotoNormalizationError, .invalidImageData)
        }
    }

    private func makeJPEG(width: Int, height: Int, orientation: Int? = nil) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        }
        guard let cgImage = image.cgImage else {
            throw TestImageError.creationFailed
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw TestImageError.creationFailed
        }
        var properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.9
        ]
        properties[kCGImagePropertyExifDictionary] = [
            kCGImagePropertyExifUserComment: "metadata should not survive normalization"
        ]
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation
        }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw TestImageError.creationFailed
        }
        return data as Data
    }

    private func dimensions(of data: Data) throws -> PhotoDimensions {
        let properties = try imageProperties(of: data)
        guard let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw TestImageError.invalidProperties
        }
        return PhotoDimensions(width: width, height: height)
    }

    private func imageProperties(of data: Data) throws -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any] else {
            throw TestImageError.invalidProperties
        }
        return properties
    }
}

private enum TestImageError: Error {
    case creationFailed
    case invalidProperties
}
