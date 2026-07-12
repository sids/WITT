import CoreGraphics
import PDFKit
import XCTest
@testable import witt

@MainActor
final class QRCodeSheetTests: XCTestCase {
    func testBatchHasRequestedUniqueCanonicalTokensAndURLs() throws {
        let codes = try QRCodeSheetBatchGenerator(tokenGenerator: QRToken.generate).generate(count: 60)

        XCTAssertEqual(codes.count, 60)
        XCTAssertEqual(Set(codes.map(\.token)).count, 60)
        for code in codes {
            XCTAssertEqual(QRToken(rawValue: code.token.rawValue), code.token)
            XCTAssertEqual(code.url.absoluteString, "witt://qr/v1/\(code.token.rawValue)")
            XCTAssertEqual(code.identifier.count, 8)
        }
    }

    func testBatchRejectsInvalidCountAndDuplicateTokens() throws {
        XCTAssertThrowsError(try QRCodeSheetBatchGenerator(tokenGenerator: QRToken.generate).generate(count: 0)) { error in
            XCTAssertEqual(error as? QRCodeSheetError, .invalidCount)
        }

        let token = try XCTUnwrap(QRToken(rawValue: "AAAAAAAAAAAAAAAAAAAAAA"))
        let generator = QRCodeSheetBatchGenerator(tokenGenerator: { token })
        XCTAssertThrowsError(try generator.generate(count: 2)) { error in
            XCTAssertEqual(error as? QRCodeSheetError, .duplicateToken)
        }
    }

    func testMillimetersConvertToPDFPointsAndBack() {
        XCTAssertEqual(PDFMeasurement.points(fromMillimeters: 25.4), 72, accuracy: 0.0001)
        XCTAssertEqual(PDFMeasurement.points(fromMillimeters: 210), 595.2756, accuracy: 0.001)
        XCTAssertEqual(PDFMeasurement.millimeters(fromPoints: 72), 25.4, accuracy: 0.0001)
    }

    func testDefaultConfigurationMatchesFourUpSquareRoll() throws {
        let configuration = QRCodeSheetConfiguration()
        let layout = try QRCodeSheetLayout(configuration: configuration)

        XCTAssertEqual(configuration.paper, .custom)
        XCTAssertEqual(configuration.customPaperLength, .unlimited)
        XCTAssertEqual(configuration.paperWidthMillimeters, 100)
        XCTAssertEqual(configuration.labelWidthMillimeters, 25)
        XCTAssertEqual(configuration.labelHeightMillimeters, 25)
        XCTAssertEqual(layout.pageSize.width, PDFMeasurement.points(fromMillimeters: 100), accuracy: 0.001)
        XCTAssertEqual(layout.columns, 4)
        XCTAssertTrue(layout.isSquareLabel)
        XCTAssertEqual(layout.estimatedQRCodeSideMillimeters, 25, accuracy: 0.001)
        XCTAssertEqual(
            layout.pageSize(at: 0, codeCount: 48).height,
            PDFMeasurement.points(fromMillimeters: 300),
            accuracy: 0.001
        )

        for index in 0..<4 {
            let label = layout.labelFrame(at: index)
            XCTAssertEqual(label.minX, PDFMeasurement.points(fromMillimeters: CGFloat(index * 25)), accuracy: 0.001)
            XCTAssertEqual(label.width, PDFMeasurement.points(fromMillimeters: 25), accuracy: 0.001)
            XCTAssertNil(layout.contentLayout(at: index).metadataFrame)
        }
        XCTAssertEqual(
            layout.labelFrame(at: 3).maxX,
            PDFMeasurement.points(fromMillimeters: 100),
            accuracy: 0.001
        )
    }

    func testA4AndLetterUseAutomaticFixedDimensions() throws {
        let expectations: [(QRCodeSheetPaper, CGSize)] = [
            (.a4, CGSize(width: 210, height: 297)),
            (.letter, CGSize(width: 215.9, height: 279.4)),
        ]

        for (paper, millimeters) in expectations {
            var configuration = QRCodeSheetConfiguration()
            configuration.paper = paper
            configuration.customPaperLength = .unlimited
            let layout = try QRCodeSheetLayout(configuration: configuration)

            XCTAssertEqual(
                layout.pageSize.width,
                PDFMeasurement.points(fromMillimeters: millimeters.width),
                accuracy: 0.001
            )
            XCTAssertEqual(
                layout.pageSize.height,
                PDFMeasurement.points(fromMillimeters: millimeters.height),
                accuracy: 0.001
            )
            XCTAssertEqual(layout.columns, 8)
            XCTAssertEqual(layout.codesPerPage, 88)
            XCTAssertEqual(layout.pageCount(for: 120), 2)
        }
    }

    func testFixedCustomLayoutUsesExactMarginsLabelSizeAndSpacing() throws {
        var configuration = QRCodeSheetConfiguration()
        configuration.customPaperLength = .fixed
        configuration.customPaperWidthMillimeters = 120
        configuration.customPaperHeightMillimeters = 80
        configuration.leftMarginMillimeters = 5
        configuration.rightMarginMillimeters = 7
        configuration.topMarginMillimeters = 6
        configuration.bottomMarginMillimeters = 4
        configuration.labelWidthMillimeters = 50
        configuration.labelHeightMillimeters = 25
        configuration.horizontalSpacingMillimeters = 2
        configuration.verticalSpacingMillimeters = 3
        let layout = try QRCodeSheetLayout(configuration: configuration)
        let first = layout.labelFrame(at: 0)
        let second = layout.labelFrame(at: 1)
        let third = layout.labelFrame(at: 2)

        XCTAssertEqual(layout.columns, 2)
        XCTAssertEqual(layout.codesPerPage, 4)
        XCTAssertEqual(first.minX, PDFMeasurement.points(fromMillimeters: 5), accuracy: 0.001)
        XCTAssertEqual(first.minY, PDFMeasurement.points(fromMillimeters: 6), accuracy: 0.001)
        XCTAssertEqual(first.width, PDFMeasurement.points(fromMillimeters: 50), accuracy: 0.001)
        XCTAssertEqual(first.height, PDFMeasurement.points(fromMillimeters: 25), accuracy: 0.001)
        XCTAssertEqual(second.minX - first.maxX, PDFMeasurement.points(fromMillimeters: 2), accuracy: 0.001)
        XCTAssertEqual(third.minY - first.maxY, PDFMeasurement.points(fromMillimeters: 3), accuracy: 0.001)
        XCTAssertEqual(layout.estimatedQRCodeSideMillimeters, 25, accuracy: 0.001)
        XCTAssertGreaterThan(try XCTUnwrap(layout.contentLayout(at: 0).metadataFrame).minX, layout.contentLayout(at: 0).qrFrame.maxX)
    }

    func testPortraitRectangleRotatesQRAndMetadataTogether() throws {
        var configuration = QRCodeSheetConfiguration()
        configuration.customPaperWidthMillimeters = 25
        configuration.labelWidthMillimeters = 25
        configuration.labelHeightMillimeters = 50
        let layout = try QRCodeSheetLayout(configuration: configuration)
        let label = layout.labelFrame(at: 0)
        let content = layout.contentLayout(at: 0)
        let localBounds = CGRect(origin: .zero, size: CGSize(width: label.height, height: label.width))

        XCTAssertFalse(layout.isSquareLabel)
        XCTAssertEqual(localBounds.applying(content.transform).standardized.minX, label.minX, accuracy: 0.001)
        XCTAssertEqual(localBounds.applying(content.transform).standardized.minY, label.minY, accuracy: 0.001)
        XCTAssertEqual(localBounds.applying(content.transform).standardized.width, label.width, accuracy: 0.001)
        XCTAssertEqual(localBounds.applying(content.transform).standardized.height, label.height, accuracy: 0.001)
        XCTAssertGreaterThan(try XCTUnwrap(content.metadataFrame).minX, content.qrFrame.maxX)
    }

    func testUnlimitedPageHeightFitsActualRows() throws {
        var configuration = QRCodeSheetConfiguration()
        configuration.topMarginMillimeters = 2
        configuration.bottomMarginMillimeters = 3
        configuration.verticalSpacingMillimeters = 1
        let layout = try QRCodeSheetLayout(configuration: configuration)
        let pageSize = layout.pageSize(at: 0, codeCount: 5)

        XCTAssertEqual(layout.pageCount(for: 5), 1)
        XCTAssertEqual(
            pageSize.height,
            PDFMeasurement.points(fromMillimeters: 56),
            accuracy: 0.001
        )
        XCTAssertEqual(
            layout.labelFrame(at: 4).maxY + layout.bottomMargin,
            pageSize.height,
            accuracy: 0.001
        )
    }

    func testLayoutRejectsInvalidAndUnreasonablySmallGeometry() {
        var invalid = QRCodeSheetConfiguration()
        invalid.leftMarginMillimeters = 60
        invalid.rightMarginMillimeters = 60
        XCTAssertThrowsError(try QRCodeSheetLayout(configuration: invalid)) { error in
            XCTAssertEqual(error as? QRCodeSheetError, .invalidGeometry)
        }

        var tooSmall = QRCodeSheetConfiguration()
        tooSmall.labelWidthMillimeters = 19
        tooSmall.labelHeightMillimeters = 19
        XCTAssertThrowsError(try QRCodeSheetLayout(configuration: tooSmall)) { error in
            XCTAssertEqual(error as? QRCodeSheetError, .qrGeometryTooSmall)
        }
        XCTAssertTrue(QRCodeSheetError.qrGeometryTooSmall.localizedDescription.contains("20 mm"))
    }

    func testUnlimitedPaginationIsDeterministicAndFitsFinalPage() throws {
        var configuration = QRCodeSheetConfiguration()
        configuration.customPaperWidthMillimeters = 100
        configuration.labelWidthMillimeters = 100
        configuration.labelHeightMillimeters = 100
        configuration.topMarginMillimeters = 20
        configuration.bottomMarginMillimeters = 20
        configuration.verticalSpacingMillimeters = 20
        let layout = try QRCodeSheetLayout(configuration: configuration)
        let count = 120
        let pages = layout.pageCount(for: count)

        XCTAssertGreaterThan(pages, 1)
        for pageIndex in 0..<pages {
            XCTAssertLessThanOrEqual(layout.pageSize(at: pageIndex, codeCount: count).height, QRCodeSheetLayout.maximumPageHeight)
        }
        XCTAssertLessThan(
            layout.pageSize(at: pages - 1, codeCount: count).height,
            layout.pageSize(at: 0, codeCount: count).height
        )

        let codes = try QRCodeSheetBatchGenerator(tokenGenerator: QRToken.generate).generate(count: count)
        let pixel = [UInt8](repeating: 0, count: 4)
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixel) as CFData))
        let image = try XCTUnwrap(CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        let data = try QRCodeSheetPDFGenerator(imageGenerator: { _, _ in image })
            .generate(codes: codes, layout: layout)
        let document = try XCTUnwrap(PDFDocument(data: data))

        XCTAssertEqual(document.pageCount, pages)
        for pageIndex in 0..<pages {
            let page = try XCTUnwrap(document.page(at: pageIndex))
            XCTAssertEqual(
                page.bounds(for: .mediaBox).height,
                layout.pageSize(at: pageIndex, codeCount: count).height,
                accuracy: 1
            )
        }
    }

    func testPDFIsValidAndUsesExpectedPageCountAndSize() throws {
        let codes = try QRCodeSheetBatchGenerator(tokenGenerator: QRToken.generate).generate(count: 100)
        var configuration = QRCodeSheetConfiguration()
        configuration.paper = .a4
        let layout = try QRCodeSheetLayout(configuration: configuration)
        let data = try QRCodeSheetPDFGenerator().generate(codes: codes, layout: layout)
        let document = try XCTUnwrap(PDFDocument(data: data))

        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        XCTAssertEqual(document.pageCount, 2)
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(page.bounds(for: .mediaBox).width, layout.pageSize.width, accuracy: 1)
        XCTAssertEqual(page.bounds(for: .mediaBox).height, layout.pageSize.height, accuracy: 1)
    }

    func testSquarePDFOmitsIdentifierAndRectangleIncludesIt() throws {
        let codes = try QRCodeSheetBatchGenerator(tokenGenerator: QRToken.generate).generate(count: 1)
        let squareLayout = try QRCodeSheetLayout(configuration: QRCodeSheetConfiguration())
        let squareData = try QRCodeSheetPDFGenerator().generate(codes: codes, layout: squareLayout)
        let squareDocument = try XCTUnwrap(PDFDocument(data: squareData))

        var rectangularConfiguration = QRCodeSheetConfiguration()
        rectangularConfiguration.customPaperWidthMillimeters = 50
        rectangularConfiguration.labelWidthMillimeters = 50
        let rectangularLayout = try QRCodeSheetLayout(configuration: rectangularConfiguration)
        let rectangularData = try QRCodeSheetPDFGenerator().generate(
            codes: codes,
            layout: rectangularLayout
        )
        let rectangularDocument = try XCTUnwrap(PDFDocument(data: rectangularData))

        XCTAssertFalse((squareDocument.page(at: 0)?.string ?? "").contains(codes[0].identifier))
        XCTAssertTrue((rectangularDocument.page(at: 0)?.string ?? "").contains(codes[0].identifier))
    }

    func testRenderedQRCodeHasCrispSymmetricQuietZone() throws {
        let token = try XCTUnwrap(QRToken(rawValue: "AAAAAAAAAAAAAAAAAAAAAA"))
        let image = try XCTUnwrap(QRCodeSheetPDFGenerator.makeQRCode(
            payload: WITTQRCodeURL(token: token).absoluteString,
            targetSide: 160
        ))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        let darkCoordinates = pixels.enumerated().compactMap { offset, value -> (x: Int, y: Int)? in
            guard value < 128 else { return nil }
            return (offset % image.width, offset / image.width)
        }
        let minX = try XCTUnwrap(darkCoordinates.map(\.x).min())
        let maxX = try XCTUnwrap(darkCoordinates.map(\.x).max())
        let minY = try XCTUnwrap(darkCoordinates.map(\.y).min())
        let maxY = try XCTUnwrap(darkCoordinates.map(\.y).max())

        XCTAssertEqual(minX, image.width - 1 - maxX)
        XCTAssertEqual(minY, image.height - 1 - maxY)
        XCTAssertGreaterThanOrEqual(minX, 4)
        XCTAssertGreaterThanOrEqual(minY, 4)
        XCTAssertTrue(pixels.allSatisfy { $0 == 0 || $0 == 255 })
    }

    func testPDFReportsImageGenerationFailure() throws {
        let codes = try QRCodeSheetBatchGenerator(tokenGenerator: QRToken.generate).generate(count: 1)
        let generator = QRCodeSheetPDFGenerator(imageGenerator: { _, _ in nil })
        var configuration = QRCodeSheetConfiguration()
        configuration.paper = .letter
        let layout = try QRCodeSheetLayout(configuration: configuration)

        XCTAssertThrowsError(try generator.generate(codes: codes, layout: layout)) { error in
            XCTAssertEqual(error as? QRCodeSheetError, .imageGenerationFailed(index: 0))
        }
    }

    func testWriteInLineChangesRectangularLabels() throws {
        let codes = try QRCodeSheetBatchGenerator(tokenGenerator: QRToken.generate).generate(count: 1)
        let generator = QRCodeSheetPDFGenerator()
        var configuration = QRCodeSheetConfiguration()
        configuration.customPaperWidthMillimeters = 50
        configuration.labelWidthMillimeters = 50
        let layout = try QRCodeSheetLayout(configuration: configuration)

        let identifierOnly = try generator.generate(codes: codes, layout: layout)
        let writeInLine = try generator.generate(
            codes: codes,
            layout: layout,
            includesWriteInLine: true
        )

        XCTAssertNotEqual(identifierOnly, writeInLine)
    }
}
