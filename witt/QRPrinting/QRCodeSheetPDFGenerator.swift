import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

@MainActor
struct QRCodeSheetPDFGenerator {
    typealias ImageGenerator = @MainActor (_ payload: String, _ targetSide: CGFloat) -> CGImage?

    private let imageGenerator: ImageGenerator

    init(imageGenerator: @escaping ImageGenerator = Self.makeQRCode) {
        self.imageGenerator = imageGenerator
    }

    func generate(
        codes: [PrintableQRCode],
        layout: QRCodeSheetLayout,
        includesWriteInLine: Bool = false
    ) throws -> Data {
        guard !codes.isEmpty else { throw QRCodeSheetError.invalidCount }

        let initialBounds = CGRect(origin: .zero, size: layout.pageSize(at: 0, codeCount: codes.count))
        let renderer = UIGraphicsPDFRenderer(bounds: initialBounds)
        var generationError: QRCodeSheetError?

        let data = renderer.pdfData { context in
            for pageStart in stride(from: 0, to: codes.count, by: layout.codesPerPage) {
                let pageIndex = pageStart / layout.codesPerPage
                let bounds = CGRect(origin: .zero, size: layout.pageSize(at: pageIndex, codeCount: codes.count))
                context.beginPage(withBounds: bounds, pageInfo: [:])
                UIColor.white.setFill()
                context.cgContext.fill(bounds)

                let pageEnd = min(pageStart + layout.codesPerPage, codes.count)
                for absoluteIndex in pageStart..<pageEnd {
                    let pageLocalIndex = absoluteIndex - pageStart
                    let labelFrame = layout.labelFrame(at: pageLocalIndex)
                    let contentLayout = layout.contentLayout(at: pageLocalIndex)
                    guard bounds.insetBy(dx: -0.5, dy: -0.5).contains(labelFrame) else {
                        generationError = .invalidGeometry
                        return
                    }
                    guard let image = imageGenerator(
                        codes[absoluteIndex].url.absoluteString,
                        contentLayout.qrFrame.width
                    ) else {
                        generationError = .imageGenerationFailed(index: absoluteIndex)
                        return
                    }

                    context.cgContext.saveGState()
                    context.cgContext.concatenate(contentLayout.transform)
                    context.cgContext.interpolationQuality = .none
                    context.cgContext.draw(image, in: contentLayout.qrFrame)

                    if let metadataFrame = contentLayout.metadataFrame {
                        drawIdentifier(
                            codes[absoluteIndex].identifier,
                            in: metadataFrame,
                            includesWriteInLine: includesWriteInLine,
                            context: context.cgContext
                        )
                    }
                    context.cgContext.restoreGState()
                }
            }
        }

        if let generationError { throw generationError }
        guard data.starts(with: Data("%PDF".utf8)) else {
            throw QRCodeSheetError.pdfGenerationFailed
        }
        return data
    }

    private func drawIdentifier(
        _ identifier: String,
        in metadataFrame: CGRect,
        includesWriteInLine: Bool,
        context: CGContext
    ) {
        let horizontalInset = min(4, metadataFrame.width * 0.06)
        let contentFrame = metadataFrame.insetBy(dx: horizontalInset, dy: 0)
        let maximumFontSize = contentFrame.width / (CGFloat(max(identifier.count, 1)) * 0.62)
        let font = UIFont.monospacedSystemFont(
            ofSize: min(10, max(6, maximumFontSize)),
            weight: .medium
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph,
        ]
        let identifierY = includesWriteInLine
            ? metadataFrame.minY + max(2, metadataFrame.height * 0.08)
            : metadataFrame.midY - (font.lineHeight / 2)
        identifier.draw(
            in: CGRect(
                x: contentFrame.minX,
                y: identifierY,
                width: contentFrame.width,
                height: font.lineHeight + 1
            ),
            withAttributes: attributes
        )

        guard includesWriteInLine else { return }
        let lineY = metadataFrame.maxY - max(5, metadataFrame.height * 0.2)
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(0.75)
        context.move(to: CGPoint(x: contentFrame.minX, y: lineY))
        context.addLine(to: CGPoint(x: contentFrame.maxX, y: lineY))
        context.strokePath()
    }

    static func makeQRCode(payload: String, targetSide: CGFloat) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        // Four modules of white quiet zone are required around a QR symbol.
        let quietZone: CGFloat = 4
        let paddedExtent = CGRect(
            x: 0,
            y: 0,
            width: output.extent.width + (quietZone * 2),
            height: output.extent.height + (quietZone * 2)
        )
        let padded = output
            .transformed(by: CGAffineTransform(translationX: quietZone, y: quietZone))
            .composited(over: CIImage(color: .white).cropped(to: paddedExtent))
        let targetPixels = targetSide * 4
        let scale = max(1, floor(targetPixels / padded.extent.width))
        let scaled = padded.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(scaled, from: scaled.extent)
    }
}
