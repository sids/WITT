import Foundation
import SwiftUI
import UIKit

enum ScanDemo: String, Identifiable {
    case known
    case unknown
    case review
    case createAttach

    var id: String { rawValue }
}

struct ScanView: View {
    let isPaused: Bool
    let onPayload: @MainActor @Sendable (String) -> Void

    var body: some View {
        NavigationStack {
            QRScannerView(isPaused: isPaused, onPayload: onPayload)
                .navigationTitle("Scan QR")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct CaptureThingView: View {
    @ObservedObject var store: CatalogStore
    let destination: ThingDestination
    let onSaved: () -> Void

    @State private var photo: NormalizedPhoto?
    @State private var showsCamera = false
    @State private var showsReview = false
    @State private var hasOfferedCamera = false
    @State private var photoError: String?
    @Environment(\.dismiss) private var dismiss

    private var location: String {
        store.locationComponents(for: destination).joined(separator: " · ")
    }

    var body: some View {
        List {
            Section {
                if let photo, let image = UIImage(data: photo.jpegData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 360)
                        .clipShape(.rect(cornerRadius: 6))
                } else {
                    ContentUnavailableView(
                        "Ready for a Photo",
                        systemImage: "camera",
                        description: Text(location)
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
            }

            Section {
                Button {
                    showsCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("capture.takePhoto")

                PhotoLibraryPicker { result in
                    accept(result)
                } onError: { error in
                    photoError = error.localizedDescription
                } label: {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
            }

            if let photoError {
                Section {
                    Label(photoError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Add Thing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear {
            guard !hasOfferedCamera else { return }
            hasOfferedCamera = true
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                showsCamera = true
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraCaptureView {
                showsCamera = false
            } onResult: { result in
                showsCamera = false
                accept(result)
            } onError: { error in
                photoError = error.localizedDescription
            }
        }
        .navigationDestination(isPresented: $showsReview) {
            ReviewThingView(
                store: store,
                destination: destination,
                photo: photo,
                onSaved: onSaved
            )
        }
    }

    private func accept(_ result: NormalizedPhoto) {
        photo = result
        photoError = nil
        showsReview = true
    }
}

struct ReviewThingView: View {
    @ObservedObject var store: CatalogStore
    let destination: ThingDestination
    let photo: NormalizedPhoto?
    let onSaved: () -> Void
    @Environment(\.thingPhotoLabelingService) private var labelingService

    @State private var name = ""
    @State private var keywords = ""
    @State private var notes = ""
    @State private var isAnalyzing = true
    @State private var isSaving = false
    @State private var usedAISuggestion = false
    @State private var analysisError: String?

    private var location: String {
        store.locationComponents(for: destination).joined(separator: " · ")
    }

    var body: some View {
        Form {
            if let photo, let image = UIImage(data: photo.thumbnailJPEGData) {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 260)
                        .clipShape(.rect(cornerRadius: 6))
                }
            }

            Section {
                if isAnalyzing {
                    ProgressView("Analyzing photo")
                } else if let analysisError {
                    Label(analysisError, systemImage: "exclamationmark.triangle")
                    Button("Try Again") {
                        Task { await analyzePhoto() }
                    }
                    .disabled(photo == nil)
                } else if usedAISuggestion {
                    Label("AI suggestion ready", systemImage: "sparkles")
                        .foregroundStyle(.tint)
                }
            }

            Section("Thing") {
                TextField("Name", text: $name)
                TextField("Keywords", text: $keywords, axis: .vertical)
                TextField("Notes", text: $notes, axis: .vertical)
            }
            .disabled(isAnalyzing)

            Section("Location") {
                Label(location, systemImage: "location")
            }
        }
        .navigationTitle("Review Thing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await save() }
                }
                .disabled(
                    isSaving
                        || isAnalyzing
                        || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .accessibilityIdentifier("review.save")
            }
        }
        .task(id: photo) {
            await analyzePhoto()
        }
    }

    private func analyzePhoto() async {
        guard let photo else {
            isAnalyzing = false
            return
        }

        isAnalyzing = true
        analysisError = nil
        do {
            let suggestion = try await labelingService.suggestLabel(for: photo.photoInput)
            guard !Task.isCancelled else { return }
            name = suggestion.proposedName
            keywords = suggestion.keywords.joined(separator: ", ")
            notes = suggestion.detail ?? ""
            usedAISuggestion = true
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            analysisError = "AI labeling is unavailable. You can enter the details manually."
        }
        isAnalyzing = false
    }

    private func save() async {
        isSaving = true
        let parsedKeywords = keywords.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let saved = await store.saveThing(
            name: name,
            keywords: parsedKeywords,
            notes: notes,
            photo: photo,
            to: destination,
            nameSource: usedAISuggestion ? "ai-reviewed" : "user"
        )
        isSaving = false
        if saved { onSaved() }
    }
}

#Preview("Known QR Capture") {
    let persistence = PersistenceController.inMemory()
    let store = CatalogStore(persistence: persistence)
    NavigationStack {
        ContentUnavailableView("Loading", systemImage: "camera")
    }
    .task { await store.bootstrap() }
}
