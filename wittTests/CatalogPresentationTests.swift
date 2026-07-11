import XCTest
@testable import witt

final class CatalogPresentationTests: XCTestCase {
    func testBrowseRouteEncodesAndDecodesEveryDestination() throws {
        let id = UUID()
        let routes: [BrowseRoute] = [
            .place(id), .room(id), .area(id), .container(id), .thing(id)
        ]

        for route in routes {
            let data = try JSONEncoder().encode(route)
            XCTAssertEqual(try JSONDecoder().decode(BrowseRoute.self, from: data), route)
        }
    }

    func testBrowseRestorationBuildsRoomAndAreaPaths() {
        let fixture = nestedFixture()

        XCTAssertEqual(
            BrowsePathRestorer.path(to: .room(fixture.roomID), in: [fixture.place]),
            [.place(fixture.place.id), .room(fixture.roomID)]
        )
        XCTAssertEqual(
            BrowsePathRestorer.path(to: .area(fixture.areaID), in: [fixture.place]),
            [.place(fixture.place.id), .room(fixture.roomID), .area(fixture.areaID)]
        )
    }

    func testBrowseRestorationBuildsArbitrarilyNestedContainerPath() {
        let fixture = nestedFixture()

        XCTAssertEqual(
            BrowsePathRestorer.path(to: .container(fixture.innerID), in: [fixture.place]),
            [
                .place(fixture.place.id),
                .room(fixture.roomID),
                .area(fixture.areaID),
                .container(fixture.outerID),
                .container(fixture.innerID)
            ]
        )
    }

    func testBrowseRestorationBuildsThingPathsForEveryHomeKind() {
        let fixture = nestedFixture()
        let roomThingID = UUID()
        let areaThingID = UUID()
        let containerThingID = UUID()
        let place = makePlace(
            name: fixture.place.name,
            rooms: fixture.place.rooms,
            areas: fixture.place.areas,
            containers: fixture.place.containers,
            things: [
                thing(id: roomThingID, placeID: fixture.place.id, name: "Room Thing", home: .room(fixture.roomID)),
                thing(id: areaThingID, placeID: fixture.place.id, name: "Area Thing", home: .area(fixture.areaID)),
                thing(id: containerThingID, placeID: fixture.place.id, name: "Container Thing", home: .container(fixture.innerID))
            ],
            id: fixture.place.id
        )

        XCTAssertEqual(
            BrowsePathRestorer.path(to: .thing(roomThingID), in: [place]),
            [.place(place.id), .room(fixture.roomID), .thing(roomThingID)]
        )
        XCTAssertEqual(
            BrowsePathRestorer.path(to: .thing(areaThingID), in: [place]),
            [.place(place.id), .room(fixture.roomID), .area(fixture.areaID), .thing(areaThingID)]
        )
        XCTAssertEqual(
            BrowsePathRestorer.path(to: .thing(containerThingID), in: [place]),
            [
                .place(place.id),
                .room(fixture.roomID),
                .area(fixture.areaID),
                .container(fixture.outerID),
                .container(fixture.innerID),
                .thing(containerThingID)
            ]
        )
    }

    func testBrowseRestorationUsesDestinationsCurrentParents() {
        let fixture = nestedFixture()
        let secondRoomID = UUID()
        let thingID = UUID()
        let movedPlace = makePlace(
            name: fixture.place.name,
            rooms: fixture.place.rooms + [
                room(id: secondRoomID, placeID: fixture.place.id, name: "Studio")
            ],
            areas: fixture.place.areas.map { area in
                guard area.id == fixture.areaID else { return area }
                return self.area(
                    id: area.id,
                    placeID: area.placeID,
                    roomID: secondRoomID,
                    name: area.name
                )
            },
            containers: fixture.place.containers.map { container in
                guard container.id == fixture.innerID else { return container }
                return self.container(
                    id: container.id,
                    placeID: container.placeID,
                    name: container.name,
                    parent: .room(fixture.roomID)
                )
            },
            things: [
                thing(
                    id: thingID,
                    placeID: fixture.place.id,
                    name: "Lamp",
                    home: .area(fixture.areaID)
                )
            ],
            id: fixture.place.id
        )

        XCTAssertEqual(
            BrowsePathRestorer.path(to: .area(fixture.areaID), in: [movedPlace]),
            [.place(movedPlace.id), .room(secondRoomID), .area(fixture.areaID)]
        )
        XCTAssertEqual(
            BrowsePathRestorer.path(to: .container(fixture.innerID), in: [movedPlace]),
            [.place(movedPlace.id), .room(fixture.roomID), .container(fixture.innerID)]
        )
        XCTAssertEqual(
            BrowsePathRestorer.path(to: .thing(thingID), in: [movedPlace]),
            [.place(movedPlace.id), .room(secondRoomID), .area(fixture.areaID), .thing(thingID)]
        )
    }

    func testBrowseRestorationRejectsArchivedMissingAndCyclicHierarchy() {
        let placeID = UUID()
        let roomID = UUID()
        let archivedContainerID = UUID()
        let cycleA = UUID()
        let cycleB = UUID()
        let place = makePlace(
            name: "Home",
            rooms: [room(id: roomID, placeID: placeID, name: "Garage")],
            containers: [
                container(
                    id: archivedContainerID,
                    placeID: placeID,
                    name: "Archived",
                    parent: .room(roomID),
                    archived: true
                ),
                container(id: cycleA, placeID: placeID, name: "Cycle A", parent: .container(cycleB)),
                container(id: cycleB, placeID: placeID, name: "Cycle B", parent: .container(cycleA))
            ],
            id: placeID
        )

        XCTAssertNil(BrowsePathRestorer.path(to: .container(archivedContainerID), in: [place]))
        XCTAssertNil(BrowsePathRestorer.path(to: .container(UUID()), in: [place]))
        XCTAssertNil(BrowsePathRestorer.path(to: .container(cycleA), in: [place]))
    }

    func testBrowseRestorationHandlesRootAndMissingSavedDestination() {
        let place = makePlace(name: "Home")

        XCTAssertEqual(BrowsePathRestorer.path(to: nil, in: [place]), [])
        XCTAssertEqual(
            BrowsePathRestorer.path(to: .place(place.id), in: [place]),
            [.place(place.id)]
        )
        XCTAssertNil(BrowsePathRestorer.path(to: .place(UUID()), in: [place]))
    }

    func testDestinationPathDoesNotMatchTheWrongPlace() {
        let first = makePlace(name: "Home")
        let secondID = UUID()
        let roomID = UUID()
        let areaID = UUID()
        let second = makePlace(
            name: "Studio",
            rooms: [RoomSnapshot(
                id: roomID,
                placeID: secondID,
                name: "Office",
                sortOrder: 0,
                archivedAt: nil
            )],
            areas: [AreaSnapshot(
                id: areaID,
                placeID: secondID,
                roomID: roomID,
                name: "Cabinet",
                detail: nil,
                sortOrder: 0,
                archivedAt: nil,
                primaryPhoto: nil,
                hasQRCode: false
            )],
            id: secondID
        )

        XCTAssertEqual(first.locationComponents(for: .area(areaID)), [])
        XCTAssertEqual(
            second.locationComponents(for: .area(areaID)),
            ["Studio", "Office", "Cabinet"]
        )
    }

    func testNestedContainerPathIncludesEveryParent() {
        let placeID = UUID()
        let roomID = UUID()
        let areaID = UUID()
        let outerID = UUID()
        let innerID = UUID()
        let place = PlaceSnapshot(
            id: placeID,
            name: "Home",
            notes: nil,
            createdAt: nil,
            updatedAt: nil,
            archivedAt: nil,
            primaryPhoto: nil,
            rooms: [RoomSnapshot(
                id: roomID,
                placeID: placeID,
                name: "Garage",
                sortOrder: 0,
                archivedAt: nil
            )],
            areas: [AreaSnapshot(
                id: areaID,
                placeID: placeID,
                roomID: roomID,
                name: "Workbench",
                detail: nil,
                sortOrder: 0,
                archivedAt: nil,
                primaryPhoto: nil,
                hasQRCode: false
            )],
            containers: [
                ContainerSnapshot(
                    id: outerID,
                    placeID: placeID,
                    name: "Tool Chest",
                    detail: nil,
                    sortOrder: 0,
                    archivedAt: nil,
                    parent: .area(areaID),
                    primaryPhoto: nil,
                    hasQRCode: false
                ),
                ContainerSnapshot(
                    id: innerID,
                    placeID: placeID,
                    name: "Bit Case",
                    detail: nil,
                    sortOrder: 0,
                    archivedAt: nil,
                    parent: .container(outerID),
                    primaryPhoto: nil,
                    hasQRCode: true
                )
            ],
            things: []
        )

        XCTAssertEqual(
            place.locationComponents(for: .container(innerID)),
            ["Home", "Garage", "Workbench", "Tool Chest", "Bit Case"]
        )
    }

    func testInactiveAndMissingAncestorsSuppressDescendants() {
        let placeID = UUID()
        let archivedRoomID = UUID()
        let missingRoomID = UUID()
        let areaID = UUID()
        let orphanAreaID = UUID()
        let containerID = UUID()
        let cycleA = UUID()
        let cycleB = UUID()
        let hiddenThingID = UUID()
        let place = makePlace(
            name: "Home",
            rooms: [room(id: archivedRoomID, placeID: placeID, name: "Garage", archived: true)],
            areas: [
                area(id: areaID, placeID: placeID, roomID: archivedRoomID, name: "Shelf"),
                area(id: orphanAreaID, placeID: placeID, roomID: missingRoomID, name: "Orphan")
            ],
            containers: [
                container(id: containerID, placeID: placeID, name: "Box", parent: .area(areaID)),
                container(id: cycleA, placeID: placeID, name: "Cycle A", parent: .container(cycleB)),
                container(id: cycleB, placeID: placeID, name: "Cycle B", parent: .container(cycleA))
            ],
            things: [thing(id: hiddenThingID, placeID: placeID, name: "Drill", home: .container(containerID))],
            id: placeID
        )

        XCTAssertTrue(place.activeAreas.isEmpty)
        XCTAssertTrue(place.activeContainers.isEmpty)
        XCTAssertTrue(place.activeThings.isEmpty)
        XCTAssertTrue(place.thingDestinationOptions.isEmpty)
        XCTAssertEqual(place.locationComponents(for: place.things[0]), [])
    }

    func testDestinationAndContainerParentOptionsUseFullActivePaths() {
        let fixture = nestedFixture()

        XCTAssertEqual(
            fixture.place.thingDestinationOptions.map(\.displayPath),
            [
                "Home · Garage",
                "Home · Garage · Workbench",
                "Home · Garage · Workbench · Tool Chest",
                "Home · Garage · Workbench · Tool Chest · Bit Case",
                "Home · Garage · Workbench · Spare Box"
            ]
        )

        let destinations = fixture.place.containerParentOptions(editing: fixture.outerID).map(\.destination)
        XCTAssertTrue(destinations.contains(.room(fixture.roomID)))
        XCTAssertTrue(destinations.contains(.area(fixture.areaID)))
        XCTAssertTrue(destinations.contains(.container(fixture.siblingID)))
        XCTAssertFalse(destinations.contains(.container(fixture.outerID)))
        XCTAssertFalse(destinations.contains(.container(fixture.innerID)))

        let innerDestinations = fixture.place.containerParentOptions(editing: fixture.innerID).map(\.destination)
        XCTAssertTrue(innerDestinations.contains(.container(fixture.outerID)))
    }

    func testArchiveImpactCountsNestedDescendantsAndBoundQR() {
        let fixture = nestedFixture(innerHasQRCode: true, withThings: true)

        XCTAssertEqual(
            fixture.place.archiveImpact(forAreaID: fixture.areaID),
            ArchiveImpactSummary(
                storageAreaCount: 0,
                containerCount: 3,
                thingCount: 2,
                containsBoundQRCode: true
            )
        )
        XCTAssertEqual(
            fixture.place.archiveImpact(forContainerID: fixture.outerID),
            ArchiveImpactSummary(
                storageAreaCount: 0,
                containerCount: 1,
                thingCount: 2,
                containsBoundQRCode: true
            )
        )
    }

    @MainActor
    func testCreateWrapperReturnsSnapshotAndReloadsCatalog() async {
        let store = CatalogStore(persistence: .inMemory())

        let created = await store.createPlace(CreatePlaceDraft(name: "Studio"))

        XCTAssertEqual(created?.name, "Studio")
        XCTAssertEqual(store.place(id: created!.id)?.name, "Studio")
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testMutationFailurePublishesLocalizedError() async {
        let store = CatalogStore(persistence: .inMemory())

        let created = await store.createRoom(CreateRoomDraft(placeID: UUID(), name: "Office"))

        XCTAssertNil(created)
        XCTAssertEqual(store.errorMessage, CatalogRepositoryError.placeNotFound.localizedDescription)
    }

    @MainActor
    func testEditingOptionsStayWithinTheOwningPlace() async throws {
        let store = CatalogStore(persistence: .inMemory())
        let createdFirstPlace = await store.createPlace(.init(name: "Home"))
        let firstPlace = try XCTUnwrap(createdFirstPlace)
        let createdFirstRoom = await store.createRoom(.init(
            placeID: firstPlace.id,
            name: "Garage"
        ))
        let firstRoom = try XCTUnwrap(createdFirstRoom)
        let createdContainer = await store.createContainer(.init(
            name: "Tool Chest",
            destination: .room(firstRoom.id)
        ))
        let container = try XCTUnwrap(createdContainer)
        let saved = await store.saveThing(
            name: "Drill",
            keywords: [],
            notes: "",
            photo: nil,
            to: .container(container.id),
            nameSource: "user"
        )
        XCTAssertTrue(saved)
        let thing = try XCTUnwrap(store.things.first { $0.name == "Drill" })

        let createdSecondPlace = await store.createPlace(.init(name: "Studio"))
        let secondPlace = try XCTUnwrap(createdSecondPlace)
        let createdSecondRoom = await store.createRoom(.init(
            placeID: secondPlace.id,
            name: "Office"
        ))
        let secondRoom = try XCTUnwrap(createdSecondRoom)

        let containerOptions = store.containerParentOptions(editing: container.id)
        XCTAssertTrue(containerOptions.contains { $0.destination == .room(firstRoom.id) })
        XCTAssertFalse(containerOptions.contains { $0.destination == .room(secondRoom.id) })

        let thingOptions = store.thingDestinationOptions(editing: thing.id)
        XCTAssertTrue(thingOptions.contains { $0.destination == .room(firstRoom.id) })
        XCTAssertFalse(thingOptions.contains { $0.destination == .room(secondRoom.id) })
    }

    private func makePlace(
        name: String,
        rooms: [RoomSnapshot] = [],
        areas: [AreaSnapshot] = [],
        containers: [ContainerSnapshot] = [],
        things: [ThingSnapshot] = [],
        id: UUID = UUID()
    ) -> PlaceSnapshot {
        PlaceSnapshot(
            id: id,
            name: name,
            notes: nil,
            createdAt: nil,
            updatedAt: nil,
            archivedAt: nil,
            primaryPhoto: nil,
            rooms: rooms,
            areas: areas,
            containers: containers,
            things: things
        )
    }

    private func nestedFixture(
        innerHasQRCode: Bool = false,
        withThings: Bool = false
    ) -> (place: PlaceSnapshot, roomID: UUID, areaID: UUID, outerID: UUID, innerID: UUID, siblingID: UUID) {
        let placeID = UUID()
        let roomID = UUID()
        let areaID = UUID()
        let outerID = UUID()
        let innerID = UUID()
        let siblingID = UUID()
        return (
            makePlace(
                name: "Home",
                rooms: [room(id: roomID, placeID: placeID, name: "Garage")],
                areas: [area(id: areaID, placeID: placeID, roomID: roomID, name: "Workbench")],
                containers: [
                    container(id: outerID, placeID: placeID, name: "Tool Chest", parent: .area(areaID)),
                    container(id: innerID, placeID: placeID, name: "Bit Case", parent: .container(outerID), hasQRCode: innerHasQRCode),
                    container(id: siblingID, placeID: placeID, name: "Spare Box", parent: .area(areaID))
                ],
                things: withThings ? [
                    thing(id: UUID(), placeID: placeID, name: "Drill", home: .container(outerID)),
                    thing(id: UUID(), placeID: placeID, name: "Bits", home: .container(innerID))
                ] : [],
                id: placeID
            ), roomID, areaID, outerID, innerID, siblingID
        )
    }

    private func room(id: UUID, placeID: UUID, name: String, archived: Bool = false) -> RoomSnapshot {
        RoomSnapshot(id: id, placeID: placeID, name: name, sortOrder: 0, archivedAt: archived ? Date() : nil)
    }

    private func area(id: UUID, placeID: UUID, roomID: UUID, name: String) -> AreaSnapshot {
        AreaSnapshot(id: id, placeID: placeID, roomID: roomID, name: name, detail: nil, sortOrder: 0, archivedAt: nil, primaryPhoto: nil, hasQRCode: false)
    }

    private func container(
        id: UUID,
        placeID: UUID,
        name: String,
        parent: ContainerSnapshotParent,
        hasQRCode: Bool = false,
        archived: Bool = false
    ) -> ContainerSnapshot {
        ContainerSnapshot(id: id, placeID: placeID, name: name, detail: nil, sortOrder: 0, archivedAt: archived ? Date() : nil, parent: parent, primaryPhoto: nil, hasQRCode: hasQRCode)
    }

    private func thing(id: UUID, placeID: UUID, name: String, home: ThingSnapshotHome) -> ThingSnapshot {
        ThingSnapshot(id: id, placeID: placeID, name: name, keywords: [], notes: nil, nameSource: "user", home: home, createdAt: nil, updatedAt: nil, archivedAt: nil, primaryPhoto: nil)
    }
}
