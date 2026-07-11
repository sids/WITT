import CoreData
import Foundation

public final class CoreDataCatalogRepository: CatalogRepository, @unchecked Sendable {
    private let persistenceController: PersistenceController
    private let context: NSManagedObjectContext

    public init(
        persistenceController: PersistenceController,
        context: NSManagedObjectContext? = nil
    ) {
        self.persistenceController = persistenceController
        self.context = context ?? persistenceController.newBackgroundContext(author: "witt.catalog")
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
                let place: Place = Self.insert("Place", into: context)
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
                let thing: Thing = Self.insert("Thing", into: context)
                thing.name = normalizedName
                thing.detail = Self.nilIfEmpty(draft.notes)
                thing.nameSource = normalizedSource
                thing.place = home.place
                home.apply(to: thing)

                let normalizedKeywords = Self.normalizeKeywords(draft.keywords)
                for displayValue in normalizedKeywords {
                    let keyword: ThingKeyword = Self.insert("ThingKeyword", into: context)
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
                    guard
                        !photoDraft.jpegData.isEmpty,
                        !photoDraft.contentType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        photoDraft.dimensions.width > 0,
                        photoDraft.dimensions.height > 0,
                        photoDraft.dimensions.width <= Int(Int32.max),
                        photoDraft.dimensions.height <= Int(Int32.max)
                    else {
                        throw CatalogRepositoryError.invalidDraft
                    }
                    let photo: PhotoAsset = Self.insert("PhotoAsset", into: context)
                    photo.data = photoDraft.jpegData
                    photo.thumbnailData = photoDraft.thumbnailJPEGData
                    photo.contentType = photoDraft.contentType
                    photo.pixelWidth = Int32(photoDraft.dimensions.width)
                    photo.pixelHeight = Int32(photoDraft.dimensions.height)
                    photo.byteSize = Int64(photoDraft.byteSize)
                    photo.kind = photoDraft.persistenceMetadata.kind
                    photo.source = photoDraft.source.rawValue
                    photo.capturedAt = photoDraft.capturedAt
                    photo.place = home.place
                    photo.thingOwner = thing
                    thing.primaryPhoto = photo
                }

                let inserted = Array(context.insertedObjects)
                if let store = home.objectID.persistentStore {
                    for object in inserted {
                        context.assign(object, to: store)
                    }
                }
                for object in inserted {
                    try Self.validateInsertedObject(object)
                }
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

    @discardableResult
    public func bindQRCode(_ request: QRCodeBindingRequest) async throws -> QRCodeBinding {
        try ensurePersistenceLoaded()
        return try await context.perform { [context] in
            context.reset()
            do {
                let existing = try Self.fetchQRCodes(token: request.token.rawValue, in: context)
                if existing.count == 1,
                   existing[0].state == "bound",
                   Self.bindingTarget(for: existing[0]) == Self.rawTarget(request.target)
                {
                    return QRCodeBinding(token: request.token, target: request.target)
                }
                guard existing.isEmpty else {
                    throw CatalogRepositoryError.tokenAlreadyBound
                }

                let target = try Self.fetchQRTarget(request.target, in: context)
                guard Self.boundQRCodes(of: target.qrCodes).isEmpty else {
                    throw CatalogRepositoryError.targetAlreadyHasQRCode
                }

                let qrCode: QRCode = Self.insert("QRCode", into: context)
                qrCode.token = request.token.rawValue
                qrCode.state = "bound"
                qrCode.boundAt = Date()
                qrCode.place = target.place
                target.apply(to: qrCode)
                if let store = target.objectID.persistentStore {
                    context.assign(qrCode, to: store)
                }
                try ManagedObjectDomainValidator.validate(qrCode)
                try context.save()
                return QRCodeBinding(token: request.token, target: request.target)
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

                let qrCode: QRCode = Self.insert("QRCode", into: context)
                qrCode.token = request.token.rawValue
                qrCode.state = "bound"
                qrCode.boundAt = Date()
                qrCode.place = place
                target.apply(to: qrCode)

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
            guard !rows.isEmpty else { return StoredQRResolution.unknown }

            var targets: [RawQRTarget] = []
            var repair: (QRCodeRepairReason, UUID?)?
            for row in rows {
                if QRToken(rawValue: row.token) == nil {
                    repair = (.invalidStoredToken, row.id)
                    continue
                }
                guard row.state == "bound" else {
                    repair = (.missingTarget, row.id)
                    continue
                }
                let rowTargets = Self.bindingTargets(for: row)
                guard !rowTargets.isEmpty else {
                    repair = (.missingTarget, row.id)
                    continue
                }
                for target in rowTargets where !targets.contains(target) {
                    targets.append(target)
                }
            }

            if targets.count > 1 { return .conflict(targets) }
            if let repair { return .repair(reason: repair.0, bindingID: repair.1) }
            guard let target = targets.first else { return .repair(reason: .missingTarget, bindingID: rows.first?.id) }
            return .known(target)
        }
        return Self.publicResolution(storedResolution)
    }

    private func ensurePersistenceLoaded() throws {
        guard persistenceController.isLoaded, persistenceController.loadError == nil else {
            throw CatalogRepositoryError.persistenceNotLoaded
        }
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
        case repair(reason: QRCodeRepairReason, bindingID: UUID?)
        case conflict([RawQRTarget])
    }

    struct HomeObject {
        let objectID: NSManagedObjectID
        let place: Place
        let destination: ThingDestination

        func apply(to thing: Thing) {
            switch destination {
            case .room:
                thing.homeRoom = try? thing.managedObjectContext?.existingObject(with: objectID) as? Room
            case .area:
                thing.homeArea = try? thing.managedObjectContext?.existingObject(with: objectID) as? Area
            case .container:
                thing.homeContainer = try? thing.managedObjectContext?.existingObject(with: objectID) as? Container
            }
        }
    }

    struct QRTargetObject {
        let objectID: NSManagedObjectID
        let place: Place
        let qrCodes: NSSet?
        let target: RawQRTarget

        func apply(to qrCode: QRCode) {
            switch target {
            case .area:
                qrCode.area = try? qrCode.managedObjectContext?.existingObject(with: objectID) as? Area
            case .container:
                qrCode.container = try? qrCode.managedObjectContext?.existingObject(with: objectID) as? Container
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
            return HomeObject(objectID: room.objectID, place: place, destination: destination)
        case .area(let id):
            let area: Area = try fetchOne(id: id, entityName: "Area", in: context)
            guard isActive(area), let place = area.place else {
                throw CatalogRepositoryError.destinationNotFound
            }
            return HomeObject(objectID: area.objectID, place: place, destination: destination)
        case .container(let id):
            let container: Container = try fetchOne(id: id, entityName: "Container", in: context)
            guard isActive(container), let place = container.place else {
                throw CatalogRepositoryError.destinationNotFound
            }
            return HomeObject(objectID: container.objectID, place: place, destination: destination)
        }
    }

    nonisolated static func fetchQRTarget(_ target: QRBindingTarget, in context: NSManagedObjectContext) throws -> QRTargetObject {
        switch target {
        case .area(let id):
            let area: Area = try fetchOne(id: id.rawValue, entityName: "Area", in: context, notFound: .targetNotFound)
            guard isActive(area), let place = area.place else {
                throw CatalogRepositoryError.targetNotFound
            }
            return QRTargetObject(
                objectID: area.objectID,
                place: place,
                qrCodes: area.qrCodes,
                target: .area(id.rawValue)
            )
        case .container(let id):
            let container: Container = try fetchOne(id: id.rawValue, entityName: "Container", in: context, notFound: .targetNotFound)
            guard isActive(container), let place = container.place else {
                throw CatalogRepositoryError.targetNotFound
            }
            return QRTargetObject(
                objectID: container.objectID,
                place: place,
                qrCodes: container.qrCodes,
                target: .container(id.rawValue)
            )
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
            let room: Room = insert("Room", into: context)
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
            let area: Area = insert("Area", into: context)
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
            return QRTargetObject(
                objectID: area.objectID,
                place: place,
                qrCodes: area.qrCodes,
                target: .area(try requiredID(area.id))
            )
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
            return QRTargetObject(
                objectID: container.objectID,
                place: place,
                qrCodes: container.qrCodes,
                target: .container(id)
            )
        case .newContainer(let name):
            let container: Container = insert("Container", into: context)
            container.name = try requiredName(name)
            container.sortOrder = nextSortOrder(
                in: managedObjects(area.containers, as: Container.self).map(\.sortOrder)
            )
            container.parentArea = area
            container.place = place
            guard let id = container.id else { throw CatalogRepositoryError.missingIdentity }
            return QRTargetObject(
                objectID: container.objectID,
                place: place,
                qrCodes: container.qrCodes,
                target: .container(id)
            )
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

    nonisolated static func fetchQRCodes(token: String, in context: NSManagedObjectContext) throws -> [QRCode] {
        let request = NSFetchRequest<QRCode>(entityName: "QRCode")
        request.predicate = NSPredicate(format: "token == %@", token)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true), NSSortDescriptor(key: "id", ascending: true)]
        return try context.fetch(request)
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

    nonisolated static func managedObjects<T: NSManagedObject>(_ set: NSSet?, as type: T.Type) -> [T] {
        (set?.allObjects as? [T]) ?? []
    }

    nonisolated static func boundQRCodes(of set: NSSet?) -> [QRCode] {
        managedObjects(set, as: QRCode.self).filter { $0.state == "bound" }
    }

    nonisolated static func insert<T: NSManagedObject>(_ entityName: String, into context: NSManagedObjectContext) -> T {
        NSEntityDescription.insertNewObject(forEntityName: entityName, into: context) as! T
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
        case .repair(let reason, let bindingID):
            .needsRepair(QRCodeRepair(reason: reason, bindingID: bindingID))
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
