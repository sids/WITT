import SwiftUI
import UIKit

private enum BrowseRoute: Hashable {
    case place(UUID)
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
    @State private var managementPresentation: ManagementPresentation?

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.activePlaces.isEmpty {
                    ProgressView("Loading Places")
                } else {
                    placesRoot
                }
            }
            .navigationTitle("Places")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Print QR Labels", systemImage: "qrcode", action: onPrintQRCodes)
                        .labelStyle(.iconOnly)
                    Button("New Place", systemImage: "plus") {
                        presentManagement(.createPlace)
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .navigationDestination(for: BrowseRoute.self) { route in
                BrowseDestinationView(
                    store: store,
                    route: route,
                    onSharePlace: onSharePlace,
                    presentManagement: presentManagement
                )
            }
        }
        .sheet(item: $managementPresentation) { presentation in
            ManagementSheet(store: store, route: presentation.route)
        }
    }

    @ViewBuilder
    private var placesRoot: some View {
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
        } else {
            List(store.activePlaces) { place in
                NavigationLink(value: BrowseRoute.place(place.id)) {
                    Label(place.name, systemImage: "house")
                }
            }
            .refreshable { await store.reload() }
            .accessibilityIdentifier("browse.placesList")
        }
    }

    private func presentManagement(_ route: ManagementRoute) {
        managementPresentation = ManagementPresentation(route: route)
    }
}

private struct PlaceListView: View {
    @ObservedObject var store: CatalogStore
    let place: PlaceSnapshot
    let onSharePlace: (UUID) -> Void
    let presentManagement: (ManagementRoute) -> Void

    var body: some View {
        List {
            if place.activeRooms.isEmpty {
                Section {
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

                Section {
                    Button("New Room", systemImage: "plus") {
                        presentManagement(.createRoom(placeID: place.id))
                    }
                }
            } else {
                Section("Rooms") {
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
        }
        .navigationTitle(place.name)
        .refreshable { await store.reload() }
        .accessibilityIdentifier("browse.placeList")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if store.isPlaceShared(place.id) {
                    Button("Shared", systemImage: "person.2") {
                        onSharePlace(place.id)
                    }
                }
                Menu("Place Actions", systemImage: "ellipsis") {
                    Button("Rename Place", systemImage: "pencil") {
                        presentManagement(.editPlace(place.id))
                    }
                    Button("Share Place", systemImage: "person.crop.circle.badge.plus") {
                        onSharePlace(place.id)
                    }
                }
                .labelStyle(.iconOnly)
            }
        }
    }
}

private struct BrowseDestinationView: View {
    @ObservedObject var store: CatalogStore
    let route: BrowseRoute
    let onSharePlace: (UUID) -> Void
    let presentManagement: (ManagementRoute) -> Void

    var body: some View {
        switch route {
        case .place(let id):
            if let place = store.activePlaces.first(where: { $0.id == id }) {
                PlaceListView(
                    store: store,
                    place: place,
                    onSharePlace: onSharePlace,
                    presentManagement: presentManagement
                )
            } else {
                unavailable("Place", systemImage: "house")
            }
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
    @State private var showsQRScanner = false

    var body: some View {
        Group {
            if let place = activePlace, let area = place.activeAreas.first(where: { $0.id == areaID }) {
                VStack(alignment: .leading, spacing: 0) {
                    if let detail = area.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                    }
                    List {
                        CatalogLocationSummary(photo: area.primaryPhoto, detail: nil)
                        Section("Contents") {
                            let things = place.activeThings(in: .area(area.id))
                            let containers = place.activeContainers(inArea: area.id)
                            if things.isEmpty && containers.isEmpty {
                                Text("Empty").foregroundStyle(.secondary)
                            }
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
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle(area.name)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu("Storage Area Actions", systemImage: "ellipsis") {
                            Button("Edit", systemImage: "pencil") {
                                presentManagement(.editArea(area.id))
                            }
                            Button(
                                area.hasQRCode ? "Reattach QR Code" : "Attach QR Code",
                                systemImage: "qrcode.viewfinder"
                            ) {
                                showsQRScanner = true
                            }
                        }
                        .labelStyle(.iconOnly)
                    }
                }
                .fullScreenCover(isPresented: $showsQRScanner) {
                    let target = QRBindingTarget.area(QRTargetID(rawValue: area.id))
                    QRAssignmentScanner(store: store, expectedTarget: target) { token in
                        try await store.replaceQRCode(token, target: target)
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
    @State private var showsQRScanner = false

    var body: some View {
        Group {
            if let place = activePlace,
                let container = place.activeContainers.first(where: { $0.id == containerID })
            {
                List {
                    CatalogLocationSummary(
                        photo: container.primaryPhoto,
                        detail: container.detail
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
                        Menu("Container Actions", systemImage: "ellipsis") {
                            Button("Edit", systemImage: "pencil") {
                                presentManagement(.editContainer(container.id))
                            }
                            Button(
                                container.hasQRCode ? "Reattach QR Code" : "Attach QR Code",
                                systemImage: "qrcode.viewfinder"
                            ) {
                                showsQRScanner = true
                            }
                        }
                        .labelStyle(.iconOnly)
                    }
                }
                .fullScreenCover(isPresented: $showsQRScanner) {
                    let target = QRBindingTarget.container(QRTargetID(rawValue: container.id))
                    QRAssignmentScanner(store: store, expectedTarget: target) { token in
                        try await store.replaceQRCode(token, target: target)
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
