import SwiftUI

struct BrowseView: View {
    let store: DemoInventoryStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            BrowseSplitView(store: store)
        } else {
            NavigationStack {
                PlaceListView(store: store)
                    .navigationDestination(for: DemoRoom.self) { room in
                        RoomDetailView(room: room)
                    }
                    .navigationDestination(for: DemoThing.self) { thing in
                        ThingDetailView(thing: thing)
                    }
            }
        }
    }
}

private struct BrowseSplitView: View {
    let store: DemoInventoryStore
    @State private var selectedRoom: DemoRoom?

    init(store: DemoInventoryStore) {
        self.store = store
        _selectedRoom = State(initialValue: store.places.first?.rooms.first)
    }

    var body: some View {
        NavigationSplitView {
            List(store.places) { place in
                Section(place.name) {
                    ForEach(place.rooms) { room in
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
        } detail: {
            NavigationStack {
                if let selectedRoom {
                    RoomDetailView(room: selectedRoom)
                } else {
                    ContentUnavailableView("Choose a Room", systemImage: "door.left.hand.open")
                }
            }
        }
    }
}

private struct PlaceListView: View {
    let store: DemoInventoryStore

    var body: some View {
        List(store.places) { place in
            Section(place.name) {
                ForEach(place.rooms) { room in
                    NavigationLink(value: room) {
                        Label(room.name, systemImage: "door.left.hand.open")
                    }
                }
            }
        }
        .navigationTitle("Browse")
        .accessibilityIdentifier("browse.placeList")
    }
}

struct RoomDetailView: View {
    let room: DemoRoom

    var body: some View {
        List {
            ForEach(room.areas) { area in
                Section {
                    ForEach(area.things) { thing in
                        NavigationLink(value: thing) {
                            ThingRow(thing: thing)
                        }
                    }
                    ForEach(area.containers) { container in
                        DisclosureGroup {
                            ForEach(container.things) { thing in
                                NavigationLink(value: thing) {
                                    ThingRow(thing: thing)
                                }
                            }
                        } label: {
                            Label(container.name, systemImage: "shippingbox")
                        }
                    }
                } header: {
                    Label(area.name, systemImage: area.hasQRCode ? "qrcode" : "cabinet")
                }
            }
        }
        .navigationTitle(room.name)
        .navigationDestination(for: DemoThing.self) { thing in
            ThingDetailView(thing: thing)
        }
    }
}

struct ThingRow: View {
    let thing: DemoThing

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(thing.name)
                Text(thing.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } icon: {
            Image(systemName: thing.symbolName)
        }
    }
}

#Preview("Browse") {
    BrowseView(store: .fixture)
}
