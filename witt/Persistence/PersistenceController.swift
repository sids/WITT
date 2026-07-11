import CloudKit
@preconcurrency import CoreData
import Foundation

public final class PersistenceController: NSObject {
    public enum StoreScope: Sendable {
        case local
        case `private`
        case shared
    }

    public static let shared: PersistenceController = {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return PersistenceController.inMemory()
        }
        return PersistenceController()
    }()

    public let container: NSPersistentCloudKitContainer
    public let usesCloudKit: Bool
    public private(set) var loadError: Error?
    public private(set) var isLoaded = false

    private var storesByScope: [StoreScope: NSPersistentStore] = [:]
    private var historyTokensByStoreID: [String: NSPersistentHistoryToken] = [:]
    private var remoteChangeObserver: NSObjectProtocol?
    private var isProcessingHistory = false

    public var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    public init(
        inMemory: Bool = false,
        cloudKitContainerIdentifier: String? = PersistenceController.configuredCloudKitIdentifier,
        storeDirectory: URL? = nil
    ) {
        container = NSPersistentCloudKitContainer(name: "WITT")
        usesCloudKit = !inMemory && cloudKitContainerIdentifier != nil
        super.init()

        container.persistentStoreDescriptions = Self.makeStoreDescriptions(
            inMemory: inMemory,
            cloudKitContainerIdentifier: cloudKitContainerIdentifier,
            storeDirectory: storeDirectory
        )
        loadStores()
        configureContexts()
        observeRemoteChanges()
    }

    deinit {
        if let remoteChangeObserver {
            NotificationCenter.default.removeObserver(remoteChangeObserver)
        }
    }

    public static func inMemory() -> PersistenceController {
        PersistenceController(inMemory: true, cloudKitContainerIdentifier: nil)
    }

    public func newBackgroundContext(author: String = "witt.background") -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.name = author
        context.transactionAuthor = author
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.undoManager = nil
        return context
    }

    public func assign(_ object: NSManagedObject, to scope: StoreScope) throws {
        guard let store = storesByScope[scope] else {
            throw PersistenceError.storeUnavailable(scope)
        }
        guard let context = object.managedObjectContext else {
            throw PersistenceError.missingManagedObjectContext
        }
        context.assign(object, to: store)
    }

    @MainActor
    public func processPersistentHistory() async throws {
        guard !isProcessingHistory else { return }
        isProcessingHistory = true
        defer { isProcessingHistory = false }

        for store in container.persistentStoreCoordinator.persistentStores {
            guard let storeID = store.identifier else { continue }
            let token = historyTokensByStoreID[storeID]
            let context = newBackgroundContext(author: "witt.history")
            let transactions: [NSPersistentHistoryTransaction] = try await context.perform {
                let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
                let fetchRequest = NSPersistentHistoryTransaction.fetchRequest!
                fetchRequest.affectedStores = [store]
                request.fetchRequest = fetchRequest

                guard
                    let result = try context.execute(request) as? NSPersistentHistoryResult,
                    let transactions = result.result as? [NSPersistentHistoryTransaction]
                else {
                    return []
                }
                return transactions
            }

            for transaction in transactions where transaction.author != viewContext.transactionAuthor {
                guard let userInfo = transaction.objectIDNotification().userInfo else { continue }
                NSManagedObjectContext.mergeChanges(
                    fromRemoteContextSave: userInfo,
                    into: [viewContext]
                )
            }
            if let token = transactions.last?.token {
                historyTokensByStoreID[storeID] = token
            }
        }
    }

    private func loadStores() {
        var loadedCount = 0
        let expectedCount = container.persistentStoreDescriptions.count

        container.loadPersistentStores { [weak self] description, error in
            guard let self else { return }
            if let error {
                loadError = error
                return
            }

            loadedCount += 1
            if
                let url = description.url,
                let store = container.persistentStoreCoordinator.persistentStore(for: url)
            {
                storesByScope[Self.scope(for: description)] = store
            }
            isLoaded = loadedCount == expectedCount
        }
    }

    private func configureContexts() {
        viewContext.name = "witt.view"
        viewContext.transactionAuthor = "witt.app"
        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        viewContext.undoManager = nil
    }

    private func observeRemoteChanges() {
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await self?.processPersistentHistory()
            }
        }
    }

    private static func makeStoreDescriptions(
        inMemory: Bool,
        cloudKitContainerIdentifier: String?,
        storeDirectory: URL?
    ) -> [NSPersistentStoreDescription] {
        if inMemory {
            return [configuredDescription(url: URL(fileURLWithPath: "/dev/null"))]
        }

        let directory = storeDirectory ?? NSPersistentContainer.defaultDirectoryURL()
        guard let cloudKitContainerIdentifier else {
            return [configuredDescription(url: directory.appendingPathComponent("WITT.sqlite"))]
        }

        return [
            cloudDescription(
                url: directory.appendingPathComponent("WITT-private.sqlite"),
                containerIdentifier: cloudKitContainerIdentifier,
                databaseScope: .private
            ),
            cloudDescription(
                url: directory.appendingPathComponent("WITT-shared.sqlite"),
                containerIdentifier: cloudKitContainerIdentifier,
                databaseScope: .shared
            )
        ]
    }

    private static func configuredDescription(url: URL) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        description.shouldAddStoreAsynchronously = false
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )
        return description
    }

    private static func cloudDescription(
        url: URL,
        containerIdentifier: String,
        databaseScope: CKDatabase.Scope
    ) -> NSPersistentStoreDescription {
        let description = configuredDescription(url: url)
        let options = NSPersistentCloudKitContainerOptions(
            containerIdentifier: containerIdentifier
        )
        options.databaseScope = databaseScope
        description.cloudKitContainerOptions = options
        return description
    }

    private static func scope(for description: NSPersistentStoreDescription) -> StoreScope {
        switch description.cloudKitContainerOptions?.databaseScope {
        case .private:
            .private
        case .shared:
            .shared
        default:
            .local
        }
    }

    public static var configuredCloudKitIdentifier: String? {
        guard
            let value = Bundle.main.object(
                forInfoDictionaryKey: "WITTCloudKitContainerIdentifier"
            ) as? String,
            !value.isEmpty
        else {
            return nil
        }
        return value
    }
}

public enum PersistenceError: Error {
    case storeUnavailable(PersistenceController.StoreScope)
    case missingManagedObjectContext
}
