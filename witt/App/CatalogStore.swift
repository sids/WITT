import Combine
import CoreData
import Foundation

@MainActor
final class CatalogStore: ObservableObject {
    @Published private(set) var places: [PlaceSnapshot] = []
    @Published private(set) var unassignedQRCodeTargets: [QRAttachTargetSnapshot] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published var errorMessage: String?

    nonisolated let repository: any CatalogRepository
    private let persistence: PersistenceController
    private let sharingService: PlaceSharingService

    init(
        persistence: PersistenceController,
        repository: (any CatalogRepository)? = nil
    ) {
        self.persistence = persistence
        self.repository = repository ?? CoreDataCatalogRepository(
            persistenceController: persistence
        )
        sharingService = PlaceSharingService(persistentContainer: persistence.container)
    }

    var things: [ThingSnapshot] {
        activePlaces.flatMap(\.things).filter { $0.archivedAt == nil }
    }

    var activePlaces: [PlaceSnapshot] {
        places.filter { $0.archivedAt == nil }
    }

    var defaultThingDestination: ThingDestination? {
        guard let place = activePlaces.first else { return nil }
        if let container = place.containers.first(where: { $0.archivedAt == nil }) {
            return .container(container.id)
        }
        if let area = place.areas.first(where: { $0.archivedAt == nil }) {
            return .area(area.id)
        }
        return place.rooms.first(where: { $0.archivedAt == nil }).map {
            .room($0.id)
        }
    }

    func bootstrap() async {
        guard !hasLoaded, !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            _ = try await repository.seedHomeIfNeeded()
            try await reloadCatalog()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() async {
        do {
            try await reloadCatalog()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadUnassignedQRCodeTargets() async {
        do {
            unassignedQRCodeTargets = try await repository.unassignedQRCodeTargets()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func bind(_ token: QRToken, to target: QRAttachTargetSnapshot) async -> Bool {
        do {
            _ = try await repository.bindQRCode(
                QRCodeBindingRequest(token: token, target: target.bindingTarget)
            )
            try await reloadCatalog()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createTargetAndBind(_ request: CreateAndBindQRCodeRequest) async -> Bool {
        do {
            _ = try await repository.createTargetAndBindQRCode(request)
            try await reloadCatalog()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func saveThing(
        name: String,
        keywords: [String],
        notes: String,
        photo: NormalizedPhoto?,
        to destination: ThingDestination,
        nameSource: String
    ) async -> Bool {
        do {
            _ = try await repository.saveThing(
                ReviewedThingDraft(
                    name: name,
                    keywords: keywords,
                    notes: notes,
                    nameSource: nameSource,
                    photo: photo
                ),
                to: destination
            )
            try await reloadCatalog()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func sharingPresentation(for placeID: UUID) throws -> PlaceSharingPresentation {
        let request = NSFetchRequest<Place>(entityName: "Place")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", placeID as CVarArg)
        guard let place = try persistence.viewContext.fetch(request).first else {
            throw CatalogRepositoryError.targetNotFound
        }
        return try sharingService.sharingPresentation(for: place)
    }

    private func reloadCatalog() async throws {
        places = try await repository.fetchPlaces()
        unassignedQRCodeTargets = try await repository.unassignedQRCodeTargets()
    }
}
