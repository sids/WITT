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
            String(localized: "These roll settings do not leave enough printable space inside the margins.")
        case .qrGeometryTooSmall:
            String(localized: "These roll settings make each QR code smaller than 20 mm. Use fewer codes per row, a wider roll, or smaller margins and spacing.")
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
    case thermal

    var id: Self { self }

    var title: String {
        switch self {
        case .a4: "A4"
        case .letter: "US Letter"
        case .thermal: "Thermal Roll"
        }
    }

    var sheetPageSize: CGSize? {
        switch self {
        case .a4: CGSize(width: 595.28, height: 841.89)
        case .letter: CGSize(width: 612, height: 792)
        case .thermal: nil
        }
    }
}

enum QRCodeSheetLabelStyle: String, CaseIterable, Identifiable, Sendable {
    case codeID
    case blankLine

    var id: Self { self }

    var title: String {
        switch self {
        case .codeID: "Code ID"
        case .blankLine: "Write-In"
        }
    }
}

struct QRCodeThermalLayoutConfiguration: Equatable, Sendable {
    var paperWidthMillimeters: CGFloat = 62
    var columns = 2
    var rowSpacingMillimeters: CGFloat = 3
    var columnSpacingMillimeters: CGFloat = 3
    var horizontalMarginMillimeters: CGFloat = 3
    var topMarginMillimeters: CGFloat = 3
    var bottomMarginMillimeters: CGFloat = 3
}

struct QRCodeSheetLayout: Equatable, Sendable {
    static let minimumQRCodeSide = PDFMeasurement.points(fromMillimeters: 20)
    static let maximumPageHeight: CGFloat = 14_400

    private enum Format: Equatable, Sendable {
        case sheet(rows: Int)
        case thermal
    }

    let pageSize: CGSize
    let horizontalMargin: CGFloat
    let topMargin: CGFloat
    let bottomMargin: CGFloat
    let columns: Int
    let rowSpacing: CGFloat
    let columnSpacing: CGFloat
    let labelHeight: CGFloat
    let qrSide: CGFloat
    let cellHeight: CGFloat
    private let format: Format

    var margin: CGFloat { horizontalMargin }
    var spacing: CGFloat { columnSpacing }

    init(
        paper: QRCodeSheetPaper,
        margin: CGFloat = 36,
        columns: Int = 3,
        rows: Int = 4,
        spacing: CGFloat = 14,
        labelHeight: CGFloat = 18
    ) {
        precondition(paper != .thermal, "Use thermal(configuration:) for roll layouts.")
        let pageSize = paper.sheetPageSize ?? .zero
        let availableWidth = pageSize.width - (2 * margin) - (CGFloat(columns - 1) * spacing)
        let availableHeight = pageSize.height - (2 * margin) - (CGFloat(rows - 1) * spacing)
        let cellWidth = availableWidth / CGFloat(columns)
        let cellHeight = availableHeight / CGFloat(rows)

        self.pageSize = pageSize
        horizontalMargin = margin
        topMargin = margin
        bottomMargin = margin
        self.columns = columns
        rowSpacing = spacing
        columnSpacing = spacing
        self.labelHeight = labelHeight
        qrSide = floor(min(cellWidth - 2, cellHeight - labelHeight - 10))
        self.cellHeight = cellHeight
        format = .sheet(rows: rows)
    }

    static func thermal(
        configuration: QRCodeThermalLayoutConfiguration,
        labelHeight: CGFloat = 18
    ) throws -> QRCodeSheetLayout {
        let width = PDFMeasurement.points(fromMillimeters: configuration.paperWidthMillimeters)
        let horizontalMargin = PDFMeasurement.points(fromMillimeters: configuration.horizontalMarginMillimeters)
        let topMargin = PDFMeasurement.points(fromMillimeters: configuration.topMarginMillimeters)
        let bottomMargin = PDFMeasurement.points(fromMillimeters: configuration.bottomMarginMillimeters)
        let rowSpacing = PDFMeasurement.points(fromMillimeters: configuration.rowSpacingMillimeters)
        let columnSpacing = PDFMeasurement.points(fromMillimeters: configuration.columnSpacingMillimeters)

        guard width > 0,
              configuration.columns > 0,
              horizontalMargin >= 0,
              topMargin >= 0,
              bottomMargin >= 0,
              rowSpacing >= 0,
              columnSpacing >= 0 else {
            throw QRCodeSheetError.invalidGeometry
        }

        let availableWidth = width - (2 * horizontalMargin) - (CGFloat(configuration.columns - 1) * columnSpacing)
        guard availableWidth > 0 else { throw QRCodeSheetError.invalidGeometry }
        let cellWidth = availableWidth / CGFloat(configuration.columns)
        let qrSide = floor(cellWidth)
        guard qrSide >= minimumQRCodeSide else { throw QRCodeSheetError.qrGeometryTooSmall }

        let cellHeight = qrSide + 10 + labelHeight
        let minimumPageHeight = topMargin + cellHeight + bottomMargin
        guard minimumPageHeight <= maximumPageHeight else { throw QRCodeSheetError.invalidGeometry }

        return QRCodeSheetLayout(
            pageSize: CGSize(width: width, height: minimumPageHeight),
            horizontalMargin: horizontalMargin,
            topMargin: topMargin,
            bottomMargin: bottomMargin,
            columns: configuration.columns,
            rowSpacing: rowSpacing,
            columnSpacing: columnSpacing,
            labelHeight: labelHeight,
            qrSide: qrSide,
            cellHeight: cellHeight,
            format: .thermal
        )
    }

    private init(
        pageSize: CGSize,
        horizontalMargin: CGFloat,
        topMargin: CGFloat,
        bottomMargin: CGFloat,
        columns: Int,
        rowSpacing: CGFloat,
        columnSpacing: CGFloat,
        labelHeight: CGFloat,
        qrSide: CGFloat,
        cellHeight: CGFloat,
        format: Format
    ) {
        self.pageSize = pageSize
        self.horizontalMargin = horizontalMargin
        self.topMargin = topMargin
        self.bottomMargin = bottomMargin
        self.columns = columns
        self.rowSpacing = rowSpacing
        self.columnSpacing = columnSpacing
        self.labelHeight = labelHeight
        self.qrSide = qrSide
        self.cellHeight = cellHeight
        self.format = format
    }

    var codesPerPage: Int {
        switch format {
        case let .sheet(rows):
            columns * rows
        case .thermal:
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
        case .sheet:
            return pageSize
        case .thermal:
            let remainingCodes = max(0, codeCount - (pageIndex * codesPerPage))
            let codesOnPage = min(codesPerPage, remainingCodes)
            let rowsOnPage = Int(ceil(Double(codesOnPage) / Double(columns)))
            let contentHeight = CGFloat(rowsOnPage) * cellHeight
            let spacingHeight = CGFloat(max(0, rowsOnPage - 1)) * rowSpacing
            return CGSize(width: pageSize.width, height: topMargin + contentHeight + spacingHeight + bottomMargin)
        }
    }

    func cellFrame(at index: Int) -> CGRect {
        let availableWidth = pageSize.width - (2 * horizontalMargin) - (CGFloat(columns - 1) * columnSpacing)
        let cellWidth = availableWidth / CGFloat(columns)
        let column = index % columns
        let row = index / columns
        return CGRect(
            x: horizontalMargin + CGFloat(column) * (cellWidth + columnSpacing),
            y: topMargin + CGFloat(row) * (cellHeight + rowSpacing),
            width: cellWidth,
            height: cellHeight
        )
    }

    func qrFrame(at index: Int) -> CGRect {
        let cell = cellFrame(at: index)
        return CGRect(
            x: cell.midX - qrSide / 2,
            y: cell.minY,
            width: qrSide,
            height: qrSide
        )
    }

    func identifierFrame(at index: Int) -> CGRect {
        let cell = cellFrame(at: index)
        return CGRect(x: cell.minX, y: cell.maxY - labelHeight, width: cell.width, height: labelHeight)
    }

    private var maximumRowsPerPage: Int {
        let availableHeight = Self.maximumPageHeight - topMargin - bottomMargin
        return max(1, Int(floor((availableHeight + rowSpacing) / (cellHeight + rowSpacing))))
    }
}
