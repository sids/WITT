import Foundation
import SwiftUI
import UIKit

#if DEBUG
enum ScanDemo: String, Identifiable {
    case known
    case unknown
    case review
    case createAttach
    case repair

    var id: String { rawValue }
}
#endif

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
    @State private var repairRequest: AssignmentRepairRequest?

    var body: some View {
        NavigationStack {
            QRScannerView(isPaused: isProcessing || alert != nil || repairRequest != nil) { payload in
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
        .confirmationDialog(
            "Repair QR Code?",
            isPresented: Binding(
                get: { repairRequest != nil },
                set: { if !$0 { repairRequest = nil } }
            ),
            titleVisibility: .visible,
            presenting: repairRequest
        ) { request in
            Button("Repair and Use This Code") {
                repairAndUse(request)
            }
            .accessibilityIdentifier("qrAssignment.repairAndUse")
            Button("Scan Another", role: .cancel) {
                repairRequest = nil
                isProcessing = false
            }
            .accessibilityIdentifier("qrAssignment.scanAnother")
        } message: { request in
            Text(request.message)
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
                case .repair(let issue):
                    isProcessing = false
                    repairRequest = AssignmentRepairRequest(
                        token: token,
                        issue: issue,
                        bindsImmediately: expectedTarget != nil
                    )
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

    private func repairAndUse(_ request: AssignmentRepairRequest) {
        repairRequest = nil
        isProcessing = true
        Task {
            do {
                if let expectedTarget {
                    try await store.repairAndReplaceQRCode(
                        request.token,
                        target: expectedTarget
                    )
                } else {
                    try await store.releaseRepairableQRCode(request.token)
                    try await onAssign(request.token)
                }
                dismiss()
            } catch {
                show(.assignmentFailed)
            }
        }
    }
}

enum QRAssignmentDecision: Equatable {
    case assign
    case accept
    case alreadyAttached
    case repair(QRCodeRepairIssue)

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
        case .needsRepair(let repair):
            .repair(.unavailable(repair))
        case .conflict(let conflict):
            .repair(.conflict(conflict))
        }
    }
}

private struct AssignmentRepairRequest: Identifiable {
    let id = UUID()
    let token: QRToken
    let issue: QRCodeRepairIssue
    let bindsImmediately: Bool

    var message: String {
        if !bindsImmediately {
            return "Repairing removes the damaged attachments and returns this code to the draft. The code will be attached when the new destination is saved."
        }
        return switch issue {
        case .unavailable:
            "This code has a damaged attachment. Repairing it will release the unavailable destination and use the code here."
        case .conflict:
            "This code has conflicting attachments. Repairing it will remove those conflicts and use the code here."
        }
    }
}

private enum AssignmentAlert: String, Identifiable {
    case invalidCode
    case alreadyAttached
    case assignmentFailed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .invalidCode: "Invalid QR Code"
        case .alreadyAttached: "QR Code Already Attached"
        case .assignmentFailed: "Unable to Attach QR Code"
        }
    }

    var message: String {
        switch self {
        case .invalidCode:
            "Scan a QR code with a non-empty payload."
        case .alreadyAttached:
            "This QR code is attached to another Storage Area or Container. Scan a different code."
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

    @State private var form = AIAssistedThingFormState()
    @State private var isSaving = false

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
                        .accessibilityLabel("Selected Thing photo")
                }
            }

            Section {
                if form.isAnalyzing {
                    ProgressView("Analyzing photo")
                } else if let analysisError = form.analysisError {
                    Label(analysisError, systemImage: "exclamationmark.triangle")
                    Button("Try Again") {
                        Task { await analyzePhoto() }
                    }
                    .disabled(photo == nil)
                } else if form.analysisSucceeded {
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
                        || form.values.normalizedName.isEmpty
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
            get: { form.values.name },
            set: { newValue in
                form.markEdited(.name)
                form.values.name = newValue
            })
    }

    private var keywordsBinding: Binding<String> {
        Binding(
            get: { form.values.keywords },
            set: { newValue in
                form.markEdited(.keywords)
                form.values.keywords = newValue
            })
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { form.values.notes },
            set: { newValue in
                form.markEdited(.notes)
                form.values.notes = newValue
            })
    }

    private func analyzePhoto() async {
        guard let photo else {
            invalidateAnalysis()
            return
        }

        let requestID = form.beginAnalysis()
        do {
            let suggestion = try await labelingService.suggestLabel(for: photo.photoInput)
            guard !Task.isCancelled else { return }
            form.apply(suggestion, requestID: requestID)
        } catch is CancellationError {
            form.cancel(requestID: requestID)
        } catch {
            guard !Task.isCancelled else { return }
            form.fail(
                requestID: requestID,
                message: "AI labeling is unavailable. You can enter the details manually."
            )
        }
    }

    private func invalidateAnalysis() {
        form.invalidateAnalysis()
    }

    private func save() async {
        invalidateAnalysis()
        isSaving = true
        let saved = await store.saveThing(
            name: form.values.normalizedName,
            keywords: form.values.parsedKeywords,
            notes: form.values.normalizedNotes ?? "",
            photo: photo,
            to: destination,
            nameSource: form.nameWasAISupplied ? "ai-reviewed" : "user"
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
