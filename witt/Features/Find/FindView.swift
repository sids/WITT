import SwiftUI

struct FindView: View {
    @ObservedObject var store: CatalogStore
    @State private var query = ""

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
        NavigationStack {
            List(results) { thing in
                NavigationLink(value: thing) {
                    ThingRow(store: store, thing: thing)
                }
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
            .navigationTitle("Find")
            .searchable(text: $query, prompt: "Things, keywords, or places")
            .refreshable { await store.reload() }
            .accessibilityIdentifier("find.searchResults")
            .navigationDestination(for: ThingSnapshot.self) { thing in
                ThingDetailView(store: store, thing: thing)
            }
        }
    }
}

#Preview("Find") {
    let persistence = PersistenceController.inMemory()
    let store = CatalogStore(persistence: persistence)
    FindView(store: store)
        .task { await store.bootstrap() }
}
