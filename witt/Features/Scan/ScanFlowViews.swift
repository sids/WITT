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
    let onClose: @MainActor @Sendable () -> Void
    let onPayload: @MainActor @Sendable (String) -> Void

    var body: some View {
        NavigationStack {
            QRScannerView(isPaused: isPaused, onPayload: onPayload)
                .navigationTitle("Scan QR")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: onClose) {
                            Label("Close", systemImage: "xmark")
                        }
                        .labelStyle(.iconOnly)
                    }
                }
        }
    }
}

struct QRAssignmentScanner: View {
    @ObservedObject var store: CatalogStore
    let expectedTarget: QRBindingTarget?
    let onAssign: (QRToken) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false
    @State private var alert: AssignmentAlert?

    var body: some View {
        NavigationStack {
            QRScannerView(isPaused: isProcessing || alert != nil) { payload in
                process(payload)
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isProcessing)
                }
            }
        }
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func process(_ payload: String) {
        guard !isProcessing, alert == nil else { return }
        isProcessing = true

        Task {
            do {
                guard let token = QRToken(scannedPayload: payload) else {
                    show(.invalidCode)
                    return
                }
                let resolution = try await store.resolveQRCode(token)
                switch QRAssignmentDecision.evaluate(
                    resolution: resolution,
                    expectedTarget: expectedTarget
                ) {
                case .assign:
                    try await onAssign(token)
                    dismiss()
                case .accept:
                    dismiss()
                case .alreadyAttached:
                    show(.alreadyAttached)
                case .needsRepair:
                    show(.needsRepair)
                case .conflict:
                    show(.conflict)
                }
            } catch CatalogRepositoryError.tokenAlreadyBound {
                show(.alreadyAttached)
            } catch {
                show(.assignmentFailed)
            }
        }
    }

    private func show(_ newAlert: AssignmentAlert) {
        isProcessing = false
        alert = newAlert
    }
}

enum QRAssignmentDecision: Equatable {
    case assign
    case accept
    case alreadyAttached
    case needsRepair
    case conflict

    static func evaluate(
        resolution: QRCodeResolution,
        expectedTarget: QRBindingTarget?
    ) -> Self {
        switch resolution {
        case .unknown:
            .assign
        case .knownArea(let id):
            expectedTarget == .area(id) ? .accept : .alreadyAttached
        case .knownContainer(let id):
            expectedTarget == .container(id) ? .accept : .alreadyAttached
        case .needsRepair:
            .needsRepair
        case .conflict:
            .conflict
        }
    }
}

private enum AssignmentAlert: String, Identifiable {
    case invalidCode
    case alreadyAttached
    case needsRepair
    case conflict
    case assignmentFailed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .invalidCode: "Invalid QR Code"
        case .alreadyAttached: "QR Code Already Attached"
        case .needsRepair: "QR Code Needs Repair"
        case .conflict: "QR Code Conflict"
        case .assignmentFailed: "Unable to Attach QR Code"
        }
    }

    var message: String {
        switch self {
        case .invalidCode:
            "Scan a QR code with a non-empty payload."
        case .alreadyAttached:
            "This QR code is attached to another Storage Area or Container. Scan a different code."
        case .needsRepair:
            "This QR code has an incomplete attachment that must be repaired before it can be used."
        case .conflict:
            "This QR code has conflicting attachments that must be resolved before it can be used."
        case .assignmentFailed:
            "WITT could not attach this QR code. Try scanning it again."
        }
    }
}

struct CaptureThingView: View {
    @ObservedObject var store: CatalogStore
    let destination: ThingDestination
    let onPostSaveHandoff: (ThingPostSaveHandoff) -> Void

    @State private var photo: NormalizedPhoto?
    @State private var savedThing: ThingSnapshot?
    @State private var showsCamera = false
    @State private var showsReview = false
    @State private var hasOfferedCamera = false
    @State private var photoError: String?
    @Environment(\.dismiss) private var dismiss

    private var location: String {
        store.locationComponents(for: destination).joined(separator: " · ")
    }

    var body: some View {
        if let savedThing {
            ThingSavedView(
                thing: savedThing,
                location: store.locationComponents(for: savedThing).joined(separator: " · "),
                onAction: handlePostSaveAction
            )
        } else {
            captureContent
        }
    }

    private var captureContent: some View {
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
                onSaved: showConfirmation
            )
        }
    }

    private func showConfirmation(_ thing: ThingSnapshot) {
        showsReview = false
        savedThing = thing
    }

    private func handlePostSaveAction(_ action: ThingPostSaveAction) {
        guard let savedThing else { return }
        if action == .addAnotherHere {
            photo = nil
            photoError = nil
            self.savedThing = nil
            Task { @MainActor in
                await Task.yield()
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showsCamera = true
                }
            }
        } else if let handoff = ThingPostSaveHandoff(action: action, thingID: savedThing.id) {
            onPostSaveHandoff(handoff)
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
    let onSaved: (ThingSnapshot) -> Void
    @Environment(\.thingPhotoLabelingService) private var labelingService

    @State private var values = ManagementFormValues()
    @State private var isAnalyzing = false
    @State private var isSaving = false
    @State private var analysisSucceeded = false
    @State private var analysisError: String?
    @State private var analysisRequestID: UUID?
    @State private var editedFields: Set<ManagementAIEditableField> = []
    @State private var aiAppliedName: String?

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
                } else if analysisSucceeded {
                    Label("AI suggestion ready", systemImage: "sparkles")
                        .foregroundStyle(.tint)
                }
            }

            Section("Thing") {
                TextField("Name", text: nameBinding)
                TextField("Keywords", text: keywordsBinding, axis: .vertical)
                TextField("Notes", text: notesBinding, axis: .vertical)
            }

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
                        || values.normalizedName.isEmpty
                )
                .accessibilityIdentifier("review.save")
            }
        }
        .task(id: photo) {
            await analyzePhoto()
        }
        .onDisappear { invalidateAnalysis() }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { values.name },
            set: { newValue in
                markEdited(.name)
                values.name = newValue
            })
    }

    private var keywordsBinding: Binding<String> {
        Binding(
            get: { values.keywords },
            set: { newValue in
                markEdited(.keywords)
                values.keywords = newValue
            })
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { values.notes },
            set: { newValue in
                markEdited(.notes)
                values.notes = newValue
            })
    }

    private func markEdited(_ field: ManagementAIEditableField) {
        guard analysisRequestID != nil else { return }
        editedFields.insert(field)
    }

    private func analyzePhoto() async {
        guard let photo else {
            invalidateAnalysis()
            return
        }

        let requestID = UUID()
        analysisRequestID = requestID
        editedFields = []
        isAnalyzing = true
        analysisSucceeded = false
        analysisError = nil
        do {
            let suggestion = try await labelingService.suggestLabel(for: photo.photoInput)
            guard !Task.isCancelled, analysisRequestID == requestID else { return }
            let application = ManagementAISuggestionApplication.apply(
                suggestion,
                to: values,
                preserving: editedFields
            )
            analysisRequestID = nil
            values = application.values
            if application.suppliedName {
                aiAppliedName = values.normalizedName
            }
            analysisSucceeded = true
        } catch is CancellationError {
            guard analysisRequestID == requestID else { return }
            analysisRequestID = nil
        } catch {
            guard !Task.isCancelled, analysisRequestID == requestID else { return }
            analysisRequestID = nil
            analysisError = "AI labeling is unavailable. You can enter the details manually."
        }
        guard analysisRequestID == nil else { return }
        isAnalyzing = false
    }

    private func invalidateAnalysis() {
        analysisRequestID = nil
        isAnalyzing = false
        editedFields = []
    }

    private func save() async {
        invalidateAnalysis()
        isSaving = true
        let nameWasAISupplied = aiAppliedName.map { $0 == values.normalizedName } == true
        let saved = await store.saveThing(
            name: values.normalizedName,
            keywords: values.parsedKeywords,
            notes: values.normalizedNotes ?? "",
            photo: photo,
            to: destination,
            nameSource: nameWasAISupplied ? "ai-reviewed" : "user"
        )
        isSaving = false
        if let saved { onSaved(saved) }
    }
}

struct ReviewThingSessionView: View {
    @ObservedObject var store: CatalogStore
    let destination: ThingDestination
    let photo: NormalizedPhoto?
    let onPostSaveHandoff: (ThingPostSaveHandoff) -> Void

    @State private var savedThing: ThingSnapshot?
    @State private var sessionID = UUID()

    var body: some View {
        if let savedThing {
            ThingSavedView(
                thing: savedThing,
                location: store.locationComponents(for: savedThing).joined(separator: " · "),
                onAction: handlePostSaveAction
            )
        } else {
            ReviewThingView(
                store: store,
                destination: destination,
                photo: photo,
                onSaved: { savedThing = $0 }
            )
            .id(sessionID)
        }
    }

    private func handlePostSaveAction(_ action: ThingPostSaveAction) {
        guard let savedThing else { return }
        if action == .addAnotherHere {
            self.savedThing = nil
            sessionID = UUID()
        } else if let handoff = ThingPostSaveHandoff(action: action, thingID: savedThing.id) {
            onPostSaveHandoff(handoff)
        }
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
