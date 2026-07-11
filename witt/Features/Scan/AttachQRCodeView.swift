import SwiftUI

struct AttachQRCodeView: View {
    @ObservedObject var store: CatalogStore
    let token: QRToken
    let onAttached: () -> Void

    @State private var showsCreateForm = false
    @State private var bindingTargetID: UUID?
    @State private var isLoadingTargets = true
    @Environment(\.dismiss) private var dismiss

    private var areas: [QRAttachTargetSnapshot] {
        store.unassignedQRCodeTargets.filter { $0.kind == .area }
    }

    private var containers: [QRAttachTargetSnapshot] {
        store.unassignedQRCodeTargets.filter { $0.kind == .container }
    }

    var body: some View {
        Group {
            if isLoadingTargets && areas.isEmpty && containers.isEmpty {
                ProgressView("Loading Storage Areas and Containers")
            } else if areas.isEmpty && containers.isEmpty {
                CreateAndAttachView(store: store, token: token, onAttached: onAttached)
            } else {
                List {
                    if !areas.isEmpty {
                        Section("Storage Areas without QR") {
                            ForEach(areas) { target in
                                targetButton(target)
                            }
                        }
                    }

                    if !containers.isEmpty {
                        Section("Containers without QR") {
                            ForEach(containers) { target in
                                targetButton(target)
                            }
                        }
                    }

                    Section {
                        Button {
                            showsCreateForm = true
                        } label: {
                            Label("Create & Attach", systemImage: "plus")
                        }
                        .accessibilityIdentifier("attach.create")
                    }
                }
                .refreshable { await store.loadUnassignedQRCodeTargets() }
            }
        }
        .navigationTitle("Attach QR")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .task {
            await store.loadUnassignedQRCodeTargets()
            isLoadingTargets = false
        }
        .navigationDestination(isPresented: $showsCreateForm) {
            CreateAndAttachView(store: store, token: token, onAttached: onAttached)
        }
    }

    private func targetButton(_ target: QRAttachTargetSnapshot) -> some View {
        Button {
            bindingTargetID = target.id
            Task {
                if await store.bind(token, to: target) { onAttached() }
                bindingTargetID = nil
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.name)
                    Text(target.locationComponents.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if bindingTargetID == target.id {
                    ProgressView()
                }
            }
        }
        .disabled(bindingTargetID != nil)
        .foregroundStyle(.primary)
        .accessibilityLabel(
            "Attach QR code to \(target.name), \(target.locationComponents.joined(separator: ", "))"
        )
    }
}

struct CreateAndAttachView: View {
    private enum Destination: Hashable {
        case area
        case container
    }

    @ObservedObject var store: CatalogStore
    let token: QRToken
    let onAttached: () -> Void

    @State private var selectedPlaceID: UUID?
    @State private var selectedRoomID: UUID?
    @State private var selectedAreaID: UUID?
    @State private var selectedContainerID: UUID?
    @State private var destination: Destination = .area
    @State private var isAddingRoom = false
    @State private var isAddingArea = false
    @State private var isAddingContainer = false
    @State private var newRoom = ""
    @State private var newArea = ""
    @State private var newContainer = ""
    @State private var isSaving = false

    private var place: PlaceSnapshot? {
        store.activePlaces.first { $0.id == selectedPlaceID } ?? store.activePlaces.first
    }

    private var rooms: [RoomSnapshot] {
        place?.activeRooms ?? []
    }

    private var areas: [AreaSnapshot] {
        guard let place, let selectedRoomID, !isAddingRoom else { return [] }
        return place.activeAreas(in: selectedRoomID)
    }

    private var containers: [ContainerSnapshot] {
        guard let place, let selectedAreaID, !isAddingArea else { return [] }
        return place.activeContainers(inArea: selectedAreaID).filter { !$0.hasQRCode }
    }

    private var selectedAreaHasQRCode: Bool {
        areas.first { $0.id == selectedAreaID }?.hasQRCode ?? false
    }

    var body: some View {
        Form {
            if store.activePlaces.count > 1 {
                Section("Place") {
                    Picker("Place", selection: $selectedPlaceID) {
                        ForEach(store.activePlaces) { place in
                            Text(place.name).tag(Optional(place.id))
                        }
                    }
                }
            }

            Section("Room") {
                if isAddingRoom || rooms.isEmpty {
                    TextField("New Room Name", text: $newRoom)
                } else {
                    Picker("Room", selection: $selectedRoomID) {
                        ForEach(rooms) { room in
                            Text(room.name).tag(Optional(room.id))
                        }
                    }
                }

                if !rooms.isEmpty {
                    Button(
                        isAddingRoom ? "Choose Existing Room" : "Add Room",
                        systemImage: isAddingRoom ? "list.bullet" : "plus"
                    ) {
                        isAddingRoom.toggle()
                        synchronizeSelections()
                    }
                }
            }

            Section("Storage Area") {
                if isAddingArea || areas.isEmpty {
                    TextField("New Storage Area Name", text: $newArea)
                } else {
                    Picker("Storage Area", selection: $selectedAreaID) {
                        ForEach(areas) { area in
                            Text(area.name).tag(Optional(area.id))
                        }
                    }
                }

                if !areas.isEmpty {
                    Button(
                        isAddingArea ? "Choose Existing Storage Area" : "Add Storage Area",
                        systemImage: isAddingArea ? "list.bullet" : "plus"
                    ) {
                        isAddingArea.toggle()
                        synchronizeSelections()
                    }
                }
            }

            Section("Attach To") {
                Picker("QR Destination", selection: $destination) {
                    Text("Storage Area").tag(Destination.area)
                    Text("Container").tag(Destination.container)
                }
                .pickerStyle(.segmented)

                if destination == .area && selectedAreaHasQRCode {
                    Label("This Storage Area already has a QR code.", systemImage: "qrcode")
                        .foregroundStyle(.secondary)
                }

                if destination == .container {
                    if isAddingContainer || containers.isEmpty {
                        TextField("New Container Name", text: $newContainer)
                    } else {
                        Picker("Container", selection: $selectedContainerID) {
                            ForEach(containers) { container in
                                Text(container.name).tag(Optional(container.id))
                            }
                        }
                    }

                    if !containers.isEmpty {
                        Button(
                            isAddingContainer ? "Choose Existing Container" : "Add Container",
                            systemImage: isAddingContainer ? "list.bullet" : "plus"
                        ) {
                            isAddingContainer.toggle()
                            synchronizeSelections()
                        }
                    }
                }
            }
        }
        .navigationTitle("Create & Attach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Attach") {
                    Task { await createAndAttach() }
                }
                .disabled(!isValid || isSaving)
                .accessibilityIdentifier("createAttach.confirm")
            }
        }
        .onAppear { synchronizeSelections() }
        .onChange(of: selectedPlaceID) { _, _ in synchronizeSelections() }
        .onChange(of: selectedRoomID) { _, _ in synchronizeSelections() }
        .onChange(of: selectedAreaID) { _, _ in synchronizeSelections() }
    }

    private var isValid: Bool {
        guard place != nil else { return false }
        let validRoom = isAddingRoom || rooms.isEmpty
            ? !trimmed(newRoom).isEmpty
            : selectedRoomID != nil
        let validArea = isAddingArea || areas.isEmpty
            ? !trimmed(newArea).isEmpty
            : selectedAreaID != nil
        guard validRoom, validArea else { return false }

        switch destination {
        case .area:
            return !selectedAreaHasQRCode
        case .container:
            return isAddingContainer || containers.isEmpty
                ? !trimmed(newContainer).isEmpty
                : selectedContainerID != nil
        }
    }

    private func synchronizeSelections() {
        if selectedPlaceID == nil || !store.activePlaces.contains(where: { $0.id == selectedPlaceID }) {
            selectedPlaceID = store.activePlaces.first?.id
        }

        if isAddingRoom || rooms.isEmpty {
            isAddingArea = true
            selectedRoomID = nil
        } else if selectedRoomID == nil || !rooms.contains(where: { $0.id == selectedRoomID }) {
            selectedRoomID = rooms.first?.id
        }

        if isAddingArea || areas.isEmpty {
            selectedAreaID = nil
            isAddingContainer = true
        } else if selectedAreaID == nil || !areas.contains(where: { $0.id == selectedAreaID }) {
            selectedAreaID = areas.first?.id
        }

        if selectedAreaHasQRCode { destination = .container }
        if !isAddingContainer && !containers.contains(where: { $0.id == selectedContainerID }) {
            selectedContainerID = containers.first?.id
        }
    }

    private func createAndAttach() async {
        guard let place else { return }
        let roomSelection: RoomSelection
        if isAddingRoom || rooms.isEmpty {
            roomSelection = .new(name: trimmed(newRoom))
        } else if let selectedRoomID {
            roomSelection = .existing(selectedRoomID)
        } else {
            return
        }

        let areaSelection: AreaSelection
        if isAddingArea || areas.isEmpty {
            areaSelection = .new(name: trimmed(newArea))
        } else if let selectedAreaID {
            areaSelection = .existing(selectedAreaID)
        } else {
            return
        }

        let attachment: QRCodeAttachmentSelection
        switch destination {
        case .area:
            attachment = .area
        case .container where isAddingContainer || containers.isEmpty:
            attachment = .newContainer(name: trimmed(newContainer))
        case .container:
            guard let selectedContainerID else { return }
            attachment = .existingContainer(selectedContainerID)
        }

        isSaving = true
        let saved = await store.createTargetAndBind(
            CreateAndBindQRCodeRequest(
                token: token,
                placeID: place.id,
                room: roomSelection,
                area: areaSelection,
                attachment: attachment
            )
        )
        isSaving = false
        if saved { onAttached() }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview("Attach QR") {
    let persistence = PersistenceController.inMemory()
    let store = CatalogStore(persistence: persistence)
    NavigationStack {
        AttachQRCodeView(
            store: store,
            token: try! QRToken(validating: "BBBBBBBBBBBBBBBBBBBBBA"),
            onAttached: {}
        )
    }
    .task { await store.bootstrap() }
}
