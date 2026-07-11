import SwiftUI
import UIKit

struct BrowseView: View {
    @ObservedObject var store: CatalogStore
    let onSharePlace: (UUID) -> Void
    let onPrintQRCodes: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if store.isLoading && store.activePlaces.isEmpty {
                ProgressView("Loading Places")
            } else if store.activePlaces.isEmpty {
                NavigationStack {
                    ContentUnavailableView(
                        "No Places",
                        systemImage: "house",
                        description: Text("Add a Place to start cataloguing your things.")
                    )
                    .navigationTitle("Browse")
                    .toolbar { BrowseToolbar(places: [], onSharePlace: onSharePlace, onPrintQRCodes: onPrintQRCodes) }
                }
            } else if horizontalSizeClass == .regular {
                BrowseSplitView(store: store, onSharePlace: onSharePlace, onPrintQRCodes: onPrintQRCodes)
            } else {
                NavigationStack {
                    PlaceListView(store: store, onSharePlace: onSharePlace, onPrintQRCodes: onPrintQRCodes)
                        .navigationDestination(for: RoomSnapshot.self) { room in
                            if let place = store.activePlaces.first(where: { $0.id == room.placeID }) {
                                RoomDetailView(store: store, place: place, room: room)
                            }
                        }
                }
            }
        }
    }
}

private struct BrowseSplitView: View {
    @ObservedObject var store: CatalogStore
    let onSharePlace: (UUID) -> Void
    let onPrintQRCodes: () -> Void
    @State private var selectedRoom: RoomSnapshot?

    var body: some View {
        NavigationSplitView {
            List(store.activePlaces) { place in
                Section(place.name) {
                    ForEach(place.activeRooms) { room in
                        Button {
                            selectedRoom = room
                        } label: {
                            Label(room.name, systemImage: "door.left.hand.open")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Browse")
            .toolbar { BrowseToolbar(places: store.activePlaces, onSharePlace: onSharePlace, onPrintQRCodes: onPrintQRCodes) }
        } detail: {
            NavigationStack {
                if
                    let selectedRoom,
                    let place = store.activePlaces.first(where: { $0.id == selectedRoom.placeID })
                {
                    RoomDetailView(store: store, place: place, room: selectedRoom)
                } else {
                    ContentUnavailableView("Choose a Room", systemImage: "door.left.hand.open")
                }
            }
        }
        .onAppear { reconcileSelectedRoom() }
        .onChange(of: store.places) { _, _ in reconcileSelectedRoom() }
    }

    private func reconcileSelectedRoom() {
        if let selectedRoom {
            let currentRoom = store.activePlaces
                .flatMap(\.activeRooms)
                .first { $0.id == selectedRoom.id }
            if let currentRoom {
                self.selectedRoom = currentRoom
                return
            }
        }
        selectedRoom = store.activePlaces.first?.activeRooms.first
    }
}

private struct PlaceListView: View {
    @ObservedObject var store: CatalogStore
    let onSharePlace: (UUID) -> Void
    let onPrintQRCodes: () -> Void

    var body: some View {
        List(store.activePlaces) { place in
            Section(place.name) {
                ForEach(place.activeRooms) { room in
                    NavigationLink(value: room) {
                        Label(room.name, systemImage: "door.left.hand.open")
                    }
                }
            }
        }
        .navigationTitle("Browse")
        .toolbar { BrowseToolbar(places: store.activePlaces, onSharePlace: onSharePlace, onPrintQRCodes: onPrintQRCodes) }
        .refreshable { await store.reload() }
        .accessibilityIdentifier("browse.placeList")
    }
}

private struct BrowseToolbar: ToolbarContent {
    let places: [PlaceSnapshot]
    let onSharePlace: (UUID) -> Void
    let onPrintQRCodes: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: onPrintQRCodes) {
                Image(systemName: "qrcode")
            }
            .help("Print QR Labels")
            .accessibilityLabel("Print QR Labels")
        }
        ToolbarItem(placement: .primaryAction) {
            if let onlyPlace = places.first, places.count == 1 {
                Button {
                    onSharePlace(onlyPlace.id)
                } label: {
                    Image(systemName: "person.crop.circle.badge.plus")
                }
                .help("Share Place")
                .accessibilityLabel("Share \(onlyPlace.name)")
            } else if !places.isEmpty {
                Menu {
                    ForEach(places) { place in
                        Button(place.name) { onSharePlace(place.id) }
                    }
                } label: {
                    Image(systemName: "person.crop.circle.badge.plus")
                }
                .help("Share Place")
                .accessibilityLabel("Share Place")
            }
        }
    }
}

struct RoomDetailView: View {
    @ObservedObject var store: CatalogStore
    let place: PlaceSnapshot
    let room: RoomSnapshot

    private var roomThings: [ThingSnapshot] {
        place.activeThings(in: .room(room.id))
    }

    private var roomContainers: [ContainerSnapshot] {
        place.activeContainers(inRoom: room.id)
    }

    var body: some View {
        List {
            if !roomThings.isEmpty || !roomContainers.isEmpty {
                Section("In Room") {
                    ForEach(roomThings) { thing in
                        NavigationLink(value: thing) {
                            ThingRow(store: store, thing: thing)
                        }
                    }
                    ForEach(roomContainers) { container in
                        ContainerDisclosureView(store: store, place: place, container: container)
                    }
                }
            }

            ForEach(place.activeAreas(in: room.id)) { area in
                Section {
                    let things = place.activeThings(in: .area(area.id))
                    let containers = place.activeContainers(inArea: area.id)
                    if things.isEmpty && containers.isEmpty {
                        Text("Empty")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(things) { thing in
                        NavigationLink(value: thing) {
                            ThingRow(store: store, thing: thing)
                        }
                    }
                    ForEach(containers) { container in
                        ContainerDisclosureView(store: store, place: place, container: container)
                    }
                } header: {
                    Label(area.name, systemImage: area.hasQRCode ? "qrcode" : "cabinet")
                }
            }
        }
        .navigationTitle(room.name)
        .navigationDestination(for: ThingSnapshot.self) { thing in
            ThingDetailView(store: store, thing: thing)
        }
    }
}

private struct ContainerDisclosureView: View {
    @ObservedObject var store: CatalogStore
    let place: PlaceSnapshot
    let container: ContainerSnapshot

    private var things: [ThingSnapshot] {
        place.activeThings(in: .container(container.id))
    }

    private var children: [ContainerSnapshot] {
        place.childContainers(of: container.id)
    }

    var body: some View {
        DisclosureGroup {
            if things.isEmpty && children.isEmpty {
                Text("Empty")
                    .foregroundStyle(.secondary)
            }
            ForEach(things) { thing in
                NavigationLink(value: thing) {
                    ThingRow(store: store, thing: thing)
                }
            }
            ForEach(children) { child in
                ContainerDisclosureView(store: store, place: place, container: child)
            }
        } label: {
            Label(container.name, systemImage: container.hasQRCode ? "shippingbox.fill" : "shippingbox")
        }
    }
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
            if
                let data = thing.primaryPhoto?.thumbnailData ?? thing.primaryPhoto?.data,
                let image = UIImage(data: data)
            {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.secondary)
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
