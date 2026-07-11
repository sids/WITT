import SwiftUI
import UIKit

struct ThingDetailView: View {
    @ObservedObject var store: CatalogStore
    let thingID: UUID
    @State private var managementRoute: ManagementRoute?

    var body: some View {
        Group {
            if let thing = activeThing {
                List {
                    Section {
                        HStack(alignment: .top, spacing: 16) {
                            ThingPhoto(thing: thing)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(thing.name)
                                    .font(.title2.weight(.semibold))
                                Text(location(for: thing))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section("Where") {
                        Label(location(for: thing), systemImage: "location")
                    }

                    if !thing.keywords.isEmpty {
                        Section("Keywords") { Text(thing.keywords.joined(separator: ", ")) }
                    }

                    if let notes = thing.notes, !notes.isEmpty {
                        Section("Notes") { Text(notes) }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit", systemImage: "pencil") { managementRoute = .editThing(thing.id) }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Thing Unavailable",
                    systemImage: "shippingbox",
                    description: Text("It may have been archived or removed from this Place.")
                )
            }
        }
        .navigationTitle("Thing")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("thing.detail")
        .sheet(item: $managementRoute) { route in
            ManagementSheet(store: store, route: route)
        }
    }

    private var activeThing: ThingSnapshot? {
        store.things.first { $0.id == thingID }
    }

    private func location(for thing: ThingSnapshot) -> String {
        store.locationComponents(for: thing).joined(separator: " · ")
    }
}

private struct ThingPhoto: View {
    let thing: ThingSnapshot

    var body: some View {
        Group {
            if let data = thing.primaryPhoto?.thumbnailData ?? thing.primaryPhoto?.data,
                let image = UIImage(data: data)
            {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "shippingbox")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}

#Preview("Thing Detail") {
    let persistence = PersistenceController.inMemory()
    let store = CatalogStore(persistence: persistence)
    NavigationStack {
        ThingDetailView(store: store, thingID: UUID())
    }
    .task { await store.bootstrap() }
}
