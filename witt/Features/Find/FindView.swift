import SwiftUI

struct FindView: View {
    let store: DemoInventoryStore
    @State private var query = ""

    private var results: [DemoThing] {
        guard !query.isEmpty else { return store.things }
        return store.things.filter { thing in
            thing.name.localizedStandardContains(query)
                || thing.keywords.contains { $0.localizedStandardContains(query) }
                || thing.location.localizedStandardContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(results) { thing in
                NavigationLink(value: thing) {
                    ThingRow(thing: thing)
                }
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Find")
            .searchable(text: $query, prompt: "Things, keywords, or places")
            .accessibilityIdentifier("find.searchResults")
            .navigationDestination(for: DemoThing.self) { thing in
                ThingDetailView(thing: thing)
            }
        }
    }
}

#Preview("Find") {
    FindView(store: .fixture)
}
