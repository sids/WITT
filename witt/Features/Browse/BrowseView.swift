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

struct BrowseView: View {
    @ObservedObject var store: CatalogStore
    let onSharePlace: (UUID) -> Void
    let onPrintQRCodes: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var managementPresentation: ManagementPresentation?

    var body: some View {
        Group {
            if store.isLoading && store.activePlaces.isEmpty {
                ProgressView("Loading Places")
            } else if horizontalSizeClass == .regular {
                BrowseSplitView(
                    store: store,
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
        .sheet(item: $managementPresentation) { presentation in
            ManagementSheet(store: store, route: presentation.route)
        }
    }

    @ViewBuilder
    private var browseRoot: some View {
        if store.activePlaces.isEmpty {
            ContentUnavailableView(
                "No Places",
                systemImage: "house",
                description: Text("Add a Place to start cataloguing your things.")
            )
            .navigationTitle("Browse")
            .toolbar { toolbar }
        } else {
            PlaceListView(store: store)
                .navigationTitle("Browse")
                .toolbar { toolbar }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        BrowseToolbar(
            store: store,
            onSharePlace: onSharePlace,
            onPrintQRCodes: onPrintQRCodes,
            presentManagement: presentManagement
        )
    }

    private func presentManagement(_ route: ManagementRoute) {
        managementPresentation = ManagementPresentation(route: route)
    }
}

private struct BrowseSplitView: View {
    @ObservedObject var store: CatalogStore
    let onSharePlace: (UUID) -> Void
    let onPrintQRCodes: () -> Void
    let presentManagement: (ManagementRoute) -> Void
    @State private var selectedRoomID: UUID?

    var body: some View {
        NavigationSplitView {
            List(store.activePlaces) { place in
                Section(place.name) {
                    ForEach(place.activeRooms) { room in
                        Button {
                            selectedRoomID = room.id
                        } label: {
                            Label(room.name, systemImage: "door.left.hand.open")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Browse")
            .toolbar {
                BrowseToolbar(
                    store: store,
                    onSharePlace: onSharePlace,
                    onPrintQRCodes: onPrintQRCodes,
                    presentManagement: presentManagement
                )
            }
            .refreshable { await store.reload() }
        } detail: {
            NavigationStack {
                if let selectedRoomID {
                    RoomDetailView(store: store, roomID: selectedRoomID, presentManagement: presentManagement)
                        .navigationDestination(for: BrowseRoute.self) { route in
                            BrowseDestinationView(
                                store: store, route: route, presentManagement: presentManagement)
                        }
                } else {
                    ContentUnavailableView("Choose a Room", systemImage: "door.left.hand.open")
                }
            }
        }
        .onAppear { reconcileSelectedRoom() }
        .onChange(of: store.places) { _, _ in reconcileSelectedRoom() }
    }

    private func reconcileSelectedRoom() {
        let roomIDs = Set(store.activePlaces.flatMap(\.activeRooms).map(\.id))
        if let selectedRoomID, roomIDs.contains(selectedRoomID) { return }
        selectedRoomID = store.activePlaces.first?.activeRooms.first?.id
    }
}

private struct PlaceListView: View {
    @ObservedObject var store: CatalogStore

    var body: some View {
        List(store.activePlaces) { place in
            Section(place.name) {
                ForEach(place.activeRooms) { room in
                    NavigationLink(value: BrowseRoute.room(room.id)) {
                        Label(room.name, systemImage: "door.left.hand.open")
                    }
                }
            }
        }
        .refreshable { await store.reload() }
        .accessibilityIdentifier("browse.placeList")
    }
}

private struct BrowseToolbar: ToolbarContent {
    @ObservedObject var store: CatalogStore
    let onSharePlace: (UUID) -> Void
    let onPrintQRCodes: () -> Void
    let presentManagement: (ManagementRoute) -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ManagementAddMenu(store: store, presentManagement: presentManagement)
        }
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Button("Print QR Labels", systemImage: "qrcode", action: onPrintQRCodes)
                shareCommands
                editPlaceCommands
            } label: {
                Image(systemName: "ellipsis")
            }
            .help("More Actions")
            .accessibilityLabel("More Actions")
        }
    }

    @ViewBuilder
    private var shareCommands: some View {
        if let onlyPlace = store.activePlaces.first, store.activePlaces.count == 1 {
            Button("Share Place", systemImage: "person.crop.circle.badge.plus") {
                onSharePlace(onlyPlace.id)
            }
        } else if !store.activePlaces.isEmpty {
            Menu("Share Place", systemImage: "person.crop.circle.badge.plus") {
                ForEach(store.activePlaces) { place in
                    Button(place.name) { onSharePlace(place.id) }
                }
            }
        }
    }

    @ViewBuilder
    private var editPlaceCommands: some View {
        if let onlyPlace = store.activePlaces.first, store.activePlaces.count == 1 {
            Button("Edit Place", systemImage: "pencil") {
                presentManagement(.editPlace(onlyPlace.id))
            }
        } else if !store.activePlaces.isEmpty {
            Menu("Edit Place", systemImage: "pencil") {
                ForEach(store.activePlaces) { place in
                    Button(place.name) { presentManagement(.editPlace(place.id)) }
                }
            }
        }
    }
}

private struct ManagementAddMenu: View {
    @ObservedObject var store: CatalogStore
    var placeID: UUID?
    var roomID: UUID?
    var containerDestination: ContainerDestination?
    var thingDestination: ThingDestination?
    let presentManagement: (ManagementRoute) -> Void

    private var defaultPlaceID: UUID? {
        placeID ?? (store.activePlaces.count == 1 ? store.activePlaces[0].id : nil)
    }

    private var defaultRoomID: UUID? {
        if let roomID { return roomID }
        let rooms = store.activePlaces.flatMap(\.activeRooms)
        return rooms.count == 1 ? rooms[0].id : nil
    }

    private var defaultContainerDestination: ContainerDestination? {
        if let containerDestination { return containerDestination }
        let options = store.containerParentOptions()
        return options.count == 1 ? options[0].destination : nil
    }

    private var defaultThingDestination: ThingDestination? {
        if let thingDestination { return thingDestination }
        let options = store.thingDestinationOptions
        return options.count == 1 ? options[0].destination : nil
    }

    var body: some View {
        Menu {
            Button("Place", systemImage: "house") { presentManagement(.createPlace) }
            Button("Room", systemImage: "door.left.hand.open") {
                presentManagement(.createRoom(placeID: defaultPlaceID))
            }
            Button("Storage Area", systemImage: "cabinet") {
                presentManagement(.createArea(roomID: defaultRoomID))
            }
            Button("Container", systemImage: "shippingbox") {
                presentManagement(.createContainer(destination: defaultContainerDestination))
            }
            Button("Thing", systemImage: "square.grid.2x2") {
                presentManagement(.createThing(destination: defaultThingDestination))
            }
        } label: {
            Image(systemName: "plus")
        }
        .help("Add")
        .accessibilityLabel("Add")
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
                        if areas.isEmpty { Text("No Storage Areas").foregroundStyle(.secondary) }
                        ForEach(areas) { area in
                            NavigationLink(value: BrowseRoute.area(area.id)) {
                                Label(area.name, systemImage: "cabinet")
                            }
                        }
                    }
                }
                .navigationTitle(room.name)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        ManagementAddMenu(
                            store: store,
                            placeID: place.id,
                            roomID: room.id,
                            containerDestination: .room(room.id),
                            thingDestination: .room(room.id),
                            presentManagement: presentManagement
                        )
                    }
                    ToolbarItem(placement: .secondaryAction) {
                        Button("Edit", systemImage: "pencil") { presentManagement(.editRoom(room.id)) }
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
                    }
                }
                .navigationTitle(area.name)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        ManagementAddMenu(
                            store: store,
                            placeID: place.id,
                            roomID: area.roomID,
                            containerDestination: .area(area.id),
                            thingDestination: .area(area.id),
                            presentManagement: presentManagement
                        )
                    }
                    ToolbarItem(placement: .secondaryAction) {
                        Button("Edit", systemImage: "pencil") { presentManagement(.editArea(area.id)) }
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
                    }
                }
                .navigationTitle(container.name)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        ManagementAddMenu(
                            store: store,
                            placeID: place.id,
                            roomID: roomID(for: container, in: place),
                            containerDestination: .container(container.id),
                            thingDestination: .container(container.id),
                            presentManagement: presentManagement
                        )
                    }
                    ToolbarItem(placement: .secondaryAction) {
                        Button("Edit", systemImage: "pencil") {
                            presentManagement(.editContainer(container.id))
                        }
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

    private func roomID(for container: ContainerSnapshot, in place: PlaceSnapshot) -> UUID? {
        switch container.parent {
        case .room(let id): return id
        case .area(let id): return place.area(id: id)?.roomID
        case .container(let id):
            guard let parent = place.container(id: id) else { return nil }
            return roomID(for: parent, in: place)
        }
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
