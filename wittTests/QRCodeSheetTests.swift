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

    func testLayoutStaysInsidePrintableMargins() {
        for paper in [QRCodeSheetPaper.a4, .letter] {
            let layout = QRCodeSheetLayout(paper: paper)
            let printableBounds = CGRect(origin: .zero, size: layout.pageSize).insetBy(dx: layout.margin, dy: layout.margin)

            XCTAssertEqual(layout.codesPerPage, 12)
            for index in 0..<layout.codesPerPage {
                XCTAssertTrue(printableBounds.contains(layout.cellFrame(at: index)))
                XCTAssertTrue(layout.cellFrame(at: index).contains(layout.qrFrame(at: index)))
                XCTAssertGreaterThanOrEqual(layout.qrFrame(at: index).width, 120)
            }
        }
    }

    func testMillimetersConvertToPDFPointsAndBack() {
        XCTAssertEqual(PDFMeasurement.points(fromMillimeters: 25.4), 72, accuracy: 0.0001)
        XCTAssertEqual(PDFMeasurement.points(fromMillimeters: 210), 595.2756, accuracy: 0.001)
        XCTAssertEqual(PDFMeasurement.millimeters(fromPoints: 72), 25.4, accuracy: 0.0001)
    }

    func testThermalLayoutUsesConfiguredWidthMarginsColumnsAndSpacing() throws {
        let configuration = QRCodeThermalLayoutConfiguration(
            paperWidthMillimeters: 80,
            columns: 2,
            rowSpacingMillimeters: 5,
            columnSpacingMillimeters: 4,
            horizontalMarginMillimeters: 6,
            topMarginMillimeters: 7,
            bottomMarginMillimeters: 8
        )
        let layout = try QRCodeSheetLayout.thermal(configuration: configuration)
        let first = layout.cellFrame(at: 0)
        let second = layout.cellFrame(at: 1)
        let third = layout.cellFrame(at: 2)

        XCTAssertEqual(layout.pageSize.width, PDFMeasurement.points(fromMillimeters: 80), accuracy: 0.001)
        XCTAssertEqual(first.minX, PDFMeasurement.points(fromMillimeters: 6), accuracy: 0.001)
        XCTAssertEqual(first.minY, PDFMeasurement.points(fromMillimeters: 7), accuracy: 0.001)
        XCTAssertEqual(second.minX - first.maxX, PDFMeasurement.points(fromMillimeters: 4), accuracy: 0.001)
        XCTAssertEqual(third.minY - first.maxY, PDFMeasurement.points(fromMillimeters: 5), accuracy: 0.001)
        XCTAssertEqual(layout.qrFrame(at: 0).width, floor(first.width), accuracy: 0.001)
    }

    func testThermalPageHeightFitsActualRowsWithoutRequiringFullRows() throws {
        let configuration = QRCodeThermalLayoutConfiguration(
            paperWidthMillimeters: 80,
            columns: 2,
            rowSpacingMillimeters: 3,
            columnSpacingMillimeters: 3,
            horizontalMarginMillimeters: 3,
            topMarginMillimeters: 4,
            bottomMarginMillimeters: 5
        )
        let layout = try QRCodeSheetLayout.thermal(configuration: configuration)
        let pageSize = layout.pageSize(at: 0, codeCount: 3)
        let expectedHeight = layout.topMargin
            + (2 * layout.cellHeight)
            + layout.rowSpacing
            + layout.bottomMargin

        XCTAssertEqual(layout.pageCount(for: 3), 1)
        XCTAssertEqual(pageSize.height, expectedHeight, accuracy: 0.001)
        XCTAssertEqual(layout.cellFrame(at: 2).maxY + layout.bottomMargin, pageSize.height, accuracy: 0.001)
    }

    func testThermalLayoutRejectsInvalidAndUnreasonablySmallGeometry() {
        var invalid = QRCodeThermalLayoutConfiguration()
        invalid.horizontalMarginMillimeters = 40
        XCTAssertThrowsError(try QRCodeSheetLayout.thermal(configuration: invalid)) { error in
            XCTAssertEqual(error as? QRCodeSheetError, .invalidGeometry)
        }

        var tooSmall = QRCodeThermalLayoutConfiguration()
        tooSmall.paperWidthMillimeters = 49
        tooSmall.columns = 2
        XCTAssertThrowsError(try QRCodeSheetLayout.thermal(configuration: tooSmall)) { error in
            XCTAssertEqual(error as? QRCodeSheetError, .qrGeometryTooSmall)
        }
        XCTAssertTrue(QRCodeSheetError.qrGeometryTooSmall.localizedDescription.contains("20 mm"))
    }

    func testThermalPaginationIsDeterministicAndFitsFinalPage() throws {
        let configuration = QRCodeThermalLayoutConfiguration(
            paperWidthMillimeters: 110,
            columns: 1,
            rowSpacingMillimeters: 20,
            columnSpacingMillimeters: 0,
            horizontalMarginMillimeters: 0,
            topMarginMillimeters: 20,
            bottomMarginMillimeters: 20
        )
        let layout = try QRCodeSheetLayout.thermal(configuration: configuration)
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
            XCTAssertFalse(try XCTUnwrap(page.string).isEmpty)
        }
    }

    func testThermalPDFUsesDerivedPageDimensionsAndValidOutput() throws {
        let codes = try QRCodeSheetBatchGenerator(tokenGenerator: QRToken.generate).generate(count: 5)
        let layout = try QRCodeSheetLayout.thermal(configuration: QRCodeThermalLayoutConfiguration(
            paperWidthMillimeters: 80,
            columns: 2,
            rowSpacingMillimeters: 4,
            columnSpacingMillimeters: 4,
            horizontalMarginMillimeters: 4,
            topMarginMillimeters: 5,
            bottomMarginMillimeters: 6
        ))
        let data = try QRCodeSheetPDFGenerator().generate(codes: codes, layout: layout)
        let document = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(document.page(at: 0))
        let expectedSize = layout.pageSize(at: 0, codeCount: codes.count)

        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        XCTAssertEqual(document.pageCount, 1)
        XCTAssertEqual(page.bounds(for: .mediaBox).width, expectedSize.width, accuracy: 1)
        XCTAssertEqual(page.bounds(for: .mediaBox).height, expectedSize.height, accuracy: 1)
    }

    func testPDFIsValidAndUsesExpectedPageCountAndSize() throws {
        let codes = try QRCodeSheetBatchGenerator(tokenGenerator: QRToken.generate).generate(count: 25)
        let layout = QRCodeSheetLayout(paper: .a4)
        let data = try QRCodeSheetPDFGenerator().generate(codes: codes, layout: layout)
        let document = try XCTUnwrap(PDFDocument(data: data))

        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        XCTAssertEqual(document.pageCount, 3)
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(page.bounds(for: .mediaBox).width, layout.pageSize.width, accuracy: 1)
        XCTAssertEqual(page.bounds(for: .mediaBox).height, layout.pageSize.height, accuracy: 1)
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

        XCTAssertThrowsError(try generator.generate(codes: codes, layout: QRCodeSheetLayout(paper: .letter))) { error in
            XCTAssertEqual(error as? QRCodeSheetError, .imageGenerationFailed(index: 0))
        }
    }

    func testBlankLineStyleChangesRenderedLabels() throws {
        let codes = try QRCodeSheetBatchGenerator(tokenGenerator: QRToken.generate).generate(count: 1)
        let generator = QRCodeSheetPDFGenerator()
        let layout = QRCodeSheetLayout(paper: .letter)

        let codeIDOnly = try generator.generate(codes: codes, layout: layout, labelStyle: .codeID)
        let blankLine = try generator.generate(codes: codes, layout: layout, labelStyle: .blankLine)

        XCTAssertNotEqual(codeIDOnly, blankLine)
    }
}
