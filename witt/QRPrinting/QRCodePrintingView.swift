import QuickLook
import SwiftUI
import UIKit

struct QRCodePrintingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var labelCount = 48
    @State private var configuration = QRCodeSheetConfiguration()
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
                    Picker("Paper Size", selection: $configuration.paper) {
                        ForEach(QRCodeSheetPaper.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    if configuration.paper == .custom {
                        Picker("Length", selection: $configuration.customPaperLength) {
                            ForEach(QRCodePaperLength.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)

                        millimeterField(
                            "Paper Width",
                            value: $configuration.customPaperWidthMillimeters
                        )
                        if configuration.customPaperLength == .fixed {
                            millimeterField(
                                "Paper Height",
                                value: $configuration.customPaperHeightMillimeters
                            )
                        }
                    } else if let size = configuration.paper.fixedSizeMillimeters {
                        LabeledContent(
                            "Dimensions",
                            value: millimeterDimensions(width: size.width, height: size.height)
                        )
                    }
                }

                marginsSection
                labelsSection

                if !isSquareLabelSelection {
                    Section("Rectangular Labels") {
                        Toggle("Write-In Line", isOn: $configuration.includesWriteInLine)
                    }
                }

                Section {
                    Button {
                        generateAndShare()
                    } label: {
                        Label("Preview PDF", systemImage: "doc.text.magnifyingglass")
                    }
                    .disabled(configuredLayout == nil)
                }
            }
            .navigationTitle("Print QR Labels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
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

    private var marginsSection: some View {
        Section("Paper Margins") {
            millimeterField("Left", value: $configuration.leftMarginMillimeters)
            millimeterField("Right", value: $configuration.rightMarginMillimeters)
            millimeterField("Top", value: $configuration.topMarginMillimeters)
            millimeterField("Bottom", value: $configuration.bottomMarginMillimeters)
        }
    }

    private var labelsSection: some View {
        Section("Label Layout") {
            millimeterField("Label Width", value: $configuration.labelWidthMillimeters)
            millimeterField("Label Height", value: $configuration.labelHeightMillimeters)
            millimeterField("Horizontal Gap", value: $configuration.horizontalSpacingMillimeters)
            millimeterField("Vertical Gap", value: $configuration.verticalSpacingMillimeters)

            if let layout = configuredLayout {
                LabeledContent("Labels per Row", value: "\(layout.columns)")
                if configuration.usesUnlimitedLength {
                    LabeledContent(
                        "Output Length",
                        value: pointsAsMillimeters(
                            layout.pageSize(at: 0, codeCount: labelCount).height
                        )
                    )
                } else {
                    LabeledContent("Labels per Page", value: "\(layout.codesPerPage)")
                }
                LabeledContent("QR Size", value: pointsAsMillimeters(layout.qrSide))
            } else if let layoutErrorMessage {
                Text(layoutErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var labelCountRange: ClosedRange<Int> { 1...120 }

    private var labelCountStep: Int { 1 }

    private var configuredLayout: QRCodeSheetLayout? {
        try? QRCodeSheetLayout(configuration: configuration)
    }

    private var layoutErrorMessage: String? {
        do {
            _ = try QRCodeSheetLayout(configuration: configuration)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var isSquareLabelSelection: Bool {
        abs(configuration.labelWidthMillimeters - configuration.labelHeightMillimeters) <= 0.1
    }

    private func millimeterField(
        _ title: LocalizedStringKey,
        value: Binding<CGFloat>
    ) -> some View {
        let numericValue = Binding<Double>(
            get: { Double(value.wrappedValue) },
            set: { value.wrappedValue = CGFloat($0) }
        )

        return LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(
                    "",
                    value: numericValue,
                    format: .number.precision(.fractionLength(0...1))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 72)
                .accessibilityLabel(title)
                Text("mm")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    private func pointsAsMillimeters(_ value: CGFloat) -> String {
        formattedMillimeters(PDFMeasurement.millimeters(fromPoints: value))
    }

    private func formattedMillimeters(_ value: CGFloat) -> String {
        let number = Double(value).formatted(.number.precision(.fractionLength(0...1)))
        return String(localized: "\(number) mm")
    }

    private func millimeterDimensions(width: CGFloat, height: CGFloat) -> String {
        let formattedWidth = Double(width).formatted(.number.precision(.fractionLength(0...1)))
        let formattedHeight = Double(height).formatted(.number.precision(.fractionLength(0...1)))
        return String(localized: "\(formattedWidth) × \(formattedHeight) mm")
    }

    @MainActor
    private func generateAndShare() {
        do {
            let codes = try QRCodeSheetBatchGenerator(tokenGenerator: { try QRToken.generate() })
                .generate(count: labelCount)
            let layout = try QRCodeSheetLayout(configuration: configuration)
            let data = try QRCodeSheetPDFGenerator().generate(
                codes: codes,
                layout: layout,
                includesWriteInLine: configuration.includesWriteInLine
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
