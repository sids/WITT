import CoreGraphics
import Foundation

struct PrintableQRCode: Equatable, Sendable {
    let token: QRToken
    let url: WITTQRCodeURL

    var identifier: String {
        String(token.rawValue.prefix(8)).uppercased()
    }
}

enum QRCodeSheetError: Error, Equatable, LocalizedError {
    case invalidCount
    case duplicateToken
    case invalidGeometry
    case qrGeometryTooSmall
    case imageGenerationFailed(index: Int)
    case pdfGenerationFailed

    var errorDescription: String? {
        switch self {
        case .invalidCount:
            String(localized: "Choose between 1 and 120 labels.")
        case .duplicateToken:
            String(localized: "WITT couldn't generate a unique set of codes. Please try again.")
        case .invalidGeometry:
            String(localized: "These paper, margin, and label settings do not leave enough printable space for one label.")
        case .qrGeometryTooSmall:
            String(localized: "These label dimensions make the QR code smaller than 20 mm. Use a larger label or a square label.")
        case .imageGenerationFailed:
            String(localized: "WITT couldn't render one of the QR codes. Please try again.")
        case .pdfGenerationFailed:
            String(localized: "WITT couldn't create the PDF. Please try again.")
        }
    }
}

@MainActor
struct QRCodeSheetBatchGenerator {
    var tokenGenerator: @MainActor () throws -> QRToken

    func generate(count: Int) throws -> [PrintableQRCode] {
        guard (1...120).contains(count) else {
            throw QRCodeSheetError.invalidCount
        }

        var seen = Set<QRToken>()
        var codes: [PrintableQRCode] = []
        codes.reserveCapacity(count)

        for _ in 0..<count {
            let token = try tokenGenerator()
            guard seen.insert(token).inserted else {
                throw QRCodeSheetError.duplicateToken
            }
            codes.append(PrintableQRCode(token: token, url: WITTQRCodeURL(token: token)))
        }
        return codes
    }
}

enum PDFMeasurement {
    static let pointsPerInch: CGFloat = 72
    static let millimetersPerInch: CGFloat = 25.4

    static func points(fromMillimeters millimeters: CGFloat) -> CGFloat {
        millimeters * pointsPerInch / millimetersPerInch
    }

    static func millimeters(fromPoints points: CGFloat) -> CGFloat {
        points * millimetersPerInch / pointsPerInch
    }
}

enum QRCodeSheetPaper: String, CaseIterable, Identifiable, Sendable {
    case a4
    case letter
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .a4: "A4"
        case .letter: "US Letter"
        case .custom: "Custom"
        }
    }

    var fixedSizeMillimeters: CGSize? {
        switch self {
        case .a4: CGSize(width: 210, height: 297)
        case .letter: CGSize(width: 215.9, height: 279.4)
        case .custom: nil
        }
    }
}

enum QRCodePaperLength: String, CaseIterable, Identifiable, Sendable {
    case fixed
    case unlimited

    var id: Self { self }

    var title: String {
        switch self {
        case .fixed: "Fixed"
        case .unlimited: "Unlimited"
        }
    }
}

struct QRCodeSheetConfiguration: Equatable, Sendable {
    var paper: QRCodeSheetPaper = .custom
    var customPaperWidthMillimeters: CGFloat = 100
    var customPaperHeightMillimeters: CGFloat = 100
    var customPaperLength: QRCodePaperLength = .unlimited
    var leftMarginMillimeters: CGFloat = 0
    var rightMarginMillimeters: CGFloat = 0
    var topMarginMillimeters: CGFloat = 0
    var bottomMarginMillimeters: CGFloat = 0
    var labelWidthMillimeters: CGFloat = 25
    var labelHeightMillimeters: CGFloat = 25
    var horizontalSpacingMillimeters: CGFloat = 0
    var verticalSpacingMillimeters: CGFloat = 0
    var includesWriteInLine = false

    var paperWidthMillimeters: CGFloat {
        paper.fixedSizeMillimeters?.width ?? customPaperWidthMillimeters
    }

    var fixedPaperHeightMillimeters: CGFloat? {
        if let height = paper.fixedSizeMillimeters?.height {
            return height
        }
        return customPaperLength == .fixed ? customPaperHeightMillimeters : nil
    }

    var usesUnlimitedLength: Bool {
        paper == .custom && customPaperLength == .unlimited
    }
}

struct QRCodeLabelContentLayout: Equatable, Sendable {
    let transform: CGAffineTransform
    let qrFrame: CGRect
    let metadataFrame: CGRect?
}

struct QRCodeSheetLayout: Equatable, Sendable {
    static let minimumQRCodeSide = PDFMeasurement.points(fromMillimeters: 20)
    static let maximumPageHeight: CGFloat = 14_400
    private static let rectangularContentGap = PDFMeasurement.points(fromMillimeters: 2)
    private static let minimumMetadataWidth = PDFMeasurement.points(fromMillimeters: 14)
    private static let squareTolerance = PDFMeasurement.points(fromMillimeters: 0.1)

    private enum Format: Equatable, Sendable {
        case fixed(rows: Int)
        case unlimited
    }

    let pageSize: CGSize
    let leftMargin: CGFloat
    let rightMargin: CGFloat
    let topMargin: CGFloat
    let bottomMargin: CGFloat
    let columns: Int
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let labelSize: CGSize
    let qrSide: CGFloat
    let isSquareLabel: Bool
    private let format: Format

    init(configuration: QRCodeSheetConfiguration) throws {
        let width = PDFMeasurement.points(fromMillimeters: configuration.paperWidthMillimeters)
        let fixedHeight = configuration.fixedPaperHeightMillimeters.map {
            PDFMeasurement.points(fromMillimeters: $0)
        }
        let leftMargin = PDFMeasurement.points(fromMillimeters: configuration.leftMarginMillimeters)
        let rightMargin = PDFMeasurement.points(fromMillimeters: configuration.rightMarginMillimeters)
        let topMargin = PDFMeasurement.points(fromMillimeters: configuration.topMarginMillimeters)
        let bottomMargin = PDFMeasurement.points(fromMillimeters: configuration.bottomMarginMillimeters)
        let labelWidth = PDFMeasurement.points(fromMillimeters: configuration.labelWidthMillimeters)
        let labelHeight = PDFMeasurement.points(fromMillimeters: configuration.labelHeightMillimeters)
        let horizontalSpacing = PDFMeasurement.points(fromMillimeters: configuration.horizontalSpacingMillimeters)
        let verticalSpacing = PDFMeasurement.points(fromMillimeters: configuration.verticalSpacingMillimeters)
        let values = [
            width,
            leftMargin,
            rightMargin,
            topMargin,
            bottomMargin,
            labelWidth,
            labelHeight,
            horizontalSpacing,
            verticalSpacing,
        ] + (fixedHeight.map { [$0] } ?? [])

        guard values.allSatisfy(\.isFinite),
              width > 0,
              labelWidth > 0,
              labelHeight > 0,
              leftMargin >= 0,
              rightMargin >= 0,
              topMargin >= 0,
              bottomMargin >= 0,
              horizontalSpacing >= 0,
              verticalSpacing >= 0 else {
            throw QRCodeSheetError.invalidGeometry
        }

        let availableWidth = width - leftMargin - rightMargin
        let columns = Self.fitCount(
            available: availableWidth,
            item: labelWidth,
            spacing: horizontalSpacing
        )
        guard columns > 0 else { throw QRCodeSheetError.invalidGeometry }

        let isSquareLabel = abs(labelWidth - labelHeight) <= Self.squareTolerance
        let contentWidth = max(labelWidth, labelHeight)
        let contentHeight = min(labelWidth, labelHeight)
        let qrSide = if isSquareLabel {
            contentHeight
        } else {
            min(
                contentHeight,
                contentWidth - Self.rectangularContentGap - Self.minimumMetadataWidth
            )
        }
        guard qrSide >= Self.minimumQRCodeSide else { throw QRCodeSheetError.qrGeometryTooSmall }

        let resolvedFormat: Format
        let resolvedPageHeight: CGFloat
        if let fixedHeight {
            guard fixedHeight > 0 else { throw QRCodeSheetError.invalidGeometry }
            let availableHeight = fixedHeight - topMargin - bottomMargin
            let rows = Self.fitCount(
                available: availableHeight,
                item: labelHeight,
                spacing: verticalSpacing
            )
            guard rows > 0 else { throw QRCodeSheetError.invalidGeometry }
            resolvedFormat = .fixed(rows: rows)
            resolvedPageHeight = fixedHeight
        } else {
            let minimumPageHeight = topMargin + labelHeight + bottomMargin
            guard minimumPageHeight <= Self.maximumPageHeight else {
                throw QRCodeSheetError.invalidGeometry
            }
            resolvedFormat = .unlimited
            resolvedPageHeight = minimumPageHeight
        }

        pageSize = CGSize(width: width, height: resolvedPageHeight)
        self.leftMargin = leftMargin
        self.rightMargin = rightMargin
        self.topMargin = topMargin
        self.bottomMargin = bottomMargin
        self.columns = columns
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        labelSize = CGSize(width: labelWidth, height: labelHeight)
        self.qrSide = qrSide
        self.isSquareLabel = isSquareLabel
        format = resolvedFormat
    }

    var codesPerPage: Int {
        switch format {
        case let .fixed(rows):
            columns * rows
        case .unlimited:
            columns * maximumRowsPerPage
        }
    }

    var estimatedQRCodeSideMillimeters: CGFloat {
        PDFMeasurement.millimeters(fromPoints: qrSide)
    }

    func pageCount(for codeCount: Int) -> Int {
        guard codeCount > 0 else { return 0 }
        return Int(ceil(Double(codeCount) / Double(codesPerPage)))
    }

    func pageSize(at pageIndex: Int, codeCount: Int) -> CGSize {
        switch format {
        case .fixed:
            return pageSize
        case .unlimited:
            let remainingCodes = max(0, codeCount - (pageIndex * codesPerPage))
            let codesOnPage = min(codesPerPage, remainingCodes)
            let rowsOnPage = Int(ceil(Double(codesOnPage) / Double(columns)))
            let contentHeight = CGFloat(rowsOnPage) * labelSize.height
            let spacingHeight = CGFloat(max(0, rowsOnPage - 1)) * verticalSpacing
            return CGSize(width: pageSize.width, height: topMargin + contentHeight + spacingHeight + bottomMargin)
        }
    }

    func labelFrame(at index: Int) -> CGRect {
        let column = index % columns
        let row = index / columns
        return CGRect(
            x: leftMargin + CGFloat(column) * (labelSize.width + horizontalSpacing),
            y: topMargin + CGFloat(row) * (labelSize.height + verticalSpacing),
            width: labelSize.width,
            height: labelSize.height
        )
    }

    func contentLayout(at index: Int) -> QRCodeLabelContentLayout {
        let label = labelFrame(at: index)
        let isPortraitRectangle = !isSquareLabel && label.height > label.width
        let contentSize = isPortraitRectangle
            ? CGSize(width: label.height, height: label.width)
            : label.size
        let transform = if isPortraitRectangle {
            CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: label.maxX, ty: label.minY)
        } else {
            CGAffineTransform(translationX: label.minX, y: label.minY)
        }
        let qrFrame = CGRect(
            x: isSquareLabel ? (contentSize.width - qrSide) / 2 : 0,
            y: (contentSize.height - qrSide) / 2,
            width: qrSide,
            height: qrSide
        )
        let metadataFrame: CGRect? = if isSquareLabel {
            nil
        } else {
            CGRect(
                x: qrFrame.maxX + Self.rectangularContentGap,
                y: 0,
                width: contentSize.width - qrFrame.maxX - Self.rectangularContentGap,
                height: contentSize.height
            )
        }

        return QRCodeLabelContentLayout(
            transform: transform,
            qrFrame: qrFrame,
            metadataFrame: metadataFrame
        )
    }

    private var maximumRowsPerPage: Int {
        let availableHeight = Self.maximumPageHeight - topMargin - bottomMargin
        return max(
            1,
            Self.fitCount(
                available: availableHeight,
                item: labelSize.height,
                spacing: verticalSpacing
            )
        )
    }

    private static func fitCount(available: CGFloat, item: CGFloat, spacing: CGFloat) -> Int {
        guard available >= item else { return 0 }
        return max(0, Int(floor((available + spacing) / (item + spacing))))
    }
}
