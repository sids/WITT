import Combine
import CoreData
import SwiftUI

@main
struct WITTApp: App {
    @UIApplicationDelegateAdaptor(WITTAppDelegate.self)
    private var appDelegate

    private let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView(persistence: persistence)
                .environment(\.managedObjectContext, persistence.viewContext)
        }
    }
}

struct ContentView: View {
    @StateObject private var store: CatalogStore
    private let persistence: PersistenceController
    private let labelingService: any ThingPhotoLabelingService

    init(
        persistence: PersistenceController = .shared,
        labelingService: any ThingPhotoLabelingService = ThingPhotoLabelingServices.appDefault()
    ) {
        self.persistence = persistence
        self.labelingService = labelingService
        _store = StateObject(wrappedValue: CatalogStore(persistence: persistence))
    }

    var body: some View {
        AppShellView(
            store: store,
            initialScan: initialScan,
            qrResolver: store.repository
        )
        .environment(\.thingPhotoLabelingService, labelingService)
        .task {
            await store.bootstrap()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSPersistentStoreRemoteChange,
                object: persistence.container.persistentStoreCoordinator
            )
            .receive(on: DispatchQueue.main)
        ) { _ in
            Task { await store.reload() }
        }
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
        if ProcessInfo.processInfo.arguments.contains("--demo-create-attach") {
            return .createAttach
        }
#endif
        return nil
    }
}

#Preview("App Shell") {
    ContentView(persistence: .inMemory())
}
