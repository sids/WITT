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
        for paper in QRCodeSheetPaper.allCases {
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
