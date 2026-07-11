import QuickLook
import SwiftUI
import UIKit

struct QRCodePrintingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var labelCount = 48
    @State private var paper: QRCodeSheetPaper = .a4
    @State private var labelStyle: QRCodeSheetLabelStyle = .codeID
    @State private var sharedFile: SharedPDF?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Labels") {
                    Stepper(value: $labelCount, in: 6...60, step: 6) {
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

    @MainActor
    private func generateAndShare() {
        do {
            let codes = try QRCodeSheetBatchGenerator(tokenGenerator: { try QRToken.generate() })
                .generate(count: labelCount)
            let data = try QRCodeSheetPDFGenerator().generate(
                codes: codes,
                layout: QRCodeSheetLayout(paper: paper),
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
