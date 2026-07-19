import CoreData
import Foundation

public final class CoreDataCatalogRepository: CatalogRepository, @unchecked Sendable {
    private let persistenceController: PersistenceController
    private let context: NSManagedObjectContext

    public init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
        context = persistenceController.newBackgroundContext(author: "witt.catalog")
    }

    public func fetchPlaces() async throws -> [PlaceSnapshot] {
        try ensurePersistenceLoaded()
        return try await context.perform { [context] in
            context.reset()
            return try Self.fetchPlaceSnapshots(in: context)
        }
    }

    @discardableResult
    public func seedHomeIfNeeded() async throws -> PlaceSnapshot? {
        try ensurePersistenceLoaded()
        return try await context.perform { [context, self] in
            context.reset()
            let request = NSFetchRequest<Place>(entityName: "Place")
            request.predicate = NSPredicate(format: "archivedAt == nil")
            request.fetchLimit = 1
            guard try context.count(for: request) == 0 else { return nil }

            do {
                let place: Place = try Self.insert("Place", into: context)
                place.name = "Home"

                let inserted = Array(context.insertedObjects)
                if persistenceController.usesCloudKit {
                    for object in inserted {
                        try persistenceController.assign(object, to: .private)
                    }
                }
                for object in inserted {
                    try Self.validateInsertedObject(object)
                }
                try context.save()
                return try Self.snapshot(place)
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func createPlace(_ draft: CreatePlaceDraft) async throws -> PlaceSnapshot {
        try ensurePersistenceLoaded()
        return try await context.perform { [context, self] in
            context.reset()
            do {
                let place: Place = try Self.insert("Place", into: context)
                place.name = try Self.requiredName(draft.name)
                place.notes = Self.nilIfEmpty(draft.notes)
                if let photo = draft.photo {
                    try Self.applyPhotoMutation(.replace(photo), to: .place(place), in: context)
                }
                place.updatedAt = Date()

                if persistenceController.usesCloudKit {
                    for object in context.insertedObjects {
                        try persistenceController.assign(object, to: .private)
                    }
                }
                try Self.validateChanges(in: context)
                try context.save()
                return try Self.snapshot(place)
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func createRoom(_ draft: CreateRoomDraft) async throws -> RoomSnapshot {
        try ensurePersistenceLoaded()
        return try await context.perform { [context] in
            context.reset()
            do {
                let place: Place = try Self.fetchActive(
                    id: draft.placeID, entityName: "Place", in: context, notFound: .placeNotFound
                )
                let room: Room = try Self.insert("Room", into: context)
                room.name = try Self.requiredName(draft.name)
                room.sortOrder = Self.nextSortOrder(
                    in: Self.managedObjects(place.rooms, as: Room.self).map(\.sortOrder)
                )
                room.place = place
                room.updatedAt = Date()
                Self.assignInsertions(in: context, toStoreOf: place)
                try Self.validateChanges(in: context)
                try context.save()
                return try Self.snapshot(room)
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func createArea(_ draft: CreateAreaDraft) async throws -> AreaSnapshot {
        try ensurePersistenceLoaded()
        return try await context.perform { [context] in
            context.reset()
            do {
                let room: Room = try Self.fetchOne(
                    id: draft.roomID, entityName: "Room", in: context, notFound: .roomNotFound
                )
                guard Self.isActive(room), let place = room.place else {
                    throw CatalogRepositoryError.roomNotFound
                }
                if let qrToken = draft.qrToken {
                    guard try Self.fetchQRCodes(token: qrToken.rawValue, in: context).isEmpty else {
                        throw CatalogRepositoryError.tokenAlreadyBound
                    }
                }
                let area: Area = try Self.insert("Area", into: context)
                area.name = try Self.requiredName(draft.name)
                area.detail = Self.nilIfEmpty(draft.detail)
                area.sortOrder = Self.nextSortOrder(
                    in: Self.managedObjects(room.areas, as: Area.self).map(\.sortOrder)
                )
                area.room = room
                area.place = place
                if let photo = draft.photo {
                    try Self.applyPhotoMutation(.replace(photo), to: .area(area), in: context)
                }
                if let qrToken = draft.qrToken {
                    try Self.insertQRCode(
                        qrToken,
                        for: .area(area, place, try Self.requiredID(area.id)),
                        in: context
                    )
                }
                area.updatedAt = Date()
                Self.assignInsertions(in: context, toStoreOf: place)
                try Self.validateChanges(in: context)
                try context.save()
                return try Self.snapshot(area)
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func createContainer(_ draft: CreateContainerDraft) async throws -> ContainerSnapshot {
        try ensurePersistenceLoaded()
        return try await context.perform { [context] in
            context.reset()
            do {
                let parent = try Self.fetchContainerDestination(draft.destination, in: context)
                if let qrToken = draft.qrToken {
                    guard try Self.fetchQRCodes(token: qrToken.rawValue, in: context).isEmpty else {
                        throw CatalogRepositoryError.tokenAlreadyBound
                    }
                }
                let container: Container = try Self.insert("Container", into: context)
                container.name = try Self.requiredName(draft.name)
                container.detail = Self.nilIfEmpty(draft.detail)
                container.sortOrder = Self.nextSortOrder(in: parent.childSortOrders)
                container.place = parent.place
                parent.apply(to: container)
                if let photo = draft.photo {
                    try Self.applyPhotoMutation(.replace(photo), to: .container(container), in: context)
                }
                if let qrToken = draft.qrToken {
                    try Self.insertQRCode(
                        qrToken,
                        for: .container(
                            container,
                            parent.place,
                            try Self.requiredID(container.id)
                        ),
                        in: context
                    )
                }
                container.updatedAt = Date()
                Self.assignInsertions(in: context, toStoreOf: parent.place)
                try Self.validateChanges(in: context)
                try context.save()
                return try Self.snapshot(container)
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func updatePlace(id: UUID, with draft: UpdatePlaceDraft) async throws -> PlaceSnapshot {
        try ensurePersistenceLoaded()
        return try await context.perform { [context] in
            context.reset()
            do {
                let place: Place = try Self.fetchActive(
                    id: id, entityName: "Place", in: context, notFound: .placeNotFound
                )
                place.name = try Self.requiredName(draft.name)
                place.notes = Self.nilIfEmpty(draft.notes)
                try Self.applyPhotoMutation(draft.photo, to: .place(place), in: context)
                place.updatedAt = Date()
                Self.assignInsertions(in: context, toStoreOf: place)
                try Self.validateChanges(in: context)
                try context.save()
                return try Self.snapshot(place)
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func updateRoom(id: UUID, with draft: UpdateRoomDraft) async throws -> RoomSnapshot {
        try ensurePersistenceLoaded()
        return try await context.perform { [context] in
            context.reset()
            do {
                let room: Room = try Self.fetchOne(
                    id: id, entityName: "Room", in: context, notFound: .roomNotFound
                )
                guard Self.isActive(room) else { throw CatalogRepositoryError.roomNotFound }
                room.name = try Self.requiredName(draft.name)
                room.updatedAt = Date()
                try Self.validateChanges(in: context)
                try context.save()
                return try Self.snapshot(room)
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func updateArea(id: UUID, with draft: UpdateAreaDraft) async throws -> AreaSnapshot {
        try ensurePersistenceLoaded()
        return try await context.perform { [context] in
            context.reset()
            do {
                let area: Area = try Self.fetchOne(
                    id: id, entityName: "Area", in: context, notFound: .areaNotFound
                )
                guard Self.isActive(area), let place = area.place else {
                    throw CatalogRepositoryError.areaNotFound
                }
                let room: Room = try Self.fetchOne(
                    id: draft.roomID, entityName: "Room", in: context, notFound: .destinationNotFound
                )
                guard Self.isActive(room) else { throw CatalogRepositoryError.destinationNotFound }
                guard room.place === place else { throw CatalogRepositoryError.crossPlaceMove }

                area.name = try Self.requiredName(draft.name)
                area.detail = Self.nilIfEmpty(draft.detail)
                area.room = room
                try Self.applyPhotoMutation(draft.photo, to: .area(area), in: context)
                area.updatedAt = Date()
                Self.assignInsertions(in: context, toStoreOf: place)
                try Self.validateChanges(in: context)
                try context.save()
                return try Self.snapshot(area)
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func updateContainer(id: UUID, with draft: UpdateContainerDraft) async throws -> ContainerSnapshot {
        try ensurePersistenceLoaded()
        return try await context.perform { [context] in
            context.reset()
            do {
                let container: Container = try Self.fetchOne(
                    id: id, entityName: "Container", in: context, notFound: .containerNotFound
                )
                guard Self.isActive(container), let place = container.place else {
                    throw CatalogRepositoryError.containerNotFound
                }
                let parent = try Self.fetchContainerDestination(draft.destination, in: context)
                guard parent.place === place else { throw CatalogRepositoryError.crossPlaceMove }
                if case .container = draft.destination {
                    do {
                        try Self.validateContainerMove(container, to: parent)
                    } catch DomainValidationError.containerCycle {
                        throw CatalogRepositoryError.containerCycle
                    }
                }

                container.name = try Self.requiredName(draft.name)
                container.detail = Self.nilIfEmpty(draft.detail)
                parent.apply(to: container)
                try Self.applyPhotoMutation(draft.photo, to: .container(container), in: context)
                container.updatedAt = Date()
                Self.assignInsertions(in: context, toStoreOf: place)
                try Self.validateChanges(in: context)
                try context.save()
                return try Self.snapshot(container)
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func updateThing(id: UUID, with draft: UpdateThingDraft) async throws -> ThingSnapshot {
        try ensurePersistenceLoaded()
        return try await context.perform { [context] in
            context.reset()
            do {
                let thing: Thing = try Self.fetchOne(
                    id: id, entityName: "Thing", in: context, notFound: .thingNotFound
                )
                guard Self.isActive(thing), let place = thing.place else {
                    throw CatalogRepositoryError.thingNotFound
                }
                let home = try Self.fetchHome(draft.destination, in: context)
                guard home.place === place else { throw CatalogRepositoryError.crossPlaceMove }

                let name = try Self.requiredName(draft.name)
                let keywords = Self.normalizeKeywords(draft.keywords)
                thing.name = name
                thing.detail = Self.nilIfEmpty(draft.notes)
                thing.homeRoom = nil
                thing.homeArea = nil
                thing.homeContainer = nil
                home.apply(to: thing)
                for keyword in Self.managedObjects(thing.keywords, as: ThingKeyword.self) {
                    context.delete(keyword)
                }
                for displayValue in keywords {
                    let keyword: ThingKeyword = try Self.insert("ThingKeyword", into: context)
                    keyword.displayValue = displayValue
                    keyword.normalizedValue = Self.searchNormalized(displayValue)
                    keyword.source = thing.nameSource
                    keyword.place = place
                    keyword.thing = thing
                }
                thing.searchTextNormalized = Self.searchNormalized(
                    ([name] + keywords + [thing.detail].compactMap { $0 }).joined(separator: " ")
                )
                try Self.applyPhotoMutation(draft.photo, to: .thing(thing), in: context)
                thing.updatedAt = Date()
                Self.assignInsertions(in: context, toStoreOf: place)
                try Self.validateChanges(in: context)
                try context.save()
                return try Self.snapshot(thing)
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func archivePlace(id: UUID) async throws -> PlaceSnapshot {
        try ensurePersistenceLoaded()
        return try await context.perform { [context] in
            context.reset()
            do {
                let place: Place = try Self.fetchActive(
                    id: id, entityName: "Place", in: context, notFound: .placeNotFound
                )
                let objects: [NSManagedObject] = [place]
                    + Self.managedObjects(place.rooms, as: Room.self)
                    + Self.managedObjects(place.areas, as: Area.self)
                    + Self.managedObjects(place.containers, as: Container.self)
                    + Self.managedObjects(place.things, as: Thing.self)
                Self.archive(objects, at: Date())
                try Self.validateChanges(in: context)
                try context.save()
                return try Self.snapshot(place)
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func archiveRoom(id: UUID) async throws -> RoomSnapshot {
        try ensurePersistenceLoaded()
        return try await context.perform { [context] in
            context.reset()
            do {
                let room: Room = try Self.fetchOne(
                    id: id, entityName: "Room", in: context, notFound: .roomNotFound
                )
                guard Self.isActive(room) else { throw CatalogRepositoryError.roomNotFound }
                Self.archive(Self.archiveSubtree(for: room), at: Date())
                try Self.validateChanges(in: context)
                try context.save()
                return try Self.snapshot(room)
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func archiveArea(id: UUID) async throws -> AreaSnapshot {
        try ensurePersistenceLoaded()
        return try await context.perform { [context] in
            context.reset()
            do {
                let area: Area = try Self.fetchOne(
                    id: id, entityName: "Area", in: context, notFound: .areaNotFound
                )
                guard Self.isActive(area) else { throw CatalogRepositoryError.areaNotFound }
                Self.archive(Self.archiveSubtree(for: area), at: Date())
                try Self.validateChanges(in: context)
                try context.save()
                return try Self.snapshot(area)
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func archiveContainer(id: UUID) async throws -> ContainerSnapshot {
        try ensurePersistenceLoaded()
        return try await context.perform { [context] in
            context.reset()
            do {
                let container: Container = try Self.fetchOne(
                    id: id, entityName: "Container", in: context, notFound: .containerNotFound
                )
                guard Self.isActive(container) else { throw CatalogRepositoryError.containerNotFound }
                Self.archive(Self.archiveSubtree(for: container), at: Date())
                try Self.validateChanges(in: context)
                try context.save()
                return try Self.snapshot(container)
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func archiveThing(id: UUID) async throws -> ThingSnapshot {
        try ensurePersistenceLoaded()
        return try await context.perform { [context] in
            context.reset()
            do {
                let thing: Thing = try Self.fetchOne(
                    id: id, entityName: "Thing", in: context, notFound: .thingNotFound
                )
                guard Self.isActive(thing) else { throw CatalogRepositoryError.thingNotFound }
                Self.archive([thing], at: Date())
                try Self.validateChanges(in: context)
                try context.save()
                return try Self.snapshot(thing)
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func saveThing(
        _ draft: ReviewedThingDraft,
        to destination: ThingDestination
    ) async throws -> ThingSnapshot {
        try ensurePersistenceLoaded()
        return try await context.perform { [context] in
            context.reset()
            do {
                let normalizedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedSource = draft.nameSource.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedName.isEmpty, !normalizedSource.isEmpty else {
                    throw CatalogRepositoryError.invalidDraft
                }

                let home = try Self.fetchHome(destination, in: context)
                let thing: Thing = try Self.insert("Thing", into: context)
                thing.name = normalizedName
                thing.detail = Self.nilIfEmpty(draft.notes)
                thing.nameSource = normalizedSource
                thing.place = home.place
                home.apply(to: thing)

                let normalizedKeywords = Self.normalizeKeywords(draft.keywords)
                for displayValue in normalizedKeywords {
                    let keyword: ThingKeyword = try Self.insert("ThingKeyword", into: context)
                    keyword.displayValue = displayValue
                    keyword.normalizedValue = Self.searchNormalized(displayValue)
                    keyword.source = normalizedSource
                    keyword.place = home.place
                    keyword.thing = thing
                }
                thing.searchTextNormalized = Self.searchNormalized(
                    ([normalizedName] + normalizedKeywords + [thing.detail].compactMap { $0 }).joined(separator: " ")
                )

                if let photoDraft = draft.photo {
                    try Self.applyPhotoMutation(.replace(photoDraft), to: .thing(thing), in: context)
                }

                Self.assignInsertions(in: context, toStoreOf: home.place)
                try Self.validateChanges(in: context)
                try context.save()
                return try Self.snapshot(thing)
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func unassignedQRCodeTargets() async throws -> [QRAttachTargetSnapshot] {
        try ensurePersistenceLoaded()
        return try await context.perform { [context] in
            context.reset()
            let areas = try context.fetch(NSFetchRequest<Area>(entityName: "Area"))
                .filter { Self.isActive($0) && Self.boundQRCodes(of: $0.qrCodes).isEmpty }
                .compactMap(Self.attachTarget(for:))
            let containers = try context.fetch(NSFetchRequest<Container>(entityName: "Container"))
                .filter { Self.isActive($0) && Self.boundQRCodes(of: $0.qrCodes).isEmpty }
                .compactMap(Self.attachTarget(for:))
            return (areas + containers).sorted(by: Self.attachTargetSort)
        }
    }

    public func bindQRCode(_ request: QRCodeBindingRequest) async throws {
        try ensurePersistenceLoaded()
        try await context.perform { [context] in
            context.reset()
            do {
                let existing = try Self.fetchQRCodes(token: request.token.rawValue, in: context)
                if existing.count == 1,
                   existing[0].state == "bound",
                   Self.bindingTarget(for: existing[0]) == Self.rawTarget(request.target)
                {
                    return
                }
                guard existing.isEmpty else {
                    throw CatalogRepositoryError.tokenAlreadyBound
                }

                let target = try Self.fetchQRTarget(request.target, in: context)
                guard Self.boundQRCodes(of: target.qrCodes).isEmpty else {
                    throw CatalogRepositoryError.targetAlreadyHasQRCode
                }

                try Self.insertQRCode(request.token, for: target, in: context)
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func replaceQRCode(_ request: QRCodeBindingRequest) async throws {
        try ensurePersistenceLoaded()
        try await context.perform { [context] in
            context.reset()
            do {
                let target = try Self.fetchQRTarget(request.target, in: context)
                let existing = try Self.fetchQRCodes(token: request.token.rawValue, in: context)
                let isSameTarget = existing.count == 1
                    && existing[0].state == "bound"
                    && existing[0].place === target.place
                    && Self.bindingTarget(for: existing[0]) == target.target

                guard existing.isEmpty || isSameTarget else {
                    throw CatalogRepositoryError.tokenAlreadyBound
                }

                let retainedQRCode = isSameTarget ? existing[0] : nil
                for qrCode in Self.managedObjects(target.qrCodes, as: QRCode.self)
                    where qrCode !== retainedQRCode
                {
                    context.delete(qrCode)
                }
                if retainedQRCode == nil {
                    try Self.insertQRCode(request.token, for: target, in: context)
                }

                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func repairQRCode(_ request: QRCodeBindingRequest) async throws {
        try await repairQRCode(request, replacingTargetQRCode: false)
    }

    public func repairAndReplaceQRCode(
        _ request: QRCodeBindingRequest
    ) async throws {
        try await repairQRCode(request, replacingTargetQRCode: true)
    }

    private func repairQRCode(
        _ request: QRCodeBindingRequest,
        replacingTargetQRCode: Bool
    ) async throws {
        try ensurePersistenceLoaded()
        try await context.perform { [context] in
            context.reset()
            do {
                let repairRows = try Self.fetchQRCodes(
                    token: request.token.rawValue,
                    in: context
                )
                try Self.requireRepairable(repairRows)

                let target = try Self.fetchQRTarget(request.target, in: context)
                if !replacingTargetQRCode {
                    try Self.requireRepairTargetAvailable(
                        target,
                        for: request.token,
                        in: context
                    )
                }
                try Self.consolidate(
                    repairRows,
                    token: request.token,
                    onto: target,
                    in: context
                )

                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func repairQRCodeTargetIsEligible(
        _ request: QRCodeBindingRequest
    ) async throws -> Bool {
        try ensurePersistenceLoaded()
        return try await context.perform { [context] in
            context.reset()
            let repairRows = try Self.fetchQRCodes(
                token: request.token.rawValue,
                in: context
            )
            try Self.requireRepairable(repairRows)
            let target = try Self.fetchQRTarget(request.target, in: context)
            do {
                try Self.requireRepairTargetAvailable(
                    target,
                    for: request.token,
                    in: context
                )
                return true
            } catch CatalogRepositoryError.targetAlreadyHasQRCode {
                return false
            }
        }
    }

    public func releaseRepairableQRCode(_ token: QRToken) async throws {
        try ensurePersistenceLoaded()
        try await context.perform { [context] in
            context.reset()
            do {
                let repairRows = try Self.fetchQRCodes(token: token.rawValue, in: context)
                try Self.requireRepairable(repairRows)
                repairRows.forEach(context.delete)
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    @discardableResult
    public func createTargetAndBindQRCode(
        _ request: CreateAndBindQRCodeRequest
    ) async throws -> QRAttachTargetSnapshot {
        try ensurePersistenceLoaded()
        return try await context.perform { [context] in
            context.reset()
            do {
                guard try Self.fetchQRCodes(token: request.token.rawValue, in: context).isEmpty else {
                    throw CatalogRepositoryError.tokenAlreadyBound
                }

                let place: Place = try Self.fetchOne(
                    id: request.placeID,
                    entityName: "Place",
                    in: context,
                    notFound: .targetNotFound
                )
                guard place.archivedAt == nil else {
                    throw CatalogRepositoryError.targetNotFound
                }
                let room = try Self.resolveRoom(request.room, in: place, context: context)
                let area = try Self.resolveArea(request.area, in: room, place: place, context: context)
                let target = try Self.resolveAttachment(
                    request.attachment,
                    in: area,
                    place: place,
                    context: context
                )
                guard Self.boundQRCodes(of: target.qrCodes).isEmpty else {
                    throw CatalogRepositoryError.targetAlreadyHasQRCode
                }

                try Self.insertQRCode(request.token, for: target, in: context)

                let inserted = Array(context.insertedObjects)
                if let store = place.objectID.persistentStore {
                    for object in inserted {
                        context.assign(object, to: store)
                    }
                }
                for object in inserted {
                    try Self.validateInsertedObject(object)
                }
                let targetSnapshot: QRAttachTargetSnapshot
                switch target.target {
                case .area:
                    guard let snapshot = Self.attachTarget(for: area) else {
                        throw CatalogRepositoryError.invalidStoredHierarchy
                    }
                    targetSnapshot = snapshot
                case .container:
                    let container = try context.existingObject(with: target.objectID) as! Container
                    guard let snapshot = Self.attachTarget(for: container) else {
                        throw CatalogRepositoryError.invalidStoredHierarchy
                    }
                    targetSnapshot = snapshot
                }
                try context.save()
                return targetSnapshot
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    @discardableResult
    public func repairCreateTargetAndBindQRCode(
        _ request: CreateAndBindQRCodeRequest
    ) async throws -> QRAttachTargetSnapshot {
        try ensurePersistenceLoaded()
        return try await context.perform { [context] in
            context.reset()
            do {
                let repairRows = try Self.fetchQRCodes(
                    token: request.token.rawValue,
                    in: context
                )
                try Self.requireRepairable(repairRows)

                let place: Place = try Self.fetchOne(
                    id: request.placeID,
                    entityName: "Place",
                    in: context,
                    notFound: .targetNotFound
                )
                guard place.archivedAt == nil else {
                    throw CatalogRepositoryError.targetNotFound
                }
                let room = try Self.resolveRoom(request.room, in: place, context: context)
                let area = try Self.resolveArea(request.area, in: room, place: place, context: context)
                let target = try Self.resolveAttachment(
                    request.attachment,
                    in: area,
                    place: place,
                    context: context
                )
                try Self.requireRepairTargetAvailable(
                    target,
                    for: request.token,
                    in: context
                )
                try Self.consolidate(
                    repairRows,
                    token: request.token,
                    onto: target,
                    in: context
                )

                let inserted = Array(context.insertedObjects)
                if let store = place.objectID.persistentStore {
                    for object in inserted {
                        context.assign(object, to: store)
                    }
                }
                for object in inserted {
                    try Self.validateInsertedObject(object)
                }

                let targetSnapshot: QRAttachTargetSnapshot
                switch target.target {
                case .area:
                    guard let snapshot = Self.attachTarget(for: area) else {
                        throw CatalogRepositoryError.invalidStoredHierarchy
                    }
                    targetSnapshot = snapshot
                case .container:
                    let container = try context.existingObject(with: target.objectID) as! Container
                    guard let snapshot = Self.attachTarget(for: container) else {
                        throw CatalogRepositoryError.invalidStoredHierarchy
                    }
                    targetSnapshot = snapshot
                }
                try context.save()
                return targetSnapshot
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    public func resolve(_ token: QRToken) async throws -> QRCodeResolution {
        try ensurePersistenceLoaded()
        let storedResolution = try await context.perform { [context] in
            context.reset()
            let rows = try Self.fetchQRCodes(token: token.rawValue, in: context)
            return Self.storedResolution(for: rows)
        }
        return Self.publicResolution(storedResolution)
    }

    private func ensurePersistenceLoaded() throws {
        guard persistenceController.isLoaded, persistenceController.loadError == nil else {
            throw CatalogRepositoryError.persistenceNotLoaded
        }
    }
}

extension CoreDataCatalogRepository {
    nonisolated static func insert<T: NSManagedObject>(
        _ entityName: String,
        into context: NSManagedObjectContext
    ) throws -> T {
        guard let entity = NSEntityDescription.entity(forEntityName: entityName, in: context) else {
            throw CatalogRepositoryError.invalidManagedObjectModel
        }

        let expectedClassName = NSStringFromClass(T.self)
        guard
            entity.managedObjectClassName == expectedClassName,
            let runtimeClass = NSClassFromString(expectedClassName),
            runtimeClass === T.self
        else {
            throw CatalogRepositoryError.invalidManagedObjectModel
        }

        return T(entity: entity, insertInto: context)
    }
}

private extension CoreDataCatalogRepository {
    enum RawQRTarget: Hashable, Sendable {
        case area(UUID)
        case container(UUID)
    }

    enum StoredQRResolution: Sendable {
        case unknown
        case known(RawQRTarget)
        case repair(QRCodeRepairReason)
        case conflict([RawQRTarget])
    }

    enum HomeObject {
        case room(Room, Place)
        case area(Area, Place)
        case container(Container, Place)

        var place: Place {
            switch self {
            case .room(_, let place), .area(_, let place), .container(_, let place):
                place
            }
        }

        func apply(to thing: Thing) {
            switch self {
            case .room(let room, _):
                thing.homeRoom = room
            case .area(let area, _):
                thing.homeArea = area
            case .container(let container, _):
                thing.homeContainer = container
            }
        }
    }

    struct ContainerParentObject {
        enum Parent {
            case room(Room)
            case area(Area)
            case container(Container)
        }

        let parent: Parent
        let place: Place
        let childSortOrders: [Int32]

        var containerParent: Container? {
            guard case .container(let container) = parent else { return nil }
            return container
        }

        func apply(to container: Container) {
            container.parentRoom = nil
            container.parentArea = nil
            container.parentContainer = nil
            switch parent {
            case .room(let room):
                container.parentRoom = room
            case .area(let area):
                container.parentArea = area
            case .container(let parent):
                container.parentContainer = parent
            }
        }
    }

    enum PhotoOwnerObject {
        case place(Place)
        case area(Area)
        case container(Container)
        case thing(Thing)

        var place: Place? {
            switch self {
            case .place(let owner): owner
            case .area(let owner): owner.place
            case .container(let owner): owner.place
            case .thing(let owner): owner.place
            }
        }

        var primaryPhoto: PhotoAsset? {
            get {
                switch self {
                case .place(let owner): owner.primaryPhoto
                case .area(let owner): owner.primaryPhoto
                case .container(let owner): owner.primaryPhoto
                case .thing(let owner): owner.primaryPhoto
                }
            }
            nonmutating set {
                switch self {
                case .place(let owner): owner.primaryPhoto = newValue
                case .area(let owner): owner.primaryPhoto = newValue
                case .container(let owner): owner.primaryPhoto = newValue
                case .thing(let owner): owner.primaryPhoto = newValue
                }
            }
        }

        func apply(to photo: PhotoAsset) {
            switch self {
            case .place(let owner): photo.placeOwner = owner
            case .area(let owner): photo.areaOwner = owner
            case .container(let owner): photo.containerOwner = owner
            case .thing(let owner): photo.thingOwner = owner
            }
            primaryPhoto = photo
        }
    }

    enum QRTargetObject {
        case area(Area, Place, UUID)
        case container(Container, Place, UUID)

        var objectID: NSManagedObjectID {
            switch self {
            case .area(let area, _, _): area.objectID
            case .container(let container, _, _): container.objectID
            }
        }

        var place: Place {
            switch self {
            case .area(_, let place, _), .container(_, let place, _): place
            }
        }

        var qrCodes: NSSet? {
            switch self {
            case .area(let area, _, _): area.qrCodes
            case .container(let container, _, _): container.qrCodes
            }
        }

        var target: RawQRTarget {
            switch self {
            case .area(_, _, let id): .area(id)
            case .container(_, _, let id): .container(id)
            }
        }

        func apply(to qrCode: QRCode) {
            switch self {
            case .area(let area, _, _):
                qrCode.area = area
            case .container(let container, _, _):
                qrCode.container = container
            }
        }
    }

    nonisolated static func fetchPlaceSnapshots(in context: NSManagedObjectContext) throws -> [PlaceSnapshot] {
        let request = NSFetchRequest<Place>(entityName: "Place")
        request.relationshipKeyPathsForPrefetching = [
            "rooms", "areas", "containers", "things", "things.keywords",
            "primaryPhoto", "areas.primaryPhoto", "containers.primaryPhoto", "things.primaryPhoto"
        ]
        return try context.fetch(request).map(snapshot).sorted {
            compare(name: $0.name, id: $0.id, name: $1.name, id: $1.id)
        }
    }

    nonisolated static func snapshot(_ place: Place) throws -> PlaceSnapshot {
        guard let id = place.id else { throw CatalogRepositoryError.missingIdentity }
        let rooms = try managedObjects(place.rooms, as: Room.self).map(snapshot).sorted(by: roomSort)
        let areas = try managedObjects(place.areas, as: Area.self).map(snapshot).sorted(by: areaSort)
        let containers = try managedObjects(place.containers, as: Container.self).map(snapshot).sorted(by: containerSort)
        let things = try managedObjects(place.things, as: Thing.self).map(snapshot).sorted(by: thingSort)
        return PlaceSnapshot(
            id: id,
            name: place.name,
            notes: place.notes,
            createdAt: place.createdAt,
            updatedAt: place.updatedAt,
            archivedAt: place.archivedAt,
            primaryPhoto: try place.primaryPhoto.map(snapshot),
            rooms: rooms,
            areas: areas,
            containers: containers,
            things: things
        )
    }

    nonisolated static func snapshot(_ room: Room) throws -> RoomSnapshot {
        guard let id = room.id, let placeID = room.place?.id else {
            throw CatalogRepositoryError.invalidStoredHierarchy
        }
        return RoomSnapshot(id: id, placeID: placeID, name: room.name, sortOrder: Int(room.sortOrder), archivedAt: room.archivedAt)
    }

    nonisolated static func snapshot(_ area: Area) throws -> AreaSnapshot {
        guard let id = area.id, let placeID = area.place?.id, let roomID = area.room?.id else {
            throw CatalogRepositoryError.invalidStoredHierarchy
        }
        return AreaSnapshot(
            id: id, placeID: placeID, roomID: roomID, name: area.name, detail: area.detail,
            sortOrder: Int(area.sortOrder), archivedAt: area.archivedAt,
            primaryPhoto: try area.primaryPhoto.map(snapshot), hasQRCode: !boundQRCodes(of: area.qrCodes).isEmpty
        )
    }

    nonisolated static func snapshot(_ container: Container) throws -> ContainerSnapshot {
        guard let id = container.id, let placeID = container.place?.id else {
            throw CatalogRepositoryError.invalidStoredHierarchy
        }
        let parents: [ContainerSnapshotParent] = [
            container.parentRoom?.id.map(ContainerSnapshotParent.room),
            container.parentArea?.id.map(ContainerSnapshotParent.area),
            container.parentContainer?.id.map(ContainerSnapshotParent.container)
        ].compactMap { $0 }
        guard parents.count == 1 else { throw CatalogRepositoryError.invalidStoredHierarchy }
        return ContainerSnapshot(
            id: id, placeID: placeID, name: container.name, detail: container.detail,
            sortOrder: Int(container.sortOrder), archivedAt: container.archivedAt, parent: parents[0],
            primaryPhoto: try container.primaryPhoto.map(snapshot), hasQRCode: !boundQRCodes(of: container.qrCodes).isEmpty
        )
    }

    nonisolated static func snapshot(_ thing: Thing) throws -> ThingSnapshot {
        guard let id = thing.id, let placeID = thing.place?.id else {
            throw CatalogRepositoryError.invalidStoredHierarchy
        }
        let homes: [ThingSnapshotHome] = [
            thing.homeRoom?.id.map(ThingSnapshotHome.room),
            thing.homeArea?.id.map(ThingSnapshotHome.area),
            thing.homeContainer?.id.map(ThingSnapshotHome.container)
        ].compactMap { $0 }
        guard homes.count == 1 else { throw CatalogRepositoryError.invalidStoredHierarchy }
        let keywords = managedObjects(thing.keywords, as: ThingKeyword.self)
            .map(\.displayValue)
            .sorted(by: stringSort)
        return ThingSnapshot(
            id: id, placeID: placeID, name: thing.name, keywords: keywords, notes: thing.detail,
            nameSource: thing.nameSource, home: homes[0], createdAt: thing.createdAt,
            updatedAt: thing.updatedAt, archivedAt: thing.archivedAt,
            primaryPhoto: try thing.primaryPhoto.map(snapshot)
        )
    }

    nonisolated static func snapshot(_ photo: PhotoAsset) throws -> PhotoAssetSnapshot {
        guard let id = photo.id else { throw CatalogRepositoryError.missingIdentity }
        return PhotoAssetSnapshot(
            id: id, data: photo.data, thumbnailData: photo.thumbnailData,
            contentType: photo.contentType, pixelWidth: Int(photo.pixelWidth),
            pixelHeight: Int(photo.pixelHeight), byteSize: Int(photo.byteSize), capturedAt: photo.capturedAt
        )
    }

    nonisolated static func fetchHome(_ destination: ThingDestination, in context: NSManagedObjectContext) throws -> HomeObject {
        switch destination {
        case .room(let id):
            let room: Room = try fetchOne(id: id, entityName: "Room", in: context)
            guard isActive(room), let place = room.place else {
                throw CatalogRepositoryError.destinationNotFound
            }
            return .room(room, place)
        case .area(let id):
            let area: Area = try fetchOne(id: id, entityName: "Area", in: context)
            guard isActive(area), let place = area.place else {
                throw CatalogRepositoryError.destinationNotFound
            }
            return .area(area, place)
        case .container(let id):
            let container: Container = try fetchOne(id: id, entityName: "Container", in: context)
            guard isActive(container), let place = container.place else {
                throw CatalogRepositoryError.destinationNotFound
            }
            return .container(container, place)
        }
    }

    nonisolated static func fetchContainerDestination(
        _ destination: ContainerDestination,
        in context: NSManagedObjectContext
    ) throws -> ContainerParentObject {
        switch destination {
        case .room(let id):
            let room: Room = try fetchOne(id: id, entityName: "Room", in: context)
            guard isActive(room), let place = room.place else {
                throw CatalogRepositoryError.destinationNotFound
            }
            return ContainerParentObject(
                parent: .room(room),
                place: place,
                childSortOrders: managedObjects(room.containers, as: Container.self).map(\.sortOrder)
            )
        case .area(let id):
            let area: Area = try fetchOne(id: id, entityName: "Area", in: context)
            guard isActive(area), let place = area.place else {
                throw CatalogRepositoryError.destinationNotFound
            }
            return ContainerParentObject(
                parent: .area(area),
                place: place,
                childSortOrders: managedObjects(area.containers, as: Container.self).map(\.sortOrder)
            )
        case .container(let id):
            let parent: Container = try fetchOne(id: id, entityName: "Container", in: context)
            guard isActive(parent), let place = parent.place else {
                throw CatalogRepositoryError.destinationNotFound
            }
            return ContainerParentObject(
                parent: .container(parent),
                place: place,
                childSortOrders: managedObjects(parent.childContainers, as: Container.self).map(\.sortOrder)
            )
        }
    }

    nonisolated static func fetchQRTarget(_ target: QRBindingTarget, in context: NSManagedObjectContext) throws -> QRTargetObject {
        switch target {
        case .area(let id):
            let area: Area = try fetchOne(id: id.rawValue, entityName: "Area", in: context, notFound: .targetNotFound)
            guard isActive(area), let place = area.place else {
                throw CatalogRepositoryError.targetNotFound
            }
            return .area(area, place, id.rawValue)
        case .container(let id):
            let container: Container = try fetchOne(id: id.rawValue, entityName: "Container", in: context, notFound: .targetNotFound)
            guard isActive(container), let place = container.place else {
                throw CatalogRepositoryError.targetNotFound
            }
            return .container(container, place, id.rawValue)
        }
    }

    nonisolated static func resolveRoom(
        _ selection: RoomSelection,
        in place: Place,
        context: NSManagedObjectContext
    ) throws -> Room {
        switch selection {
        case .existing(let id):
            let room: Room = try fetchOne(id: id, entityName: "Room", in: context, notFound: .targetNotFound)
            guard isActive(room), room.place === place else {
                throw CatalogRepositoryError.selectionDoesNotBelongToParent
            }
            return room
        case .new(let name):
            let normalizedName = try requiredName(name)
            let room: Room = try insert("Room", into: context)
            room.name = normalizedName
            room.sortOrder = nextSortOrder(in: managedObjects(place.rooms, as: Room.self).map(\.sortOrder))
            room.place = place
            return room
        }
    }

    nonisolated static func resolveArea(
        _ selection: AreaSelection,
        in room: Room,
        place: Place,
        context: NSManagedObjectContext
    ) throws -> Area {
        switch selection {
        case .existing(let id):
            let area: Area = try fetchOne(id: id, entityName: "Area", in: context, notFound: .targetNotFound)
            guard isActive(area), area.room === room, area.place === place else {
                throw CatalogRepositoryError.selectionDoesNotBelongToParent
            }
            return area
        case .new(let name):
            let normalizedName = try requiredName(name)
            let area: Area = try insert("Area", into: context)
            area.name = normalizedName
            area.sortOrder = nextSortOrder(in: managedObjects(room.areas, as: Area.self).map(\.sortOrder))
            area.room = room
            area.place = place
            return area
        }
    }

    nonisolated static func resolveAttachment(
        _ selection: QRCodeAttachmentSelection,
        in area: Area,
        place: Place,
        context: NSManagedObjectContext
    ) throws -> QRTargetObject {
        switch selection {
        case .area:
            guard isActive(area) else { throw CatalogRepositoryError.targetNotFound }
            return .area(area, place, try requiredID(area.id))
        case .existingContainer(let id):
            let container: Container = try fetchOne(
                id: id,
                entityName: "Container",
                in: context,
                notFound: .targetNotFound
            )
            guard isActive(container), container.place === place, rootArea(of: container) === area else {
                throw CatalogRepositoryError.selectionDoesNotBelongToParent
            }
            return .container(container, place, id)
        case .newContainer(let name):
            let container: Container = try insert("Container", into: context)
            container.name = try requiredName(name)
            container.sortOrder = nextSortOrder(
                in: managedObjects(area.containers, as: Container.self).map(\.sortOrder)
            )
            container.parentArea = area
            container.place = place
            guard let id = container.id else { throw CatalogRepositoryError.missingIdentity }
            return .container(container, place, id)
        }
    }

    nonisolated static func fetchOne<T: NSManagedObject>(
        id: UUID,
        entityName: String,
        in context: NSManagedObjectContext,
        notFound: CatalogRepositoryError = .destinationNotFound
    ) throws -> T {
        let request = NSFetchRequest<T>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 2
        let results = try context.fetch(request)
        guard results.count == 1, let result = results.first else { throw notFound }
        return result
    }

    nonisolated static func fetchActive<T: NSManagedObject>(
        id: UUID,
        entityName: String,
        in context: NSManagedObjectContext,
        notFound: CatalogRepositoryError
    ) throws -> T {
        let object: T = try fetchOne(
            id: id, entityName: entityName, in: context, notFound: notFound
        )
        guard object.value(forKey: "archivedAt") == nil else { throw notFound }
        return object
    }

    nonisolated static func fetchQRCodes(token: String, in context: NSManagedObjectContext) throws -> [QRCode] {
        let request = NSFetchRequest<QRCode>(entityName: "QRCode")
        request.predicate = NSPredicate(format: "token == %@", token)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true), NSSortDescriptor(key: "id", ascending: true)]
        return try context.fetch(request)
    }

    nonisolated static func storedResolution(for rows: [QRCode]) -> StoredQRResolution {
        guard !rows.isEmpty else { return .unknown }

        var activeTargets: [RawQRTarget] = []
        var repair: QRCodeRepairReason?
        for row in rows {
            guard !row.token.isEmpty else {
                repair = repair ?? .invalidStoredToken
                continue
            }
            guard row.state == "bound" else {
                repair = repair ?? .missingTarget
                continue
            }

            let rowTargets = bindingTargets(for: row)
            guard rowTargets.count == 1 else {
                if rowTargets.isEmpty {
                    repair = repair ?? .missingTarget
                } else {
                    activeTargets.append(contentsOf: rowTargets)
                }
                continue
            }
            activeTargets.append(rowTargets[0])
        }

        let distinctTargets = activeTargets.reduce(into: [RawQRTarget]()) { result, target in
            guard !result.contains(target) else { return }
            result.append(target)
        }
        if distinctTargets.count > 1 {
            return .conflict(distinctTargets)
        }
        if let repair {
            return .repair(repair)
        }
        if rows.count > 1 {
            return .repair(.duplicateBindings)
        }
        guard let target = distinctTargets.first else {
            return .repair(.missingTarget)
        }
        return .known(target)
    }

    nonisolated static func requireRepairable(_ rows: [QRCode]) throws {
        switch storedResolution(for: rows) {
        case .repair, .conflict:
            return
        case .unknown, .known:
            throw CatalogRepositoryError.qrCodeNotRepairable
        }
    }

    static func requireRepairTargetAvailable(
        _ target: QRTargetObject,
        for token: QRToken,
        in context: NSManagedObjectContext
    ) throws {
        let targetRows = managedObjects(target.qrCodes, as: QRCode.self)
        let otherTokens = Set(targetRows.lazy.map(\.token).filter { $0 != token.rawValue })
        for rawToken in otherTokens {
            let rows = try fetchQRCodes(token: rawToken, in: context)
            if case .known(let boundTarget) = storedResolution(for: rows),
               boundTarget == target.target
            {
                throw CatalogRepositoryError.targetAlreadyHasQRCode
            }
        }
    }

    static func consolidate(
        _ repairRows: [QRCode],
        token: QRToken,
        onto target: QRTargetObject,
        in context: NSManagedObjectContext
    ) throws {
        let targetRows = managedObjects(target.qrCodes, as: QRCode.self)
        var deleted = Set<NSManagedObjectID>()
        for row in repairRows + targetRows where deleted.insert(row.objectID).inserted {
            context.delete(row)
        }
        try insertQRCode(token, for: target, in: context)
    }

    static func insertQRCode(
        _ token: QRToken,
        for target: QRTargetObject,
        in context: NSManagedObjectContext
    ) throws {
        let qrCode: QRCode = try insert("QRCode", into: context)
        qrCode.token = token.rawValue
        qrCode.state = "bound"
        qrCode.boundAt = Date()
        qrCode.place = target.place
        target.apply(to: qrCode)
        if let store = target.objectID.persistentStore {
            context.assign(qrCode, to: store)
        }
        try ManagedObjectDomainValidator.validate(qrCode)
    }

    nonisolated static func bindingTarget(for qrCode: QRCode) -> RawQRTarget? {
        let targets = bindingTargets(for: qrCode)
        return targets.count == 1 ? targets[0] : nil
    }

    nonisolated static func bindingTargets(for qrCode: QRCode) -> [RawQRTarget] {
        [
            qrCode.area.flatMap { isActive($0) ? $0.id.map(RawQRTarget.area) : nil },
            qrCode.container.flatMap { isActive($0) ? $0.id.map(RawQRTarget.container) : nil }
        ].compactMap { $0 }
    }

    nonisolated static func isActive(_ room: Room) -> Bool {
        room.archivedAt == nil && room.place?.archivedAt == nil
    }

    nonisolated static func isActive(_ area: Area) -> Bool {
        guard
            area.archivedAt == nil,
            area.place?.archivedAt == nil,
            let room = area.room
        else {
            return false
        }
        return isActive(room) && room.place === area.place
    }

    nonisolated static func isActive(_ container: Container) -> Bool {
        guard container.archivedAt == nil, let place = container.place, place.archivedAt == nil else {
            return false
        }

        var current = container
        var seen = Set<NSManagedObjectID>()
        while let parent = current.parentContainer {
            guard
                seen.insert(parent.objectID).inserted,
                parent.archivedAt == nil,
                parent.place === place
            else {
                return false
            }
            current = parent
        }

        if let area = current.parentArea {
            return isActive(area) && area.place === place
        }
        if let room = current.parentRoom {
            return isActive(room) && room.place === place
        }
        return false
    }

    nonisolated static func isActive(_ thing: Thing) -> Bool {
        guard thing.archivedAt == nil, thing.place?.archivedAt == nil else { return false }
        let activeHomes = [
            thing.homeRoom.map(isActive),
            thing.homeArea.map(isActive),
            thing.homeContainer.map(isActive)
        ].compactMap { $0 }
        return activeHomes.count == 1 && activeHomes[0]
    }

    nonisolated static func attachTarget(for area: Area) -> QRAttachTargetSnapshot? {
        guard let id = area.id, let place = area.place, let placeID = place.id, let room = area.room else { return nil }
        return QRAttachTargetSnapshot(id: id, placeID: placeID, kind: .area, name: area.name, locationComponents: [place.name, room.name])
    }

    nonisolated static func attachTarget(for container: Container) -> QRAttachTargetSnapshot? {
        guard let id = container.id, let place = container.place, let placeID = place.id else { return nil }
        var parents: [String] = []
        var current = container.parentContainer
        var seen = Set<NSManagedObjectID>()
        while let candidate = current, seen.insert(candidate.objectID).inserted {
            parents.append(candidate.name)
            current = candidate.parentContainer
        }
        let base: [String]
        if let area = container.parentArea, let room = area.room {
            base = [place.name, room.name, area.name]
        } else if let room = container.parentRoom {
            base = [place.name, room.name]
        } else if let root = currentRoot(container), let area = root.parentArea, let room = area.room {
            base = [place.name, room.name, area.name]
        } else if let root = currentRoot(container), let room = root.parentRoom {
            base = [place.name, room.name]
        } else {
            return nil
        }
        return QRAttachTargetSnapshot(
            id: id, placeID: placeID, kind: .container, name: container.name,
            locationComponents: base + parents.reversed()
        )
    }

    nonisolated static func currentRoot(_ container: Container) -> Container? {
        var root = container
        var seen = Set<NSManagedObjectID>()
        while let parent = root.parentContainer, seen.insert(parent.objectID).inserted { root = parent }
        return root
    }

    nonisolated static func rootArea(of container: Container) -> Area? {
        currentRoot(container)?.parentArea
    }

    static func validateInsertedObject(_ object: NSManagedObject) throws {
        switch object {
        case let place as Place: try ManagedObjectDomainValidator.validate(place)
        case let room as Room: try ManagedObjectDomainValidator.validate(room)
        case let area as Area: try ManagedObjectDomainValidator.validate(area)
        case let container as Container: try ManagedObjectDomainValidator.validate(container)
        case let thing as Thing: try ManagedObjectDomainValidator.validate(thing)
        case let keyword as ThingKeyword: try ManagedObjectDomainValidator.validate(keyword)
        case let qrCode as QRCode: try ManagedObjectDomainValidator.validate(qrCode)
        case let photo as PhotoAsset: try ManagedObjectDomainValidator.validate(photo)
        default: break
        }
    }

    static func validateChanges(in context: NSManagedObjectContext) throws {
        context.processPendingChanges()
        let changed = context.insertedObjects.union(context.updatedObjects)
        for object in changed where !object.isDeleted {
            try validateInsertedObject(object)
        }
    }

    nonisolated static func assignInsertions(in context: NSManagedObjectContext, toStoreOf place: Place) {
        guard let store = place.objectID.persistentStore else { return }
        for object in context.insertedObjects {
            context.assign(object, to: store)
        }
    }

    static func applyPhotoMutation(
        _ mutation: PhotoMutation,
        to owner: PhotoOwnerObject,
        in context: NSManagedObjectContext
    ) throws {
        switch mutation {
        case .unchanged:
            return
        case .remove:
            if let obsolete = owner.primaryPhoto {
                owner.primaryPhoto = nil
                context.delete(obsolete)
            }
        case .replace(let draft):
            try validatePhotoDraft(draft)
            if let obsolete = owner.primaryPhoto {
                owner.primaryPhoto = nil
                context.delete(obsolete)
            }
            guard let place = owner.place else { throw CatalogRepositoryError.invalidStoredHierarchy }
            let photo: PhotoAsset = try insert("PhotoAsset", into: context)
            photo.data = draft.jpegData
            photo.thumbnailData = draft.thumbnailJPEGData
            photo.contentType = draft.contentType.trimmingCharacters(in: .whitespacesAndNewlines)
            photo.pixelWidth = Int32(draft.dimensions.width)
            photo.pixelHeight = Int32(draft.dimensions.height)
            photo.byteSize = Int64(draft.byteSize)
            photo.kind = "original"
            photo.source = draft.source.rawValue
            photo.capturedAt = draft.capturedAt
            photo.place = place
            owner.apply(to: photo)
        }
    }

    nonisolated static func validatePhotoDraft(_ draft: NormalizedPhoto) throws {
        guard
            !draft.jpegData.isEmpty,
            !draft.contentType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            draft.dimensions.width > 0,
            draft.dimensions.height > 0,
            draft.dimensions.width <= Int(Int32.max),
            draft.dimensions.height <= Int(Int32.max)
        else {
            throw CatalogRepositoryError.invalidDraft
        }
    }

    static func validateContainerMove(
        _ movingContainer: Container,
        to parent: ContainerParentObject
    ) throws {
        try ContainmentValidator.validateNoCycle(
            moving: movingContainer,
            proposedParent: parent.containerParent,
            id: \.objectID,
            parent: \.parentContainer
        )
    }

    nonisolated static func archiveSubtree(for room: Room) -> [NSManagedObject] {
        let areas = managedObjects(room.areas, as: Area.self)
        let roots = managedObjects(room.containers, as: Container.self)
            + areas.flatMap { managedObjects($0.containers, as: Container.self) }
        let containers = containersInSubtree(roots)
        let things = managedObjects(room.things, as: Thing.self)
            + areas.flatMap { managedObjects($0.things, as: Thing.self) }
            + containers.flatMap { managedObjects($0.things, as: Thing.self) }
        return [room] + areas + containers + things
    }

    nonisolated static func archiveSubtree(for area: Area) -> [NSManagedObject] {
        let containers = containersInSubtree(managedObjects(area.containers, as: Container.self))
        let things = managedObjects(area.things, as: Thing.self)
            + containers.flatMap { managedObjects($0.things, as: Thing.self) }
        return [area] + containers + things
    }

    nonisolated static func archiveSubtree(for container: Container) -> [NSManagedObject] {
        let containers = containersInSubtree([container])
        let things = containers.flatMap { managedObjects($0.things, as: Thing.self) }
        return containers + things
    }

    nonisolated static func containersInSubtree(_ roots: [Container]) -> [Container] {
        var result: [Container] = []
        var pending = roots
        var seen = Set<NSManagedObjectID>()
        while let container = pending.popLast() {
            guard seen.insert(container.objectID).inserted else { continue }
            result.append(container)
            pending.append(contentsOf: managedObjects(container.childContainers, as: Container.self))
        }
        return result
    }

    nonisolated static func archive(_ objects: [NSManagedObject], at date: Date) {
        var seen = Set<NSManagedObjectID>()
        for object in objects where seen.insert(object.objectID).inserted {
            guard object.value(forKey: "archivedAt") == nil else { continue }
            object.setValue(date, forKey: "archivedAt")
            object.setValue(date, forKey: "updatedAt")
        }
    }

    nonisolated static func managedObjects<T: NSManagedObject>(_ set: NSSet?, as type: T.Type) -> [T] {
        (set?.allObjects as? [T]) ?? []
    }

    nonisolated static func boundQRCodes(of set: NSSet?) -> [QRCode] {
        managedObjects(set, as: QRCode.self).filter { $0.state == "bound" }
    }

    nonisolated static func nilIfEmpty(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines), !normalized.isEmpty else { return nil }
        return normalized
    }

    nonisolated static func requiredName(_ value: String) throws -> String {
        guard let name = nilIfEmpty(value) else { throw CatalogRepositoryError.invalidDraft }
        return name
    }

    nonisolated static func requiredID(_ value: UUID?) throws -> UUID {
        guard let value else { throw CatalogRepositoryError.missingIdentity }
        return value
    }

    nonisolated static func nextSortOrder(in values: [Int32]) -> Int32 {
        guard let maximum = values.max(), maximum < Int32.max else { return 0 }
        return maximum + 1
    }

    nonisolated static func searchNormalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    nonisolated static func normalizeKeywords(_ keywords: some Sequence<String>) -> [String] {
        var seen = Set<String>()
        return keywords.compactMap { keyword in
            let displayValue = keyword.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            guard !displayValue.isEmpty else { return nil }
            let key = searchNormalized(displayValue)
            guard seen.insert(key).inserted else { return nil }
            return displayValue
        }
    }

    static func rawTarget(_ target: QRBindingTarget) -> RawQRTarget {
        switch target {
        case .area(let id): .area(id.rawValue)
        case .container(let id): .container(id.rawValue)
        }
    }

    static func publicTarget(_ target: RawQRTarget) -> QRBindingTarget {
        switch target {
        case .area(let id): .area(QRTargetID(rawValue: id))
        case .container(let id): .container(QRTargetID(rawValue: id))
        }
    }

    static func publicResolution(_ resolution: StoredQRResolution) -> QRCodeResolution {
        switch resolution {
        case .unknown:
            .unknown
        case .known(.area(let id)):
            .knownArea(QRTargetID(rawValue: id))
        case .known(.container(let id)):
            .knownContainer(QRTargetID(rawValue: id))
        case .repair(let reason):
            .needsRepair(QRCodeRepair(reason: reason))
        case .conflict(let targets):
            .conflict(QRCodeConflict(
                firstTarget: publicTarget(targets[0]),
                secondTarget: publicTarget(targets[1]),
                additionalTargets: targets.dropFirst(2).map { publicTarget($0) }
            ))
        }
    }

    nonisolated static func compare(name lhsName: String, id lhsID: UUID, name rhsName: String, id rhsID: UUID) -> Bool {
        if lhsName != rhsName {
            let lhsKey = searchNormalized(lhsName)
            let rhsKey = searchNormalized(rhsName)
            return lhsKey == rhsKey ? lhsName < rhsName : lhsKey < rhsKey
        }
        return lhsID.uuidString < rhsID.uuidString
    }

    nonisolated static func stringSort(_ lhs: String, _ rhs: String) -> Bool {
        let lhsKey = searchNormalized(lhs)
        let rhsKey = searchNormalized(rhs)
        return lhsKey == rhsKey ? lhs < rhs : lhsKey < rhsKey
    }

    nonisolated static func roomSort(_ lhs: RoomSnapshot, _ rhs: RoomSnapshot) -> Bool {
        lhs.sortOrder == rhs.sortOrder ? compare(name: lhs.name, id: lhs.id, name: rhs.name, id: rhs.id) : lhs.sortOrder < rhs.sortOrder
    }

    nonisolated static func areaSort(_ lhs: AreaSnapshot, _ rhs: AreaSnapshot) -> Bool {
        if lhs.roomID != rhs.roomID { return lhs.roomID.uuidString < rhs.roomID.uuidString }
        return lhs.sortOrder == rhs.sortOrder ? compare(name: lhs.name, id: lhs.id, name: rhs.name, id: rhs.id) : lhs.sortOrder < rhs.sortOrder
    }

    nonisolated static func containerSort(_ lhs: ContainerSnapshot, _ rhs: ContainerSnapshot) -> Bool {
        lhs.sortOrder == rhs.sortOrder ? compare(name: lhs.name, id: lhs.id, name: rhs.name, id: rhs.id) : lhs.sortOrder < rhs.sortOrder
    }

    nonisolated static func thingSort(_ lhs: ThingSnapshot, _ rhs: ThingSnapshot) -> Bool {
        compare(name: lhs.name, id: lhs.id, name: rhs.name, id: rhs.id)
    }

    nonisolated static func attachTargetSort(_ lhs: QRAttachTargetSnapshot, _ rhs: QRAttachTargetSnapshot) -> Bool {
        if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
        let lhsPath = lhs.locationComponents.joined(separator: "\u{0}")
        let rhsPath = rhs.locationComponents.joined(separator: "\u{0}")
        if lhsPath != rhsPath { return stringSort(lhsPath, rhsPath) }
        return compare(name: lhs.name, id: lhs.id, name: rhs.name, id: rhs.id)
    }
}
