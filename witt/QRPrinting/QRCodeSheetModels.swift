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
    case imageGenerationFailed(index: Int)
    case pdfGenerationFailed

    var errorDescription: String? {
        switch self {
        case .invalidCount:
            "Choose between 1 and 120 labels."
        case .duplicateToken:
            "WITT couldn't generate a unique set of codes. Please try again."
        case .imageGenerationFailed:
            "WITT couldn't render one of the QR codes. Please try again."
        case .pdfGenerationFailed:
            "WITT couldn't create the PDF. Please try again."
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

enum QRCodeSheetPaper: String, CaseIterable, Identifiable, Sendable {
    case a4
    case letter

    var id: Self { self }

    var title: String {
        switch self {
        case .a4: "A4"
        case .letter: "US Letter"
        }
    }

    var pageSize: CGSize {
        switch self {
        case .a4: CGSize(width: 595.28, height: 841.89)
        case .letter: CGSize(width: 612, height: 792)
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

struct QRCodeSheetLayout: Equatable, Sendable {
    let pageSize: CGSize
    let margin: CGFloat
    let columns: Int
    let rows: Int
    let spacing: CGFloat
    let labelHeight: CGFloat

    init(
        paper: QRCodeSheetPaper,
        margin: CGFloat = 36,
        columns: Int = 3,
        rows: Int = 4,
        spacing: CGFloat = 14,
        labelHeight: CGFloat = 18
    ) {
        pageSize = paper.pageSize
        self.margin = margin
        self.columns = columns
        self.rows = rows
        self.spacing = spacing
        self.labelHeight = labelHeight
    }

    var codesPerPage: Int { columns * rows }

    func pageCount(for codeCount: Int) -> Int {
        guard codeCount > 0 else { return 0 }
        return Int(ceil(Double(codeCount) / Double(codesPerPage)))
    }

    func cellFrame(at index: Int) -> CGRect {
        let availableWidth = pageSize.width - (2 * margin) - (CGFloat(columns - 1) * spacing)
        let availableHeight = pageSize.height - (2 * margin) - (CGFloat(rows - 1) * spacing)
        let cellSize = CGSize(width: availableWidth / CGFloat(columns), height: availableHeight / CGFloat(rows))
        let column = index % columns
        let row = (index / columns) % rows
        return CGRect(
            x: margin + CGFloat(column) * (cellSize.width + spacing),
            y: margin + CGFloat(row) * (cellSize.height + spacing),
            width: cellSize.width,
            height: cellSize.height
        )
    }

    func qrFrame(at index: Int) -> CGRect {
        let cell = cellFrame(at: index)
        let side = floor(min(cell.width - 2, cell.height - labelHeight - 10))
        return CGRect(
            x: cell.midX - side / 2,
            y: cell.minY,
            width: side,
            height: side
        )
    }

    func identifierFrame(at index: Int) -> CGRect {
        let cell = cellFrame(at: index)
        return CGRect(x: cell.minX, y: cell.maxY - labelHeight, width: cell.width, height: labelHeight)
    }
}
