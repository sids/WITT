import Foundation
import SwiftUI

enum ScanDemo: String, Identifiable {
    case known
    case unknown
    case review

    var id: String { rawValue }
}

struct ScanLauncherView: View {
    let onScan: (ScanDemo) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Demo Scans") {
                    Button {
                        onScan(.known)
                    } label: {
                        Label("Known QR Code", systemImage: "qrcode.viewfinder")
                    }
                    .accessibilityLabel("Scan a known QR code")
                    .accessibilityIdentifier("scan.known")

                    Button {
                        onScan(.unknown)
                    } label: {
                        Label("Unknown QR Code", systemImage: "qrcode")
                    }
                    .accessibilityLabel("Scan an unknown QR code")
                    .accessibilityIdentifier("scan.unknown")
                }
            }
            .navigationTitle("Scan")
        }
    }
}

struct CaptureThingView: View {
    let store: DemoInventoryStore
    let labelingService: any ThingPhotoLabelingService
    @State private var showsReview = false
    @Environment(\.dismiss) private var dismiss

    init(
        store: DemoInventoryStore,
        labelingService: any ThingPhotoLabelingService = MockThingPhotoLabelingService.demo
    ) {
        self.store = store
        self.labelingService = labelingService
    }

    var body: some View {
        List {
            Section {
                ContentUnavailableView(
                    "Ready for a Photo",
                    systemImage: "camera",
                    description: Text("Blue Bin · Hall Closet")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            }

            Section {
                Button {
                    showsReview = true
                } label: {
                    Label("Take Demo Photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("capture.takePhoto")
            }
        }
        .navigationTitle("Add Thing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .navigationDestination(isPresented: $showsReview) {
            ReviewThingView(store: store, labelingService: labelingService)
        }
    }
}

struct ReviewThingView: View {
    let store: DemoInventoryStore
    let labelingService: any ThingPhotoLabelingService
    @State private var name = ""
    @State private var keywords = ""
    @State private var notes = ""
    @State private var isAnalyzing = true
    @State private var analysisError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                if isAnalyzing {
                    ProgressView("Analyzing photo")
                } else if let analysisError {
                    Label(analysisError, systemImage: "exclamationmark.triangle")
                    Button("Try Again") {
                        Task { await analyzePhoto() }
                    }
                } else {
                    Label("AI suggestion ready", systemImage: "sparkles")
                        .foregroundStyle(.tint)
                }
            }
            Section("Thing") {
                TextField("Name", text: $name)
                TextField("Keywords", text: $keywords, axis: .vertical)
                TextField("Notes", text: $notes, axis: .vertical)
            }
            Section("Location") {
                LabeledContent("Container", value: "Blue Bin")
                LabeledContent("Storage Area", value: "Top Shelf")
                LabeledContent("Room", value: "Hall Closet")
            }
        }
        .navigationTitle("Review Thing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let parsedKeywords = keywords.split(separator: ",").map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    store.saveSuggestedThing(name: name, keywords: parsedKeywords, notes: notes)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("review.save")
            }
        }
        .task {
            await analyzePhoto()
        }
    }

    private func analyzePhoto() async {
        isAnalyzing = true
        analysisError = nil

        do {
            let suggestion = try await labelingService.suggestLabel(
                for: PhotoInput(
                    data: Data([0]),
                    contentType: "image/jpeg",
                    dimensions: .init(width: 1_600, height: 1_200)
                )
            )
            name = suggestion.proposedName
            keywords = suggestion.keywords.joined(separator: ", ")
            notes = suggestion.detail ?? ""
        } catch {
            analysisError = "AI labeling is unavailable. You can enter the details manually."
        }

        isAnalyzing = false
    }
}

#Preview("Known QR Capture") {
    NavigationStack {
        CaptureThingView(store: .fixture)
    }
}
