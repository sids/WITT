import Combine
import CoreData
import Foundation

@MainActor
final class CatalogStore: ObservableObject {
    @Published private(set) var places: [PlaceSnapshot] = []
    @Published private(set) var unassignedQRCodeTargets: [QRAttachTargetSnapshot] = []
    @Published private(set) var placeSharingStates: [UUID: PlaceSharingState] = [:]
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
        activePlaces.flatMap(\.activeThings)
    }

    var activePlaces: [PlaceSnapshot] {
        places.filter { $0.archivedAt == nil }
    }

#if DEBUG
    var defaultThingDestination: ThingDestination? {
        guard let place = activePlaces.first else { return nil }
        if let container = place.activeContainers.first {
            return .container(container.id)
        }
        if let area = place.activeAreas.first {
            return .area(area.id)
        }
        return place.activeRooms.first.map {
            .room($0.id)
        }
    }
#endif

    func isPlaceShared(_ placeID: UUID) -> Bool {
        placeSharingStates[placeID]?.isShared == true
    }

    func createPlace(_ draft: CreatePlaceDraft) async -> PlaceSnapshot? {
        await performMutation { try await repository.createPlace(draft) }
    }

    func createRoom(_ draft: CreateRoomDraft) async -> RoomSnapshot? {
        await performMutation { try await repository.createRoom(draft) }
    }

    func createArea(_ draft: CreateAreaDraft) async -> AreaSnapshot? {
        await performMutation { try await repository.createArea(draft) }
    }

    func createContainer(_ draft: CreateContainerDraft) async -> ContainerSnapshot? {
        await performMutation { try await repository.createContainer(draft) }
    }

    func updatePlace(id: UUID, with draft: UpdatePlaceDraft) async -> PlaceSnapshot? {
        await performMutation { try await repository.updatePlace(id: id, with: draft) }
    }

    func updateRoom(id: UUID, with draft: UpdateRoomDraft) async -> RoomSnapshot? {
        await performMutation { try await repository.updateRoom(id: id, with: draft) }
    }

    func updateArea(id: UUID, with draft: UpdateAreaDraft) async -> AreaSnapshot? {
        await performMutation { try await repository.updateArea(id: id, with: draft) }
    }

    func updateContainer(id: UUID, with draft: UpdateContainerDraft) async -> ContainerSnapshot? {
        await performMutation { try await repository.updateContainer(id: id, with: draft) }
    }

    func updateThing(id: UUID, with draft: UpdateThingDraft) async -> ThingSnapshot? {
        await performMutation { try await repository.updateThing(id: id, with: draft) }
    }

    func archivePlace(id: UUID) async -> PlaceSnapshot? {
        await performMutation { try await repository.archivePlace(id: id) }
    }

    func archiveRoom(id: UUID) async -> RoomSnapshot? {
        await performMutation { try await repository.archiveRoom(id: id) }
    }

    func archiveArea(id: UUID) async -> AreaSnapshot? {
        await performMutation { try await repository.archiveArea(id: id) }
    }

    func archiveContainer(id: UUID) async -> ContainerSnapshot? {
        await performMutation { try await repository.archiveContainer(id: id) }
    }

    func archiveThing(id: UUID) async -> ThingSnapshot? {
        await performMutation { try await repository.archiveThing(id: id) }
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

    func resolveQRCode(_ token: QRToken) async throws -> QRCodeResolution {
        try await repository.resolve(token)
    }

    func replaceQRCode(_ token: QRToken, target: QRBindingTarget) async throws {
        try await repository.replaceQRCode(
            QRCodeBindingRequest(token: token, target: target)
        )
        try await reloadCatalog()
    }

    func repairQRCode(_ token: QRToken, target: QRBindingTarget) async throws {
        try await repository.repairQRCode(
            QRCodeBindingRequest(token: token, target: target)
        )
        try await reloadCatalog()
    }

    func repairAndReplaceQRCode(_ token: QRToken, target: QRBindingTarget) async throws {
        try await repository.repairAndReplaceQRCode(
            QRCodeBindingRequest(token: token, target: target)
        )
        try await reloadCatalog()
    }

    func releaseRepairableQRCode(_ token: QRToken) async throws {
        try await repository.releaseRepairableQRCode(token)
        try await reloadCatalog()
    }

    func repairQRCodeTargetIsEligible(
        _ token: QRToken,
        target: QRBindingTarget
    ) async -> Bool {
        (try? await repository.repairQRCodeTargetIsEligible(
            QRCodeBindingRequest(token: token, target: target)
        )) == true
    }

    func bind(_ token: QRToken, to target: QRAttachTargetSnapshot) async -> Bool {
        do {
            try await repository.bindQRCode(
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
        await performMutation {
            try await repository.createTargetAndBindQRCode(request)
        } != nil
    }

    func repairCreateTargetAndBind(_ request: CreateAndBindQRCodeRequest) async -> Bool {
        await performMutation {
            try await repository.repairCreateTargetAndBindQRCode(request)
        } != nil
    }

    func qrAttachTarget(for target: QRBindingTarget) -> QRAttachTargetSnapshot? {
        for place in activePlaces {
            switch target {
            case .area(let targetID):
                guard let area = place.activeAreas.first(where: { $0.id == targetID.rawValue }) else {
                    continue
                }
                return QRAttachTargetSnapshot(
                    id: area.id,
                    placeID: place.id,
                    kind: .area,
                    name: area.name,
                    locationComponents: Array(
                        place.locationComponents(for: .area(area.id)).dropLast()
                    )
                )
            case .container(let targetID):
                guard let container = place.activeContainers.first(where: { $0.id == targetID.rawValue }) else {
                    continue
                }
                return QRAttachTargetSnapshot(
                    id: container.id,
                    placeID: place.id,
                    kind: .container,
                    name: container.name,
                    locationComponents: Array(
                        place.locationComponents(for: .container(container.id)).dropLast()
                    )
                )
            }
        }
        return nil
    }

    func saveThing(
        name: String,
        keywords: [String],
        notes: String,
        photo: NormalizedPhoto?,
        to destination: ThingDestination,
        nameSource: String
    ) async -> ThingSnapshot? {
        await performMutation {
            try await repository.saveThing(
                ReviewedThingDraft(
                    name: name,
                    keywords: keywords,
                    notes: notes,
                    nameSource: nameSource,
                    photo: photo
                ),
                to: destination
            )
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
        refreshPlaceSharingStates()
    }

    private func refreshPlaceSharingStates() {
        let activePlaceIDs = activePlaces.map(\.id)
        guard !activePlaceIDs.isEmpty else {
            placeSharingStates = [:]
            return
        }

        let request = NSFetchRequest<Place>(entityName: "Place")
        request.predicate = NSPredicate(format: "id IN %@", activePlaceIDs)

        guard let managedPlaces = try? persistence.viewContext.fetch(request) else {
            placeSharingStates = [:]
            return
        }

        placeSharingStates = managedPlaces.reduce(into: [:]) { states, place in
            guard let id = place.id,
                let state = try? sharingService.state(for: place)
            else { return }
            states[id] = state
        }
    }

    private func performMutation<Result>(
        _ mutation: () async throws -> Result
    ) async -> Result? {
        do {
            let result = try await mutation()
            try await reloadCatalog()
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
