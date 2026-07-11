import SwiftUI

@main
struct WITTApp: App {
    private let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.viewContext)
        }
    }
}

struct ContentView: View {
    @State private var store: DemoInventoryStore

    init() {
#if DEBUG
        let initialStore = ProcessInfo.processInfo.arguments.contains("--demo-no-qr-targets")
            ? DemoInventoryStore.allTargetsAssignedFixture
            : DemoInventoryStore.fixture
#else
        let initialStore = DemoInventoryStore.fixture
#endif
        _store = State(initialValue: initialStore)
    }

    var body: some View {
        AppShellView(store: store, initialScan: initialScan)
    }

    private var initialScan: ScanDemo? {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo-known-qr") {
            return .known
        }
        if ProcessInfo.processInfo.arguments.contains("--demo-unknown-qr") {
            return .unknown
        }
        if ProcessInfo.processInfo.arguments.contains("--demo-review-thing") {
            return .review
        }
#endif
        return nil
    }
}

#Preview("App Shell") {
    ContentView()
}
