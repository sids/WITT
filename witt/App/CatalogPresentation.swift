import Foundation

extension PlaceSnapshot {
    var activeRooms: [RoomSnapshot] {
        rooms.filter { $0.archivedAt == nil }
    }

    func activeAreas(in roomID: UUID) -> [AreaSnapshot] {
        areas.filter { $0.roomID == roomID && $0.archivedAt == nil }
    }

    func activeContainers(inArea areaID: UUID) -> [ContainerSnapshot] {
        containers.filter {
            $0.parent == .area(areaID) && $0.archivedAt == nil
        }
    }

    func activeContainers(inRoom roomID: UUID) -> [ContainerSnapshot] {
        containers.filter {
            $0.parent == .room(roomID) && $0.archivedAt == nil
        }
    }

    func childContainers(of containerID: UUID) -> [ContainerSnapshot] {
        containers.filter {
            $0.parent == .container(containerID) && $0.archivedAt == nil
        }
    }

    func activeThings(in home: ThingSnapshotHome) -> [ThingSnapshot] {
        things.filter { $0.home == home && $0.archivedAt == nil }
    }

    func locationComponents(for thing: ThingSnapshot) -> [String] {
        switch thing.home {
        case .room(let id):
            guard let room = rooms.first(where: { $0.id == id }) else { return [] }
            return [name, room.name]
        case .area(let id):
            let components = areaLocationComponents(id)
            return components.isEmpty ? [] : [name] + components
        case .container(let id):
            let components = containerLocationComponents(id)
            return components.isEmpty ? [] : [name] + components
        }
    }

    func locationComponents(for destination: ThingDestination) -> [String] {
        switch destination {
        case .room(let id):
            guard let room = rooms.first(where: { $0.id == id }) else { return [] }
            return [name, room.name]
        case .area(let id):
            let components = areaLocationComponents(id)
            return components.isEmpty ? [] : [name] + components
        case .container(let id):
            let components = containerLocationComponents(id)
            return components.isEmpty ? [] : [name] + components
        }
    }

    private func areaLocationComponents(_ areaID: UUID) -> [String] {
        guard let area = areas.first(where: { $0.id == areaID }) else { return [] }
        return rooms.filter { $0.id == area.roomID }.map(\.name) + [area.name]
    }

    private func containerLocationComponents(
        _ containerID: UUID,
        visited: Set<UUID> = []
    ) -> [String] {
        guard
            !visited.contains(containerID),
            let container = containers.first(where: { $0.id == containerID })
        else {
            return []
        }

        var visited = visited
        visited.insert(containerID)
        switch container.parent {
        case .room(let roomID):
            return rooms.filter { $0.id == roomID }.map(\.name) + [container.name]
        case .area(let areaID):
            return areaLocationComponents(areaID) + [container.name]
        case .container(let parentID):
            return containerLocationComponents(parentID, visited: visited) + [container.name]
        }
    }
}

extension CatalogStore {
    func place(containing thing: ThingSnapshot) -> PlaceSnapshot? {
        activePlaces.first { $0.id == thing.placeID }
    }

    func locationComponents(for thing: ThingSnapshot) -> [String] {
        place(containing: thing)?.locationComponents(for: thing) ?? []
    }

    func locationComponents(for destination: ThingDestination) -> [String] {
        activePlaces.lazy.map { $0.locationComponents(for: destination) }
            .first { !$0.isEmpty } ?? []
    }
}
