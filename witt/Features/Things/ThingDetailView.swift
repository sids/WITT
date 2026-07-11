import SwiftUI
import UIKit

struct ThingDetailView: View {
    @ObservedObject var store: CatalogStore
    let thing: ThingSnapshot

    private var location: String {
        store.locationComponents(for: thing).joined(separator: " · ")
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    ThingPhoto(thing: thing)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(thing.name)
                            .font(.title2.weight(.semibold))
                        Text(location)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Where") {
                Label(location, systemImage: "location")
            }

            if !thing.keywords.isEmpty {
                Section("Keywords") {
                    Text(thing.keywords.joined(separator: ", "))
                }
            }

            if let notes = thing.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }
        }
        .navigationTitle("Thing")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("thing.detail")
    }
}

private struct ThingPhoto: View {
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
        ContentUnavailableView("Load a Thing", systemImage: "shippingbox")
    }
    .task { await store.bootstrap() }
}
