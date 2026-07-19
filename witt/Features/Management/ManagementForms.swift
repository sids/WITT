import SwiftUI
import UIKit

struct ThingSavedView: View {
    let thing: ThingSnapshot
    let location: String
    let onAction: (ThingPostSaveAction) -> Void

    var body: some View {
        List {
            Section {
                LabeledContent {
                    Text(thing.name)
                } label: {
                    Label("Thing Saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
                Label(location, systemImage: "location")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Add Another Here", systemImage: "plus") {
                    onAction(.addAnotherHere)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("thingSaved.addAnother")

                Button("Scan Next", systemImage: "qrcode.viewfinder") {
                    onAction(.scanNext)
                }
                Button("View Thing", systemImage: "shippingbox") {
                    onAction(.viewThing)
                }
                Button("Done", systemImage: "checkmark") {
                    onAction(.done)
                }
            }
        }
        .navigationTitle("Thing Saved")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("thingSaved.confirmation")
    }
}

private struct ManagementPhotoSection: View {
    let existingThumbnailData: Data?
    @Binding var selection: ManagementPhotoSelection
    var onReplacement: (NormalizedPhoto) -> Void = { _ in }
    var onRemove: () -> Void = {}

    @State private var showsCamera = false
    @State private var errorMessage: String?

    private var displayedData: Data? {
        switch selection {
        case .replacement(let photo): photo.thumbnailJPEGData
        case .unchanged: existingThumbnailData
        case .removed: nil
        }
    }

    private var canRemove: Bool {
        displayedData != nil
    }

    var body: some View {
        Section("Photo") {
            if let displayedData, let image = UIImage(data: displayedData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 240)
                    .clipShape(.rect(cornerRadius: 6))
                    .accessibilityLabel("Selected photo")
            }

            Button {
                showsCamera = true
            } label: {
                Label("Take Photo", systemImage: "camera")
            }

            PhotoLibraryPicker { photo in
                accept(photo)
            } onError: { error in
                errorMessage = error.localizedDescription
            } label: {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
            }

            if canRemove {
                Button("Remove Photo", systemImage: "trash", role: .destructive) {
                    selection = .removed
                    onRemove()
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraCaptureView {
                showsCamera = false
            } onResult: { photo in
                showsCamera = false
                accept(photo)
            } onError: { error in
                showsCamera = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func accept(_ photo: NormalizedPhoto) {
        selection = .replacement(photo)
        errorMessage = nil
        onReplacement(photo)
    }
}

private struct ArchiveActionSection: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Section {
            Button(title, role: .destructive, action: action)
                .accessibilityIdentifier("management.archive")
        }
    }
}

private struct DraftQRCodeSection: View {
    let hasSelection: Bool
    let onScan: () -> Void

    var body: some View {
        Section("QR Code") {
            if hasSelection {
                Label("QR Code Ready", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
            Button(
                hasSelection ? "Scan Different QR Code" : "Scan QR Code",
                systemImage: "qrcode.viewfinder",
                action: onScan
            )
        }
    }
}

struct PlaceManagementForm: View {
    @ObservedObject var store: CatalogStore
    let placeID: UUID?
    @Binding var isSaving: Bool
    var onCreated: (PlaceSnapshot) -> Void = { _ in }
    let onFinished: () -> Void
    @State private var values = ManagementFormValues()
    @State private var photo: ManagementPhotoSelection = .unchanged
    @State private var initialized = false
    @State private var confirmsArchive = false
    @FocusState private var isNameFocused: Bool

    private var place: PlaceSnapshot? { placeID.flatMap(store.place(id:)) }
    private var isAvailable: Bool {
        guard let placeID else { return true }
        return store.activePlaces.contains { $0.id == placeID }
    }

    var body: some View {
        Group {
            if isAvailable {
                Form {
                    Section("Place") {
                        TextField("Name", text: $values.name)
                            .focused($isNameFocused)
                        TextField("Notes", text: $values.notes, axis: .vertical)
                    }
                    ManagementPhotoSection(
                        existingThumbnailData: place?.primaryPhoto?.thumbnailData
                            ?? place?.primaryPhoto?.data,
                        selection: $photo
                    )
                    if placeID != nil {
                        ArchiveActionSection(title: "Archive Place") {
                            confirmsArchive = true
                        }
                    }
                }
                .disabled(isSaving)
            } else {
                unavailable("Place")
            }
        }
        .navigationTitle(placeID == nil ? "Add Place" : "Edit Place")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            editorToolbar(
                save: save,
                disabled: values.normalizedName.isEmpty || isSaving,
                isCommitting: $isSaving
            )
        }
        .task {
            initialize()
            guard placeID == nil else { return }
            await Task.yield()
            isNameFocused = true
        }
        .confirmationDialog("Archive Place?", isPresented: $confirmsArchive, titleVisibility: .visible) {
            Button("Archive Place", role: .destructive) { beginArchive() }
        } message: {
            Text(placeArchiveFacts.message)
        }
    }

    private var placeArchiveFacts: ManagementArchiveFacts {
        guard let place else { return ManagementArchiveFacts(.empty) }
        return ManagementArchiveFacts(
            ArchiveImpactSummary(
                storageAreaCount: place.activeAreas.count,
                containerCount: place.activeContainers.count,
                thingCount: place.activeThings.count,
                containsBoundQRCode: place.activeAreas.contains(where: \.hasQRCode)
                    || place.activeContainers.contains(where: \.hasQRCode)
            ),
            roomCount: place.activeRooms.count
        )
    }

    private func initialize() {
        guard !initialized else { return }
        initialized = true
        guard let place else { return }
        values.name = place.name
        values.notes = place.notes ?? ""
    }

    private func save() async {
        let result: PlaceSnapshot?
        if let placeID {
            result = await store.updatePlace(
                id: placeID,
                with: UpdatePlaceDraft(
                    name: values.normalizedName, notes: values.normalizedNotes, photo: photo.updateMutation
                ))
        } else {
            result = await store.createPlace(
                CreatePlaceDraft(
                    name: values.normalizedName, notes: values.normalizedNotes, photo: photo.createPhoto
                ))
        }
        isSaving = false
        if let result {
            if placeID == nil { onCreated(result) }
            onFinished()
        }
    }

    private func archive() async {
        guard let placeID else {
            isSaving = false
            return
        }
        let result = await store.archivePlace(id: placeID)
        isSaving = false
        if result != nil { onFinished() }
    }

    private func beginArchive() {
        guard !isSaving else { return }
        isSaving = true
        Task { await archive() }
    }
}

struct RoomManagementForm: View {
    @ObservedObject var store: CatalogStore
    let roomID: UUID?
    let contextPlaceID: UUID?
    @Binding var isSaving: Bool
    let onFinished: () -> Void
    @State private var name = ""
    @State private var selectedPlaceID: UUID?
    @State private var initialized = false
    @State private var confirmsArchive = false
    @FocusState private var isNameFocused: Bool

    private var room: RoomSnapshot? { roomID.flatMap(store.room(id:)) }
    private var place: PlaceSnapshot? { room.flatMap(store.place(containing:)) }
    private var places: [PlaceSnapshot] { store.activePlaces }
    private var isAvailable: Bool {
        guard let roomID, let place else { return self.roomID == nil }
        return place.activeRooms.contains { $0.id == roomID }
    }

    private var hasValidPlaceSelection: Bool {
        selectedPlaceID.map { id in places.contains { $0.id == id } } == true
    }

    var body: some View {
        Group {
            if isAvailable {
                Form {
                    Section("Room") {
                        TextField("Name", text: $name)
                            .focused($isNameFocused)
                    }
                    Section("Place") {
                        if let place {
                            Label(place.name, systemImage: "house")
                        } else {
                            Picker("Place", selection: $selectedPlaceID) { optionalPlaceOptions }
                        }
                    }
                    if roomID != nil {
                        ArchiveActionSection(title: "Archive Room") {
                            confirmsArchive = true
                        }
                    }
                }
                .disabled(isSaving)
            } else {
                unavailable("Room")
            }
        }
        .navigationTitle(roomID == nil ? "Add Room" : "Edit Room")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            editorToolbar(
                save: save,
                disabled: normalizedName.isEmpty || !hasValidPlaceSelection || isSaving,
                isCommitting: $isSaving
            )
        }
        .task {
            initialize()
            guard roomID == nil else { return }
            await Task.yield()
            isNameFocused = true
        }
        .onChange(of: places.map(\.id)) { _, _ in reconcileSelectedPlace() }
        .confirmationDialog("Archive Room?", isPresented: $confirmsArchive, titleVisibility: .visible) {
            Button("Archive Room", role: .destructive) { beginArchive() }
        } message: {
            Text(archiveFacts.message)
        }
    }

    @ViewBuilder private var optionalPlaceOptions: some View {
        ForEach(places) { place in Text(place.name).tag(Optional(place.id)) }
    }

    private var normalizedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var archiveFacts: ManagementArchiveFacts {
        guard let place, let roomID else { return ManagementArchiveFacts(.empty) }
        return ManagementArchiveFacts(place.archiveImpact(forRoomID: roomID))
    }

    private func initialize() {
        guard !initialized else { return }
        initialized = true
        name = room?.name ?? ""
        selectedPlaceID =
            room?.placeID ?? ManagementPreselection.place(context: contextPlaceID, places: places)
    }

    private func reconcileSelectedPlace() {
        selectedPlaceID = ManagementPreselection.place(context: selectedPlaceID, places: places)
    }

    private func save() async {
        let result: RoomSnapshot?
        if let roomID {
            result = await store.updateRoom(id: roomID, with: UpdateRoomDraft(name: normalizedName))
        } else if let selectedPlaceID {
            result = await store.createRoom(
                CreateRoomDraft(placeID: selectedPlaceID, name: normalizedName))
        } else {
            result = nil
        }
        isSaving = false
        if result != nil { onFinished() }
    }

    private func archive() async {
        guard let roomID else {
            isSaving = false
            return
        }
        let result = await store.archiveRoom(id: roomID)
        isSaving = false
        if result != nil { onFinished() }
    }

    private func beginArchive() {
        guard !isSaving else { return }
        isSaving = true
        Task { await archive() }
    }
}

struct AreaManagementForm: View {
    @ObservedObject var store: CatalogStore
    let areaID: UUID?
    let contextRoomID: UUID?
    @Binding var isSaving: Bool
    let onFinished: () -> Void
    @State private var values = ManagementFormValues()
    @State private var selectedRoomID: UUID?
    @State private var photo: ManagementPhotoSelection = .unchanged
    @State private var initialized = false
    @State private var confirmsArchive = false
    @State private var selectedQRToken: QRToken?
    @State private var showsQRScanner = false
    @FocusState private var isNameFocused: Bool

    private var area: AreaSnapshot? { areaID.flatMap(store.area(id:)) }
    private var place: PlaceSnapshot? { area.flatMap(store.place(containing:)) }
    private var rooms: [RoomSnapshot] {
        areaID == nil ? store.activePlaces.flatMap(\.activeRooms) : (place?.activeRooms ?? [])
    }
    private var isAvailable: Bool {
        areaID == nil
            || (area?.archivedAt == nil
                && place?.activeAreas.contains(where: { $0.id == areaID }) == true)
    }
    private var hasValidRoomSelection: Bool {
        selectedRoomID.map { id in rooms.contains { $0.id == id } } == true
    }

    var body: some View {
        Group {
            if isAvailable {
                Form {
                    Section("Storage Area") {
                        TextField("Name", text: $values.name)
                            .focused($isNameFocused)
                        Picker("Room", selection: $selectedRoomID) {
                            ForEach(rooms) { room in
                                Text(roomLabel(room)).tag(Optional(room.id))
                            }
                        }
                        TextField("Details", text: $values.detail, axis: .vertical)
                    }
                    ManagementPhotoSection(
                        existingThumbnailData: area?.primaryPhoto?.thumbnailData ?? area?.primaryPhoto?.data,
                        selection: $photo
                    )
                    if areaID == nil {
                        DraftQRCodeSection(hasSelection: selectedQRToken != nil) {
                            isNameFocused = false
                            showsQRScanner = true
                        }
                    }
                    if areaID != nil {
                        ArchiveActionSection(title: "Archive Storage Area") {
                            confirmsArchive = true
                        }
                    }
                }
                .disabled(isSaving)
            } else {
                unavailable("Storage Area")
            }
        }
        .navigationTitle(areaID == nil ? "Add Storage Area" : "Edit Storage Area")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            editorToolbar(
                save: save,
                disabled: values.normalizedName.isEmpty || !hasValidRoomSelection || isSaving,
                isCommitting: $isSaving
            )
        }
        .task {
            initialize()
            guard areaID == nil else { return }
            await Task.yield()
            isNameFocused = true
        }
        .onChange(of: rooms.map(\.id)) { _, _ in reconcileSelectedRoom() }
        .fullScreenCover(isPresented: $showsQRScanner) {
            QRAssignmentScanner(store: store, expectedTarget: nil) { token in
                selectedQRToken = token
            }
        }
        .confirmationDialog(
            "Archive Storage Area?", isPresented: $confirmsArchive, titleVisibility: .visible
        ) {
            Button("Archive Storage Area", role: .destructive) { beginArchive() }
        } message: {
            Text(archiveFacts.message)
        }
    }

    private func roomLabel(_ room: RoomSnapshot) -> String {
        areaID == nil ? "\(store.place(id: room.placeID)?.name ?? "Place") · \(room.name)" : room.name
    }

    private var archiveFacts: ManagementArchiveFacts {
        guard let place, let areaID else { return ManagementArchiveFacts(.empty) }
        return ManagementArchiveFacts(place.archiveImpact(forAreaID: areaID))
    }

    private func initialize() {
        guard !initialized else { return }
        initialized = true
        values.name = area?.name ?? ""
        values.detail = area?.detail ?? ""
        selectedRoomID =
            area?.roomID ?? ManagementPreselection.room(context: contextRoomID, rooms: rooms)
    }

    private func reconcileSelectedRoom() {
        selectedRoomID = ManagementPreselection.room(context: selectedRoomID, rooms: rooms)
    }

    private func save() async {
        guard let selectedRoomID, hasValidRoomSelection else {
            isSaving = false
            return
        }
        let result: AreaSnapshot?
        if let areaID {
            result = await store.updateArea(
                id: areaID,
                with: UpdateAreaDraft(
                    name: values.normalizedName, detail: values.normalizedDetail, roomID: selectedRoomID,
                    photo: photo.updateMutation))
        } else {
            result = await store.createArea(
                CreateAreaDraft(
                    roomID: selectedRoomID, name: values.normalizedName, detail: values.normalizedDetail,
                    photo: photo.createPhoto, qrToken: selectedQRToken))
        }
        isSaving = false
        if result != nil { onFinished() }
    }

    private func archive() async {
        guard let areaID else {
            isSaving = false
            return
        }
        let result = await store.archiveArea(id: areaID)
        isSaving = false
        if result != nil { onFinished() }
    }

    private func beginArchive() {
        guard !isSaving else { return }
        isSaving = true
        Task { await archive() }
    }
}

struct ContainerManagementForm: View {
    @ObservedObject var store: CatalogStore
    let containerID: UUID?
    let contextDestination: ContainerDestination?
    @Binding var isSaving: Bool
    let onFinished: () -> Void
    @State private var values = ManagementFormValues()
    @State private var destination: ContainerDestination?
    @State private var photo: ManagementPhotoSelection = .unchanged
    @State private var initialized = false
    @State private var confirmsArchive = false
    @State private var selectedQRToken: QRToken?
    @State private var showsQRScanner = false
    @FocusState private var isNameFocused: Bool

    private var container: ContainerSnapshot? { containerID.flatMap(store.container(id:)) }
    private var place: PlaceSnapshot? { container.flatMap(store.place(containing:)) }
    private var options: [ContainerParentOption] {
        store.containerParentOptions(editing: containerID)
    }
    private var isAvailable: Bool {
        containerID == nil || place?.activeContainers.contains(where: { $0.id == containerID }) == true
    }
    private var hasValidDestination: Bool {
        destination.map { selected in options.contains { $0.destination == selected } } == true
    }

    var body: some View {
        Group {
            if isAvailable {
                Form {
                    Section("Container") {
                        TextField("Name", text: $values.name)
                            .focused($isNameFocused)
                        Picker("Parent", selection: $destination) {
                            ForEach(options) { option in
                                Text(option.displayPath).tag(Optional(option.destination))
                            }
                        }
                        TextField("Details", text: $values.detail, axis: .vertical)
                    }
                    ManagementPhotoSection(
                        existingThumbnailData: container?.primaryPhoto?.thumbnailData
                            ?? container?.primaryPhoto?.data,
                        selection: $photo
                    )
                    if containerID == nil {
                        DraftQRCodeSection(hasSelection: selectedQRToken != nil) {
                            isNameFocused = false
                            showsQRScanner = true
                        }
                    }
                    if containerID != nil {
                        ArchiveActionSection(title: "Archive Container") {
                            confirmsArchive = true
                        }
                    }
                }
                .disabled(isSaving)
            } else {
                unavailable("Container")
            }
        }
        .navigationTitle(containerID == nil ? "Add Container" : "Edit Container")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            editorToolbar(
                save: save,
                disabled: values.normalizedName.isEmpty || !hasValidDestination || isSaving,
                isCommitting: $isSaving
            )
        }
        .task {
            initialize()
            guard containerID == nil else { return }
            await Task.yield()
            isNameFocused = true
        }
        .onChange(of: options.map(\.destination)) { _, _ in reconcileDestination() }
        .fullScreenCover(isPresented: $showsQRScanner) {
            QRAssignmentScanner(store: store, expectedTarget: nil) { token in
                selectedQRToken = token
            }
        }
        .confirmationDialog(
            "Archive Container?", isPresented: $confirmsArchive, titleVisibility: .visible
        ) {
            Button("Archive Container", role: .destructive) { beginArchive() }
        } message: {
            Text(archiveFacts.message)
        }
    }

    private func initialize() {
        guard !initialized else { return }
        initialized = true
        values.name = container?.name ?? ""
        values.detail = container?.detail ?? ""
        destination =
            container.map { ContainerDestination(parent: $0.parent) }
            ?? ManagementPreselection.containerDestination(context: contextDestination, options: options)
    }

    private var archiveFacts: ManagementArchiveFacts {
        guard let place, let containerID else { return ManagementArchiveFacts(.empty) }
        return ManagementArchiveFacts(place.archiveImpact(forContainerID: containerID))
    }

    private func reconcileDestination() {
        destination = ManagementPreselection.containerDestination(
            context: destination, options: options)
    }

    private func save() async {
        guard let destination, hasValidDestination else {
            isSaving = false
            return
        }
        let result: ContainerSnapshot?
        if let containerID {
            result = await store.updateContainer(
                id: containerID,
                with: UpdateContainerDraft(
                    name: values.normalizedName, detail: values.normalizedDetail, destination: destination,
                    photo: photo.updateMutation))
        } else {
            result = await store.createContainer(
                CreateContainerDraft(
                    name: values.normalizedName, detail: values.normalizedDetail, destination: destination,
                    photo: photo.createPhoto, qrToken: selectedQRToken))
        }
        isSaving = false
        if result != nil { onFinished() }
    }

    private func archive() async {
        guard let containerID else {
            isSaving = false
            return
        }
        let result = await store.archiveContainer(id: containerID)
        isSaving = false
        if result != nil { onFinished() }
    }

    private func beginArchive() {
        guard !isSaving else { return }
        isSaving = true
        Task { await archive() }
    }
}

struct ThingManagementForm: View {
    @ObservedObject var store: CatalogStore
    let thingID: UUID?
    let contextDestination: ThingDestination?
    @Binding var isSaving: Bool
    let onCreated: (ThingSnapshot) -> Void
    let onFinished: () -> Void
    @Environment(\.thingPhotoLabelingService) private var labelingService
    @State private var form = AIAssistedThingFormState()
    @State private var destination: ThingDestination?
    @State private var photo: ManagementPhotoSelection = .unchanged
    @State private var initialized = false
    @State private var confirmsArchive = false
    @FocusState private var isNameFocused: Bool

    private var thing: ThingSnapshot? { thingID.flatMap(store.thing(id:)) }
    private var place: PlaceSnapshot? { thing.flatMap(store.place(containing:)) }
    private var options: [ThingDestinationOption] {
        thingID.map(store.thingDestinationOptions(editing:)) ?? store.thingDestinationOptions
    }
    private var isAvailable: Bool {
        thingID == nil || place?.activeThings.contains(where: { $0.id == thingID }) == true
    }
    private var hasValidDestination: Bool {
        destination.map { selected in options.contains { $0.destination == selected } } == true
    }

    var body: some View {
        Group {
            if isAvailable {
                Form {
                    if form.isAnalyzing {
                        Section { ProgressView("Analyzing photo") }
                    } else if let analysisError = form.analysisError {
                        Section {
                            Label(analysisError, systemImage: "exclamationmark.triangle").foregroundStyle(
                                .secondary)
                        }
                    }
                    Section("Thing") {
                        TextField("Name", text: nameBinding)
                            .focused($isNameFocused)
                        TextField("Keywords", text: keywordsBinding, axis: .vertical)
                            .textInputAutocapitalization(.never)
                        TextField("Notes", text: notesBinding, axis: .vertical)
                        Picker("Location", selection: $destination) {
                            ForEach(options) { option in
                                Text(option.displayPath).tag(Optional(option.destination))
                            }
                        }
                    }
                    ManagementPhotoSection(
                        existingThumbnailData: thing?.primaryPhoto?.thumbnailData
                            ?? thing?.primaryPhoto?.data,
                        selection: $photo,
                        onReplacement: beginAnalysisIfNeeded,
                        onRemove: discardCurrentAISuggestions
                    )
                    if thingID != nil {
                        ArchiveActionSection(title: "Archive Thing") {
                            confirmsArchive = true
                        }
                    }
                }
                .disabled(isSaving)
            } else {
                unavailable("Thing")
            }
        }
        .navigationTitle(thingID == nil ? "Add Thing" : "Edit Thing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            editorToolbar(
                save: save,
                disabled: form.values.normalizedName.isEmpty || !hasValidDestination || isSaving,
                isCommitting: $isSaving
            )
        }
        .task {
            initialize()
            guard thingID == nil else { return }
            await Task.yield()
            isNameFocused = true
        }
        .onChange(of: options.map(\.destination)) { _, _ in reconcileDestination() }
        .onDisappear { invalidateAnalysis() }
        .confirmationDialog("Archive Thing?", isPresented: $confirmsArchive, titleVisibility: .visible) {
            Button("Archive Thing", role: .destructive) { beginArchive() }
        } message: {
            Text("This preserves the Thing but removes it from the active catalog.")
        }
    }

    private func initialize() {
        guard !initialized else { return }
        initialized = true
        form.values.name = thing?.name ?? ""
        form.values.notes = thing?.notes ?? ""
        form.values.keywords = thing?.keywords.joined(separator: ", ") ?? ""
        destination =
            thing.map { ThingDestination(home: $0.home) }
            ?? ManagementPreselection.thingDestination(context: contextDestination, options: options)
    }

    private func reconcileDestination() {
        destination = ManagementPreselection.thingDestination(context: destination, options: options)
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

    private func beginAnalysisIfNeeded(_ selected: NormalizedPhoto) {
        guard thingID == nil else { return }
        let requestID = form.beginAnalysis(discardingAppliedValues: true)
        Task { await analyze(selected, requestID: requestID) }
    }

    @MainActor private func analyze(_ selected: NormalizedPhoto, requestID: UUID) async {
        do {
            let suggestion = try await labelingService.suggestLabel(for: selected.photoInput)
            form.apply(suggestion, requestID: requestID)
        } catch {
            form.fail(
                requestID: requestID,
                message: "AI labeling is unavailable. Enter the details manually."
            )
        }
    }

    private func discardCurrentAISuggestions() {
        form.discardCurrentSuggestions()
    }

    private func invalidateAnalysis() {
        form.invalidateAnalysis()
    }

    private func save() async {
        invalidateAnalysis()
        guard let destination, hasValidDestination else {
            isSaving = false
            return
        }
        if let thingID {
            let succeeded =
                await store.updateThing(
                    id: thingID,
                    with: UpdateThingDraft(
                        name: form.values.normalizedName,
                        keywords: form.values.parsedKeywords,
                        notes: form.values.normalizedNotes,
                        destination: destination,
                        photo: photo.updateMutation))
                != nil
            isSaving = false
            if succeeded { onFinished() }
        } else {
            let saved = await store.saveThing(
                name: form.values.normalizedName,
                keywords: form.values.parsedKeywords,
                notes: form.values.normalizedNotes ?? "",
                photo: photo.createPhoto,
                to: destination,
                nameSource: form.nameWasAISupplied ? "ai-reviewed" : "user")
            isSaving = false
            if let saved { onCreated(saved) }
        }
    }

    private func archive() async {
        guard let thingID else {
            isSaving = false
            return
        }
        let result = await store.archiveThing(id: thingID)
        isSaving = false
        if result != nil { onFinished() }
    }

    private func beginArchive() {
        guard !isSaving else { return }
        isSaving = true
        Task { await archive() }
    }
}

@ToolbarContentBuilder
private func editorToolbar(
    save: @escaping () async -> Void,
    disabled: Bool,
    isCommitting: Binding<Bool>
) -> some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
        DismissButton(disabled: isCommitting.wrappedValue)
    }
    ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
            guard !isCommitting.wrappedValue else { return }
            isCommitting.wrappedValue = true
            Task { await save() }
        }
        .disabled(disabled)
        .accessibilityIdentifier("management.save")
    }
}

private struct DismissButton: View {
    @Environment(\.dismiss) private var dismiss
    let disabled: Bool

    var body: some View {
        Button("Cancel") { dismiss() }
            .disabled(disabled)
    }
}

private func unavailable(_ item: String) -> some View {
    ContentUnavailableView(
        "\(item) Unavailable",
        systemImage: "archivebox",
        description: Text("It may have been archived or removed by another participant.")
    )
}
