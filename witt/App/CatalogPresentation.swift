import Foundation

struct ThingDestinationOption: Identifiable, Hashable, Sendable {
    let destination: ThingDestination
    let locationComponents: [String]

    var id: ThingDestination { destination }
    var displayPath: String { locationComponents.joined(separator: " · ") }
}

struct ContainerParentOption: Identifiable, Hashable, Sendable {
    let destination: ContainerDestination
    let locationComponents: [String]

    var id: ContainerDestination { destination }
    var displayPath: String { locationComponents.joined(separator: " · ") }
}

struct ArchiveImpactSummary: Equatable, Sendable {
    let storageAreaCount: Int
    let containerCount: Int
    let thingCount: Int
    let containsBoundQRCode: Bool

    static let empty = ArchiveImpactSummary(
        storageAreaCount: 0,
        containerCount: 0,
        thingCount: 0,
        containsBoundQRCode: false
    )
}

extension PlaceSnapshot {
    var activeRooms: [RoomSnapshot] {
        guard archivedAt == nil else { return [] }
        return rooms.filter { $0.archivedAt == nil && $0.placeID == id }
    }

    var activeAreas: [AreaSnapshot] {
        guard archivedAt == nil else { return [] }
        let roomIDs = Set(activeRooms.map(\.id))
        return areas.filter {
            $0.archivedAt == nil && $0.placeID == id && roomIDs.contains($0.roomID)
        }
    }

    var activeContainers: [ContainerSnapshot] {
        guard archivedAt == nil else { return [] }
        return containers.filter { isActiveContainer($0.id) }
    }

    var activeThings: [ThingSnapshot] {
        guard archivedAt == nil else { return [] }
        return things.filter { thing in
            thing.archivedAt == nil && thing.placeID == id && isActive(home: thing.home)
        }
    }

    func activeAreas(in roomID: UUID) -> [AreaSnapshot] {
        activeAreas.filter { $0.roomID == roomID }
    }

    func activeContainers(inArea areaID: UUID) -> [ContainerSnapshot] {
        activeContainers.filter { $0.parent == .area(areaID) }
    }

    func activeContainers(inRoom roomID: UUID) -> [ContainerSnapshot] {
        activeContainers.filter { $0.parent == .room(roomID) }
    }

    func childContainers(of containerID: UUID) -> [ContainerSnapshot] {
        guard isActiveContainer(containerID) else { return [] }
        return activeContainers.filter { $0.parent == .container(containerID) }
    }

    func activeThings(in home: ThingSnapshotHome) -> [ThingSnapshot] {
        guard isActive(home: home) else { return [] }
        return activeThings.filter { $0.home == home }
    }

    func room(id roomID: UUID) -> RoomSnapshot? {
        rooms.first { $0.id == roomID && $0.placeID == id }
    }

    func area(id areaID: UUID) -> AreaSnapshot? {
        areas.first { $0.id == areaID && $0.placeID == id }
    }

    func container(id containerID: UUID) -> ContainerSnapshot? {
        containers.first { $0.id == containerID && $0.placeID == id }
    }

    func thing(id thingID: UUID) -> ThingSnapshot? {
        things.first { $0.id == thingID && $0.placeID == id }
    }

    var thingDestinationOptions: [ThingDestinationOption] {
        let rooms = activeRooms.compactMap { option(for: ThingDestination.room($0.id)) }
        let areas = activeAreas.compactMap { option(for: ThingDestination.area($0.id)) }
        let containers = activeContainers.compactMap { option(for: ThingDestination.container($0.id)) }
        return rooms + areas + containers
    }

    func containerParentOptions(editing containerID: UUID? = nil) -> [ContainerParentOption] {
        var excluded = Set<UUID>()
        if let containerID {
            excluded.insert(containerID)
            collectContainerDescendants(of: containerID, into: &excluded)
        }

        let rooms = activeRooms.compactMap { option(for: ContainerDestination.room($0.id)) }
        let areas = activeAreas.compactMap { option(for: ContainerDestination.area($0.id)) }
        let containers = activeContainers.filter { !excluded.contains($0.id) }.compactMap {
            option(for: ContainerDestination.container($0.id))
        }
        return rooms + areas + containers
    }

    func locationComponents(for thing: ThingSnapshot) -> [String] {
        guard activeThings.contains(where: { $0.id == thing.id }) else { return [] }
        return locationComponents(for: thing.home)
    }

    func locationComponents(for destination: ThingDestination) -> [String] {
        locationComponents(for: home(destination))
    }

    func archiveImpact(forRoomID roomID: UUID) -> ArchiveImpactSummary {
        guard activeRooms.contains(where: { $0.id == roomID }) else { return .empty }
        let areaIDs = Set(activeAreas(in: roomID).map(\.id))
        let rootContainerIDs = activeContainers.compactMap { container -> UUID? in
            switch container.parent {
            case .room(let parentRoomID): return parentRoomID == roomID ? container.id : nil
            case .area(let areaID): return areaIDs.contains(areaID) ? container.id : nil
            case .container: return nil
            }
        }
        let containerIDs = containerSubtreeIDs(roots: rootContainerIDs)
        return impact(
            areaIDs: areaIDs,
            containerIDs: containerIDs,
            roomID: roomID,
            storageAreaCount: areaIDs.count,
            containerCount: containerIDs.count
        )
    }

    func archiveImpact(forAreaID areaID: UUID) -> ArchiveImpactSummary {
        guard activeAreas.contains(where: { $0.id == areaID }) else { return .empty }
        let roots = activeContainers(inArea: areaID).map(\.id)
        let containerIDs = containerSubtreeIDs(roots: roots)
        return impact(
            areaIDs: [areaID],
            containerIDs: containerIDs,
            storageAreaCount: 0,
            containerCount: containerIDs.count
        )
    }

    func archiveImpact(forContainerID containerID: UUID) -> ArchiveImpactSummary {
        guard isActiveContainer(containerID) else { return .empty }
        let containerIDs = containerSubtreeIDs(roots: [containerID])
        return impact(
            areaIDs: [],
            containerIDs: containerIDs,
            storageAreaCount: 0,
            containerCount: max(0, containerIDs.count - 1)
        )
    }

    private func option(for destination: ThingDestination) -> ThingDestinationOption? {
        let components = locationComponents(for: destination)
        return components.isEmpty ? nil : ThingDestinationOption(destination: destination, locationComponents: components)
    }

    private func option(for destination: ContainerDestination) -> ContainerParentOption? {
        let components = locationComponents(for: home(destination))
        return components.isEmpty ? nil : ContainerParentOption(destination: destination, locationComponents: components)
    }

    private func locationComponents(for home: ThingSnapshotHome) -> [String] {
        guard archivedAt == nil, isActive(home: home) else { return [] }
        switch home {
        case .room(let roomID):
            guard let room = room(id: roomID) else { return [] }
            return [name, room.name]
        case .area(let areaID):
            let components = areaLocationComponents(areaID)
            return components.isEmpty ? [] : [name] + components
        case .container(let containerID):
            let components = containerLocationComponents(containerID)
            return components.isEmpty ? [] : [name] + components
        }
    }

    private func areaLocationComponents(_ areaID: UUID) -> [String] {
        guard
            activeAreas.contains(where: { $0.id == areaID }),
            let area = area(id: areaID),
            let room = room(id: area.roomID)
        else { return [] }
        return [room.name, area.name]
    }

    private func containerLocationComponents(_ containerID: UUID) -> [String] {
        guard isActiveContainer(containerID) else { return [] }
        return containerLocationComponents(containerID, visited: [])
    }

    private func containerLocationComponents(_ containerID: UUID, visited: Set<UUID>) -> [String] {
        guard !visited.contains(containerID), let container = container(id: containerID) else { return [] }
        var visited = visited
        visited.insert(containerID)
        switch container.parent {
        case .room(let roomID):
            guard let room = room(id: roomID) else { return [] }
            return [room.name, container.name]
        case .area(let areaID):
            let parent = areaLocationComponents(areaID)
            return parent.isEmpty ? [] : parent + [container.name]
        case .container(let parentID):
            let parent = containerLocationComponents(parentID, visited: visited)
            return parent.isEmpty ? [] : parent + [container.name]
        }
    }

    private func isActive(home: ThingSnapshotHome) -> Bool {
        switch home {
        case .room(let id): activeRooms.contains { $0.id == id }
        case .area(let id): activeAreas.contains { $0.id == id }
        case .container(let id): isActiveContainer(id)
        }
    }

    private func isActiveContainer(_ containerID: UUID, visited: Set<UUID> = []) -> Bool {
        guard
            archivedAt == nil,
            !visited.contains(containerID),
            let container = container(id: containerID),
            container.archivedAt == nil
        else { return false }
        var visited = visited
        visited.insert(containerID)
        switch container.parent {
        case .room(let id): return activeRooms.contains { $0.id == id }
        case .area(let id): return activeAreas.contains { $0.id == id }
        case .container(let id): return isActiveContainer(id, visited: visited)
        }
    }

    private func collectContainerDescendants(of containerID: UUID, into result: inout Set<UUID>) {
        for child in containers where child.parent == .container(containerID) && !result.contains(child.id) {
            result.insert(child.id)
            collectContainerDescendants(of: child.id, into: &result)
        }
    }

    private func containerSubtreeIDs(roots: [UUID]) -> Set<UUID> {
        var result = Set<UUID>()
        for root in roots {
            result.insert(root)
            collectContainerDescendants(of: root, into: &result)
        }
        return result.intersection(Set(activeContainers.map(\.id)))
    }

    private func impact(
        areaIDs: Set<UUID>,
        containerIDs: Set<UUID>,
        roomID: UUID? = nil,
        storageAreaCount: Int,
        containerCount: Int
    ) -> ArchiveImpactSummary {
        let thingCount = activeThings.filter { thing in
            switch thing.home {
            case .room(let id): id == roomID
            case .area(let id): areaIDs.contains(id)
            case .container(let id): containerIDs.contains(id)
            }
        }.count
        return ArchiveImpactSummary(
            storageAreaCount: storageAreaCount,
            containerCount: containerCount,
            thingCount: thingCount,
            containsBoundQRCode: activeAreas.contains { areaIDs.contains($0.id) && $0.hasQRCode }
                || activeContainers.contains { containerIDs.contains($0.id) && $0.hasQRCode }
        )
    }

    private func home(_ destination: ThingDestination) -> ThingSnapshotHome {
        switch destination {
        case .room(let id): .room(id)
        case .area(let id): .area(id)
        case .container(let id): .container(id)
        }
    }

    private func home(_ destination: ContainerDestination) -> ThingSnapshotHome {
        switch destination {
        case .room(let id): .room(id)
        case .area(let id): .area(id)
        case .container(let id): .container(id)
        }
    }
}

extension CatalogStore {
    func place(id placeID: UUID) -> PlaceSnapshot? { places.first { $0.id == placeID } }
    func room(id roomID: UUID) -> RoomSnapshot? { places.lazy.compactMap { $0.room(id: roomID) }.first }
    func area(id areaID: UUID) -> AreaSnapshot? { places.lazy.compactMap { $0.area(id: areaID) }.first }
    func container(id containerID: UUID) -> ContainerSnapshot? { places.lazy.compactMap { $0.container(id: containerID) }.first }
    func thing(id thingID: UUID) -> ThingSnapshot? { places.lazy.compactMap { $0.thing(id: thingID) }.first }

    func place(containing room: RoomSnapshot) -> PlaceSnapshot? { place(id: room.placeID) }
    func place(containing area: AreaSnapshot) -> PlaceSnapshot? { place(id: area.placeID) }
    func place(containing container: ContainerSnapshot) -> PlaceSnapshot? { place(id: container.placeID) }
    func place(containing thing: ThingSnapshot) -> PlaceSnapshot? { place(id: thing.placeID) }

    var thingDestinationOptions: [ThingDestinationOption] {
        activePlaces.flatMap(\.thingDestinationOptions)
    }

    func thingDestinationOptions(editing thingID: UUID) -> [ThingDestinationOption] {
        guard let place = activePlaces.first(where: { $0.thing(id: thingID) != nil }) else {
            return []
        }
        return place.thingDestinationOptions
    }

    func containerParentOptions(editing containerID: UUID? = nil) -> [ContainerParentOption] {
        guard let containerID else {
            return activePlaces.flatMap { $0.containerParentOptions() }
        }
        guard let place = activePlaces.first(where: { $0.container(id: containerID) != nil }) else {
            return []
        }
        return place.containerParentOptions(editing: containerID)
    }

    func locationComponents(for thing: ThingSnapshot) -> [String] {
        guard let place = place(containing: thing), activePlaces.contains(where: { $0.id == place.id }) else { return [] }
        return place.locationComponents(for: thing)
    }

    func locationComponents(for destination: ThingDestination) -> [String] {
        activePlaces.lazy.map { $0.locationComponents(for: destination) }.first { !$0.isEmpty } ?? []
    }
}
