import SwiftUI

struct ThingDetailView: View {
    let thing: DemoThing

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: thing.symbolName)
                        .font(.system(size: 42))
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(thing.name)
                            .font(.title2.weight(.semibold))
                        Text(thing.location)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Where") {
                Label(thing.location, systemImage: "location")
            }

            Section("Keywords") {
                Text(thing.keywords.joined(separator: ", "))
            }

            if !thing.notes.isEmpty {
                Section("Notes") {
                    Text(thing.notes)
                }
            }
        }
        .navigationTitle("Thing")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("thing.detail")
    }
}

#Preview("Thing Detail") {
    NavigationStack {
        ThingDetailView(thing: DemoInventoryStore.fixture.things[0])
    }
}
