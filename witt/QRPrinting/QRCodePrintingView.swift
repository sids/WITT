import QuickLook
import SwiftUI
import UIKit

struct QRCodePrintingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var labelCount = 48
    @State private var paper: QRCodeSheetPaper = .a4
    @State private var labelStyle: QRCodeSheetLabelStyle = .codeID
    @State private var thermalConfiguration = QRCodeThermalLayoutConfiguration()
    @State private var sharedFile: SharedPDF?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Labels") {
                    Stepper(value: $labelCount, in: labelCountRange, step: labelCountStep) {
                        LabeledContent("Number of Labels", value: "\(labelCount)")
                    }
                }

                Section("Paper") {
                    Picker("Paper Size", selection: $paper) {
                        ForEach(QRCodeSheetPaper.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if paper == .thermal {
                    thermalSettingsSection
                }

                Section("Label Style") {
                    Picker("Label Style", selection: $labelStyle) {
                        ForEach(QRCodeSheetLabelStyle.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button {
                        generateAndShare()
                    } label: {
                        Label("Preview PDF", systemImage: "doc.text.magnifyingglass")
                    }
                }
            }
            .navigationTitle("Print QR Labels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: paper) { _, newPaper in
                guard newPaper != .thermal else { return }
                labelCount = min(60, max(6, Int(ceil(Double(labelCount) / 6)) * 6))
            }
        }
        .sheet(item: $sharedFile) { file in
            PDFPreview(fileURL: file.url)
                .onDisappear {
                    try? FileManager.default.removeItem(at: file.url)
                    sharedFile = nil
                }
        }
        .alert("Couldn't Create Labels", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var thermalSettingsSection: some View {
        Section("Thermal Roll") {
            Stepper(value: $thermalConfiguration.paperWidthMillimeters, in: 30...110, step: 1) {
                millimeterContent("Paper Width", value: thermalConfiguration.paperWidthMillimeters)
            }
            Stepper(value: $thermalConfiguration.columns, in: 1...4) {
                LabeledContent("QRs per Row", value: "\(thermalConfiguration.columns)")
            }
            Stepper(value: $thermalConfiguration.rowSpacingMillimeters, in: 0...20, step: 1) {
                millimeterContent("Row Spacing", value: thermalConfiguration.rowSpacingMillimeters)
            }
            Stepper(value: $thermalConfiguration.columnSpacingMillimeters, in: 0...20, step: 1) {
                millimeterContent("Column Spacing", value: thermalConfiguration.columnSpacingMillimeters)
            }
            Stepper(value: $thermalConfiguration.horizontalMarginMillimeters, in: 0...20, step: 1) {
                millimeterContent("Horizontal Margins", value: thermalConfiguration.horizontalMarginMillimeters)
            }
            Stepper(value: $thermalConfiguration.topMarginMillimeters, in: 0...20, step: 1) {
                millimeterContent("Top Margin", value: thermalConfiguration.topMarginMillimeters)
            }
            Stepper(value: $thermalConfiguration.bottomMarginMillimeters, in: 0...20, step: 1) {
                millimeterContent("Bottom Margin", value: thermalConfiguration.bottomMarginMillimeters)
            }
            LabeledContent("Estimated QR Size", value: estimatedQRCodeSize)
        }
    }

    private var labelCountRange: ClosedRange<Int> {
        paper == .thermal ? 1...120 : 6...60
    }

    private var labelCountStep: Int {
        paper == .thermal ? 1 : 6
    }

    private var estimatedQRCodeSize: String {
        guard let layout = try? QRCodeSheetLayout.thermal(configuration: thermalConfiguration) else {
            return String(localized: "Invalid Settings")
        }
        return millimeters(layout.estimatedQRCodeSideMillimeters)
    }

    private func millimeterContent(_ title: LocalizedStringKey, value: CGFloat) -> some View {
        LabeledContent(title, value: millimeters(value))
    }

    private func millimeters(_ value: CGFloat) -> String {
        let number = Double(value).formatted(.number.precision(.fractionLength(0...1)))
        return String(localized: "\(number) mm")
    }

    @MainActor
    private func generateAndShare() {
        do {
            let codes = try QRCodeSheetBatchGenerator(tokenGenerator: { try QRToken.generate() })
                .generate(count: labelCount)
            let layout = if paper == .thermal {
                try QRCodeSheetLayout.thermal(configuration: thermalConfiguration)
            } else {
                QRCodeSheetLayout(paper: paper)
            }
            let data = try QRCodeSheetPDFGenerator().generate(
                codes: codes,
                layout: layout,
                labelStyle: labelStyle
            )
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("WITT-QR-Labels-\(UUID().uuidString).pdf")
            try data.write(to: url, options: .atomic)
            sharedFile = SharedPDF(url: url)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct SharedPDF: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PDFPreview: UIViewControllerRepresentable {
    let fileURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(fileURL: fileURL)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        private let item: PreviewItem

        init(fileURL: URL) {
            item = PreviewItem(url: fileURL)
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            item
        }
    }
}

private final class PreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String? = "WITT QR Labels"

    init(url: URL) {
        previewItemURL = url
    }
}
