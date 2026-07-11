import SwiftUI

struct AttachQRCodeView: View {
    let store: DemoInventoryStore
    @State private var showsCreateForm = false
    @Environment(\.dismiss) private var dismiss

    private var areas: [AttachTarget] {
        store.unassignedTargets.filter { $0.kind == .area }
    }

    private var containers: [AttachTarget] {
        store.unassignedTargets.filter { $0.kind == .container }
    }

    var body: some View {
        Group {
            if areas.isEmpty && containers.isEmpty {
                CreateAndAttachView(store: store)
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
            }
        }
        .navigationTitle("Attach QR")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .navigationDestination(isPresented: $showsCreateForm) {
            CreateAndAttachView(store: store)
        }
    }

    private func targetButton(_ target: AttachTarget) -> some View {
        Button {
            store.attach(target)
            dismiss()
        } label: {
            VStack(alignment: .leading) {
                Text(target.name)
                Text(target.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("Attach QR code to \(target.name), \(target.location)")
    }
}

struct CreateAndAttachView: View {
    private enum Destination: Hashable {
        case area
        case container
    }

    let store: DemoInventoryStore
    @State private var room = "Hall Closet"
    @State private var area = "Top Shelf"
    @State private var container = "Blue Bin"
    @State private var destination: Destination = .area
    @State private var isAddingRoom = false
    @State private var isAddingArea = false
    @State private var isAddingContainer = false
    @State private var newRoom = ""
    @State private var newArea = ""
    @State private var newContainer = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Room") {
                if isAddingRoom {
                    TextField("New Room Name", text: $newRoom)
                } else {
                    Picker("Room", selection: $room) {
                        ForEach(roomNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }

                Button(isAddingRoom ? "Choose Existing Room" : "Add Room", systemImage: isAddingRoom ? "list.bullet" : "plus") {
                    isAddingRoom.toggle()
                }
            }

            Section("Storage Area") {
                if isAddingArea {
                    TextField("New Storage Area Name", text: $newArea)
                } else {
                    Picker("Storage Area", selection: $area) {
                        ForEach(areaNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }

                Button(
                    isAddingArea ? "Choose Existing Storage Area" : "Add Storage Area",
                    systemImage: isAddingArea ? "list.bullet" : "plus"
                ) {
                    isAddingArea.toggle()
                }
            }

            Section("Attach To") {
                Picker("QR Destination", selection: $destination) {
                    Text(effectiveArea).tag(Destination.area)
                    Text("Container").tag(Destination.container)
                }
                .pickerStyle(.inline)

                if destination == .container {
                    if isAddingContainer || containerNames.isEmpty {
                        TextField("New Container Name", text: $newContainer)
                    } else {
                        Picker("Container", selection: $container) {
                            ForEach(containerNames, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }

                    Button(
                        isAddingContainer ? "Choose Existing Container" : "Add Container",
                        systemImage: isAddingContainer ? "list.bullet" : "plus"
                    ) {
                        isAddingContainer.toggle()
                    }
                }
            }
        }
        .navigationTitle("Create & Attach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Attach") {
                    let targetName = destination == .container ? effectiveContainer : effectiveArea
                    store.lastAttachedTargetName = targetName
                    dismiss()
                }
                .disabled(!isValid)
                .accessibilityIdentifier("createAttach.confirm")
            }
        }
    }

    private var isValid: Bool {
        !effectiveRoom.isEmpty
            && !effectiveArea.isEmpty
            && (destination == .area || !effectiveContainer.isEmpty)
    }

    private var roomNames: [String] {
        store.places.flatMap(\.rooms).map(\.name)
    }

    private var areaNames: [String] {
        store.places.flatMap(\.rooms)
            .first { $0.name == room }?
            .areas.map(\.name) ?? []
    }

    private var containerNames: [String] {
        store.places.flatMap(\.rooms)
            .first { $0.name == room }?
            .areas.first { $0.name == area }?
            .containers.filter { !$0.hasQRCode }
            .map(\.name) ?? []
    }

    private var effectiveRoom: String {
        (isAddingRoom ? newRoom : room).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var effectiveArea: String {
        (isAddingArea ? newArea : area).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var effectiveContainer: String {
        let isNew = isAddingContainer || containerNames.isEmpty
        return (isNew ? newContainer : container)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview("Attach QR") {
    NavigationStack {
        AttachQRCodeView(store: .fixture)
    }
}

#Preview("Create and Attach") {
    NavigationStack {
        CreateAndAttachView(store: .fixture)
    }
}
