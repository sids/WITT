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
        labelStyle: QRCodeSheetLabelStyle = .codeID
    ) throws -> Data {
        guard !codes.isEmpty else { throw QRCodeSheetError.invalidCount }

        let bounds = CGRect(origin: .zero, size: layout.pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        var generationError: QRCodeSheetError?

        let data = renderer.pdfData { context in
            for pageStart in stride(from: 0, to: codes.count, by: layout.codesPerPage) {
                context.beginPage()
                UIColor.white.setFill()
                context.cgContext.fill(bounds)

                let pageEnd = min(pageStart + layout.codesPerPage, codes.count)
                for absoluteIndex in pageStart..<pageEnd {
                    let pageIndex = absoluteIndex - pageStart
                    let qrFrame = layout.qrFrame(at: pageIndex)
                    guard let image = imageGenerator(codes[absoluteIndex].url.absoluteString, qrFrame.width) else {
                        generationError = .imageGenerationFailed(index: absoluteIndex)
                        return
                    }

                    let renderedSide = min(qrFrame.width, CGFloat(image.width))
                    let renderedFrame = CGRect(
                        x: qrFrame.midX - renderedSide / 2,
                        y: qrFrame.midY - renderedSide / 2,
                        width: renderedSide,
                        height: renderedSide
                    )
                    context.cgContext.interpolationQuality = .none
                    context.cgContext.draw(image, in: renderedFrame)

                    let paragraph = NSMutableParagraphStyle()
                    paragraph.alignment = .center
                    paragraph.lineBreakMode = .byClipping
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                        .foregroundColor: UIColor.black,
                        .paragraphStyle: paragraph
                    ]
                    codes[absoluteIndex].identifier.draw(
                        in: layout.identifierFrame(at: pageIndex),
                        withAttributes: attributes
                    )
                    if labelStyle == .blankLine {
                        let frame = layout.identifierFrame(at: pageIndex)
                        let lineY = frame.maxY - 1
                        context.cgContext.setStrokeColor(UIColor.black.cgColor)
                        context.cgContext.setLineWidth(0.75)
                        context.cgContext.move(to: CGPoint(x: frame.minX + 12, y: lineY))
                        context.cgContext.addLine(to: CGPoint(x: frame.maxX - 12, y: lineY))
                        context.cgContext.strokePath()
                    }
                }
            }
        }

        if let generationError { throw generationError }
        guard data.starts(with: Data("%PDF".utf8)) else {
            throw QRCodeSheetError.pdfGenerationFailed
        }
        return data
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
        let scale = max(1, floor(targetSide / padded.extent.width))
        let scaled = padded.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(scaled, from: scaled.extent)
    }
}
