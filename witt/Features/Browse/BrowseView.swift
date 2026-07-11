import SwiftUI
import UIKit

private enum BrowseRoute: Hashable {
    case room(UUID)
    case area(UUID)
    case container(UUID)
    case thing(UUID)
}

private struct ManagementPresentation: Identifiable {
    let id = UUID()
    let route: ManagementRoute
}

struct BrowseSelection: Equatable {
    var placeID: UUID?
    var roomID: UUID?

    mutating func reconcile(with places: [PlaceSnapshot]) {
        guard !places.isEmpty else {
            placeID = nil
            roomID = nil
            return
        }

        let place = places.first(where: { $0.id == placeID }) ?? places[0]
        placeID = place.id
        if let roomID, place.activeRooms.contains(where: { $0.id == roomID }) { return }
        roomID = place.activeRooms.first?.id
    }

    mutating func selectPlace(_ id: UUID, from places: [PlaceSnapshot]) {
        placeID = id
        roomID = nil
        reconcile(with: places)
    }
}

struct BrowseView: View {
    @ObservedObject var store: CatalogStore
    let onSharePlace: (UUID) -> Void
    let onPrintQRCodes: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var managementPresentation: ManagementPresentation?
    @State private var selection = BrowseSelection()
    @State private var placeIDsBeforeCreation: Set<UUID>?

    var body: some View {
        Group {
            if store.isLoading && store.activePlaces.isEmpty {
                ProgressView("Loading Places")
            } else if horizontalSizeClass == .regular {
                BrowseSplitView(
                    store: store,
                    selection: $selection,
                    onSharePlace: onSharePlace,
                    onPrintQRCodes: onPrintQRCodes,
                    presentManagement: presentManagement
                )
            } else {
                NavigationStack {
                    browseRoot
                        .navigationDestination(for: BrowseRoute.self) { route in
                            BrowseDestinationView(
                                store: store, route: route, presentManagement: presentManagement)
                        }
                }
            }
        }
        .sheet(item: $managementPresentation, onDismiss: {
            placeIDsBeforeCreation = nil
        }) { presentation in
            ManagementSheet(store: store, route: presentation.route)
        }
        .onAppear { selection.reconcile(with: store.activePlaces) }
        .onChange(of: store.places) { _, _ in
            if let previousIDs = placeIDsBeforeCreation,
                let created = store.activePlaces.first(where: { !previousIDs.contains($0.id) })
            {
                selection.selectPlace(created.id, from: store.activePlaces)
                placeIDsBeforeCreation = nil
            } else {
                selection.reconcile(with: store.activePlaces)
            }
        }
    }

    @ViewBuilder
    private var browseRoot: some View {
        if store.activePlaces.isEmpty {
            ContentUnavailableView {
                Label("No Places", systemImage: "house")
            } description: {
                Text("Create a Place to start cataloguing your things.")
            } actions: {
                Button("New Place", systemImage: "plus") {
                    presentManagement(.createPlace)
                }
            }
            .navigationTitle("Browse")
        } else if let place = currentPlace {
            PlaceListView(
                store: store,
                place: place,
                allPlaces: store.activePlaces,
                selection: $selection,
                onSharePlace: onSharePlace,
                onPrintQRCodes: onPrintQRCodes,
                presentManagement: presentManagement
            )
            .navigationTitle("Browse")
        }
    }

    private var currentPlace: PlaceSnapshot? {
        store.activePlaces.first(where: { $0.id == selection.placeID }) ?? store.activePlaces.first
    }

    private func presentManagement(_ route: ManagementRoute) {
        if route == .createPlace {
            placeIDsBeforeCreation = Set(store.activePlaces.map(\.id))
        }
        managementPresentation = ManagementPresentation(route: route)
    }
}

private struct BrowseSplitView: View {
    @ObservedObject var store: CatalogStore
    @Binding var selection: BrowseSelection
    let onSharePlace: (UUID) -> Void
    let onPrintQRCodes: () -> Void
    let presentManagement: (ManagementRoute) -> Void

    var body: some View {
        NavigationSplitView {
            List(selection: $selection.roomID) {
                if let place = currentPlace {
                    PlaceHeader(
                        place: place,
                        allPlaces: store.activePlaces,
                        selection: $selection,
                        onSharePlace: onSharePlace,
                        presentManagement: presentManagement
                    )
                    Section("Rooms") {
                        ForEach(place.activeRooms) { room in
                            Button {
                                selection.roomID = room.id
                            } label: {
                                Label(room.name, systemImage: "door.left.hand.open")
                            }
                            .buttonStyle(.plain)
                            .tag(room.id)
                        }
                        Button("New Room", systemImage: "plus") {
                            presentManagement(.createRoom(placeID: place.id))
                        }
                    }
                }
            }
            .navigationTitle("Browse")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Print QR Labels", systemImage: "qrcode", action: onPrintQRCodes)
                        .labelStyle(.iconOnly)
                }
            }
            .refreshable { await store.reload() }
        } detail: {
            NavigationStack {
                if let roomID = selection.roomID {
                    RoomDetailView(store: store, roomID: roomID, presentManagement: presentManagement)
                        .navigationDestination(for: BrowseRoute.self) { route in
                            BrowseDestinationView(
                                store: store, route: route, presentManagement: presentManagement)
                        }
                } else if let place = currentPlace {
                    ContentUnavailableView {
                        Label("No Rooms", systemImage: "door.left.hand.open")
                    } description: {
                        Text("Add the first Room in \(place.name).")
                    } actions: {
                        Button("New Room", systemImage: "plus") {
                            presentManagement(.createRoom(placeID: place.id))
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("No Places", systemImage: "house")
                    } description: {
                        Text("Create a Place to start cataloguing your things.")
                    } actions: {
                        Button("New Place", systemImage: "plus") {
                            presentManagement(.createPlace)
                        }
                    }
                }
            }
        }
    }

    private var currentPlace: PlaceSnapshot? {
        store.activePlaces.first(where: { $0.id == selection.placeID }) ?? store.activePlaces.first
    }
}

private struct PlaceListView: View {
    @ObservedObject var store: CatalogStore
    let place: PlaceSnapshot
    let allPlaces: [PlaceSnapshot]
    @Binding var selection: BrowseSelection
    let onSharePlace: (UUID) -> Void
    let onPrintQRCodes: () -> Void
    let presentManagement: (ManagementRoute) -> Void

    var body: some View {
        List {
            PlaceHeader(
                place: place,
                allPlaces: allPlaces,
                selection: $selection,
                onSharePlace: onSharePlace,
                presentManagement: presentManagement
            )
            Section("Rooms") {
                if place.activeRooms.isEmpty {
                    ContentUnavailableView(
                        "No Rooms Yet",
                        systemImage: "door.left.hand.open",
                        description: Text(
                            "Add the first Room in \(place.name) to organize Storage Areas and Things."
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                ForEach(place.activeRooms) { room in
                    NavigationLink(value: BrowseRoute.room(room.id)) {
                        Label(room.name, systemImage: "door.left.hand.open")
                    }
                }
                Button("New Room", systemImage: "plus") {
                    presentManagement(.createRoom(placeID: place.id))
                }
            }
        }
        .refreshable { await store.reload() }
        .accessibilityIdentifier("browse.placeList")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Print QR Labels", systemImage: "qrcode", action: onPrintQRCodes)
                    .labelStyle(.iconOnly)
            }
        }
    }
}

private struct PlaceHeader: View {
    let place: PlaceSnapshot
    let allPlaces: [PlaceSnapshot]
    @Binding var selection: BrowseSelection
    let onSharePlace: (UUID) -> Void
    let presentManagement: (ManagementRoute) -> Void

    var body: some View {
        Section {
            HStack {
                Menu {
                    ForEach(allPlaces) { candidate in
                        Button {
                            selection.selectPlace(candidate.id, from: allPlaces)
                        } label: {
                            if candidate.id == place.id {
                                Label(candidate.name, systemImage: "checkmark")
                            } else {
                                Text(candidate.name)
                            }
                        }
                    }
                    Divider()
                    Button("New Place", systemImage: "plus") {
                        presentManagement(.createPlace)
                    }
                } label: {
                    Label(place.name, systemImage: "house")
                        .font(.headline)
                }
                Spacer()
                Button("Edit Place", systemImage: "pencil") {
                    presentManagement(.editPlace(place.id))
                }
                .labelStyle(.iconOnly)
                Button("Share Place", systemImage: "person.crop.circle.badge.plus") {
                    onSharePlace(place.id)
                }
                .labelStyle(.iconOnly)
            }
        }
    }
}

private struct BrowseDestinationView: View {
    @ObservedObject var store: CatalogStore
    let route: BrowseRoute
    let presentManagement: (ManagementRoute) -> Void

    var body: some View {
        switch route {
        case .room(let id):
            RoomDetailView(store: store, roomID: id, presentManagement: presentManagement)
        case .area(let id):
            AreaDetailView(store: store, areaID: id, presentManagement: presentManagement)
        case .container(let id):
            ContainerDetailView(store: store, containerID: id, presentManagement: presentManagement)
        case .thing(let id):
            ThingDetailView(store: store, thingID: id)
        }
    }
}

struct RoomDetailView: View {
    @ObservedObject var store: CatalogStore
    let roomID: UUID
    let presentManagement: (ManagementRoute) -> Void

    var body: some View {
        Group {
            if let place = activePlace, let room = place.activeRooms.first(where: { $0.id == roomID }) {
                List {
                    let things = place.activeThings(in: .room(room.id))
                    let containers = place.activeContainers(inRoom: room.id)
                    if !things.isEmpty || !containers.isEmpty {
                        Section("In Room") {
                            ForEach(things) { thing in
                                NavigationLink(value: BrowseRoute.thing(thing.id)) {
                                    ThingRow(store: store, thing: thing)
                                }
                            }
                            ForEach(containers) { container in
                                NavigationLink(value: BrowseRoute.container(container.id)) {
                                    Label(container.name, systemImage: "shippingbox")
                                }
                            }
                        }
                    }
                    Section("Storage Areas") {
                        let areas = place.activeAreas(in: room.id)
                        ForEach(areas) { area in
                            NavigationLink(value: BrowseRoute.area(area.id)) {
                                Label(area.name, systemImage: "cabinet")
                            }
                        }
                        Button("New Storage Area", systemImage: "plus") {
                            presentManagement(.createArea(roomID: room.id))
                        }
                    }
                }
                .navigationTitle(room.name)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit", systemImage: "pencil") { presentManagement(.editRoom(room.id)) }
                            .labelStyle(.iconOnly)
                    }
                }
            } else {
                unavailable("Room", systemImage: "door.left.hand.open")
            }
        }
    }

    private var activePlace: PlaceSnapshot? {
        store.activePlaces.first { $0.activeRooms.contains(where: { $0.id == roomID }) }
    }
}

private struct AreaDetailView: View {
    @ObservedObject var store: CatalogStore
    let areaID: UUID
    let presentManagement: (ManagementRoute) -> Void

    var body: some View {
        Group {
            if let place = activePlace, let area = place.activeAreas.first(where: { $0.id == areaID }) {
                List {
                    CatalogLocationSummary(
                        photo: area.primaryPhoto, detail: area.detail, hasQRCode: area.hasQRCode)
                    Section("Contents") {
                        let things = place.activeThings(in: .area(area.id))
                        let containers = place.activeContainers(inArea: area.id)
                        if things.isEmpty && containers.isEmpty { Text("Empty").foregroundStyle(.secondary) }
                        ForEach(things) { thing in
                            NavigationLink(value: BrowseRoute.thing(thing.id)) {
                                ThingRow(store: store, thing: thing)
                            }
                        }
                        ForEach(containers) { container in
                            NavigationLink(value: BrowseRoute.container(container.id)) {
                                Label(container.name, systemImage: "shippingbox")
                            }
                        }
                        Menu("New", systemImage: "plus") {
                            Button("Container", systemImage: "shippingbox") {
                                presentManagement(.createContainer(destination: .area(area.id)))
                            }
                            Button("Thing", systemImage: "square.grid.2x2") {
                                presentManagement(.createThing(destination: .area(area.id)))
                            }
                        }
                    }
                }
                .navigationTitle(area.name)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit", systemImage: "pencil") { presentManagement(.editArea(area.id)) }
                            .labelStyle(.iconOnly)
                    }
                }
            } else {
                unavailable("Storage Area", systemImage: "cabinet")
            }
        }
    }

    private var activePlace: PlaceSnapshot? {
        store.activePlaces.first { $0.activeAreas.contains(where: { $0.id == areaID }) }
    }
}

private struct ContainerDetailView: View {
    @ObservedObject var store: CatalogStore
    let containerID: UUID
    let presentManagement: (ManagementRoute) -> Void

    var body: some View {
        Group {
            if let place = activePlace,
                let container = place.activeContainers.first(where: { $0.id == containerID })
            {
                List {
                    CatalogLocationSummary(
                        photo: container.primaryPhoto,
                        detail: container.detail,
                        hasQRCode: container.hasQRCode
                    )
                    Section("Contents") {
                        let things = place.activeThings(in: .container(container.id))
                        let children = place.childContainers(of: container.id)
                        if things.isEmpty && children.isEmpty { Text("Empty").foregroundStyle(.secondary) }
                        ForEach(things) { thing in
                            NavigationLink(value: BrowseRoute.thing(thing.id)) {
                                ThingRow(store: store, thing: thing)
                            }
                        }
                        ForEach(children) { child in
                            NavigationLink(value: BrowseRoute.container(child.id)) {
                                Label(child.name, systemImage: "shippingbox")
                            }
                        }
                        Menu("New", systemImage: "plus") {
                            Button("Container", systemImage: "shippingbox") {
                                presentManagement(.createContainer(destination: .container(container.id)))
                            }
                            Button("Thing", systemImage: "square.grid.2x2") {
                                presentManagement(.createThing(destination: .container(container.id)))
                            }
                        }
                    }
                }
                .navigationTitle(container.name)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit", systemImage: "pencil") {
                            presentManagement(.editContainer(container.id))
                        }
                        .labelStyle(.iconOnly)
                    }
                }
            } else {
                unavailable("Container", systemImage: "shippingbox")
            }
        }
    }

    private var activePlace: PlaceSnapshot? {
        store.activePlaces.first { $0.activeContainers.contains(where: { $0.id == containerID }) }
    }
}

private struct CatalogLocationSummary: View {
    let photo: PhotoAssetSnapshot?
    let detail: String?
    let hasQRCode: Bool

    var body: some View {
        if photo != nil || detail?.isEmpty == false {
            Section {
                if let data = photo?.thumbnailData ?? photo?.data, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .accessibilityHidden(true)
                }
                if let detail, !detail.isEmpty { Text(detail) }
            }
        }
        Section("QR Code") {
            Label(
                hasQRCode ? "Attached" : "Not Attached",
                systemImage: hasQRCode ? "qrcode" : "qrcode.viewfinder")
        }
    }
}

@ViewBuilder
private func unavailable(_ noun: String, systemImage: String) -> some View {
    ContentUnavailableView(
        "\(noun) Unavailable",
        systemImage: systemImage,
        description: Text("It may have been archived or removed from this Place.")
    )
}

struct ThingRow: View {
    @ObservedObject var store: CatalogStore
    let thing: ThingSnapshot

    var body: some View {
        HStack(spacing: 12) {
            ThingThumbnail(thing: thing)
            VStack(alignment: .leading, spacing: 3) {
                Text(thing.name)
                Text(store.locationComponents(for: thing).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct ThingThumbnail: View {
    let thing: ThingSnapshot

    var body: some View {
        Group {
            if let data = thing.primaryPhoto?.thumbnailData ?? thing.primaryPhoto?.data,
                let image = UIImage(data: data)
            {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "shippingbox").foregroundStyle(.secondary)
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}

#Preview("Browse") {
    let persistence = PersistenceController.inMemory()
    let store = CatalogStore(persistence: persistence)
    BrowseView(store: store, onSharePlace: { _ in }, onPrintQRCodes: {})
        .task { await store.bootstrap() }
}
