import SwiftUI

struct FindView: View {
    @ObservedObject var store: CatalogStore
    @State private var query = ""
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            ThingSearchResultsContent(store: store, query: query) { thing in
                path.append(thing.id)
            }
            .navigationTitle("Find")
            .searchable(text: $query, prompt: "Things, keywords, or places")
            .refreshable { await store.reload() }
            .accessibilityIdentifier("find.searchResults")
            .navigationDestination(for: UUID.self) { thingID in
                ThingDetailView(store: store, thingID: thingID)
            }
        }
    }
}

struct ThingSearchResultsContent: View {
    @ObservedObject var store: CatalogStore
    let query: String
    let onSelect: (ThingSnapshot) -> Void

    private var results: [ThingSnapshot] {
        guard !query.isEmpty else { return store.things }
        return store.things.filter { thing in
            thing.name.localizedStandardContains(query)
                || thing.keywords.contains { $0.localizedStandardContains(query) }
                || store.locationComponents(for: thing).contains {
                    $0.localizedStandardContains(query)
                }
        }
    }

    var body: some View {
        List(results) { thing in
            Button {
                onSelect(thing)
            } label: {
                ThingRow(store: store, thing: thing)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows Thing details")
        }
        .overlay {
            if results.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView(
                        "No Things Yet",
                        systemImage: "shippingbox",
                        description: Text("Scan a Storage Area or Container to add one.")
                    )
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .refreshable { await store.reload() }
    }
}

#Preview("Find") {
    let persistence = PersistenceController.inMemory()
    let store = CatalogStore(persistence: persistence)
    FindView(store: store)
        .task { await store.bootstrap() }
}
