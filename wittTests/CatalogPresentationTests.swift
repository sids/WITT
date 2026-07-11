import XCTest
@testable import witt

final class CatalogPresentationTests: XCTestCase {
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

    private func makePlace(
        name: String,
        rooms: [RoomSnapshot] = [],
        areas: [AreaSnapshot] = [],
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
            containers: [],
            things: []
        )
    }
}
