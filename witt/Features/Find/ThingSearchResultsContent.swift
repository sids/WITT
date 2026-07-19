import SwiftUI

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
