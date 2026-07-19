import XCTest
@testable import witt

final class ContainmentValidatorTests: XCTestCase {
    private let placeID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let otherPlaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    func testThingRequiresExactlyOneHomeInItsPlace() throws {
        let home = ThingHome.area(reference(placeID: placeID))
        XCTAssertNoThrow(try ContainmentValidator.validateThing(placeID: placeID, homes: [home]))
        assertError(.missingParent) { try ContainmentValidator.validateThing(placeID: self.placeID, homes: []) }
        assertError(.multipleParents) {
            try ContainmentValidator.validateThing(placeID: self.placeID, homes: [home, home])
        }
        assertError(.crossPlaceRelationship) {
            try ContainmentValidator.validateThing(
                placeID: self.placeID,
                homes: [.room(self.reference(placeID: self.otherPlaceID))]
            )
        }
    }

    func testContainerRequiresExactlyOneParentInItsPlace() throws {
        let parent = ContainerParent.room(reference(placeID: placeID))
        XCTAssertNoThrow(try ContainmentValidator.validateContainer(placeID: placeID, parents: [parent]))
        assertError(.missingParent) { try ContainmentValidator.validateContainer(placeID: self.placeID, parents: []) }
        assertError(.multipleParents) {
            try ContainmentValidator.validateContainer(placeID: self.placeID, parents: [parent, parent])
        }
        assertError(.crossPlaceRelationship) {
            try ContainmentValidator.validateContainer(
                placeID: self.placeID,
                parents: [.area(self.reference(placeID: self.otherPlaceID))]
            )
        }
    }

    func testQRCodeBoundAndUnboundRules() throws {
        let target = QRCodeTarget.container(reference(placeID: placeID))
        XCTAssertNoThrow(try ContainmentValidator.validateQRCode(placeID: placeID, targets: [target], isBound: true))
        XCTAssertNoThrow(try ContainmentValidator.validateQRCode(placeID: nil, targets: [], isBound: false))
        assertError(.missingTarget) {
            try ContainmentValidator.validateQRCode(placeID: self.placeID, targets: [], isBound: true)
        }
        assertError(.multipleTargets) {
            try ContainmentValidator.validateQRCode(placeID: self.placeID, targets: [target, target], isBound: true)
        }
        assertError(.targetOnUnboundQRCode) {
            try ContainmentValidator.validateQRCode(placeID: self.placeID, targets: [target], isBound: false)
        }
        assertError(.crossPlaceRelationship) {
            try ContainmentValidator.validateQRCode(
                placeID: self.placeID,
                targets: [.area(self.reference(placeID: self.otherPlaceID))],
                isBound: true
            )
        }
    }

    func testPhotoRequiresExactlyOneOwnerInItsPlace() throws {
        let owner = PhotoOwner.thing(reference(placeID: placeID))
        XCTAssertNoThrow(try ContainmentValidator.validatePhoto(placeID: placeID, owners: [owner]))
        assertError(.missingOwner) { try ContainmentValidator.validatePhoto(placeID: self.placeID, owners: []) }
        assertError(.multipleOwners) {
            try ContainmentValidator.validatePhoto(placeID: self.placeID, owners: [owner, owner])
        }
        assertError(.crossPlaceRelationship) {
            try ContainmentValidator.validatePhoto(placeID: self.placeID, owners: [.place(self.otherPlaceID)])
        }
        assertError(.missingPlace) { try ContainmentValidator.validatePhoto(placeID: nil, owners: [owner]) }
    }

    func testPlaceOwnershipRejectsMissingAndCrossPlaceRelationships() throws {
        XCTAssertNoThrow(try ContainmentValidator.validatePlaceOwnership(childPlaceID: placeID, parentPlaceID: placeID))
        assertError(.missingPlace) {
            try ContainmentValidator.validatePlaceOwnership(childPlaceID: nil, parentPlaceID: self.placeID)
        }
        assertError(.crossPlaceRelationship) {
            try ContainmentValidator.validatePlaceOwnership(childPlaceID: self.placeID, parentPlaceID: self.otherPlaceID)
        }
    }

    func testContainerCycleDetectionHandlesDirectAndIndirectCycles() throws {
        let moving = UUID()
        let parent = UUID()
        let grandparent = UUID()

        XCTAssertNoThrow(try ContainmentValidator.validateNoContainerCycle(
            movingContainerID: moving,
            proposedParentID: parent,
            parentByContainerID: [parent: grandparent, grandparent: nil]
        ))
        assertError(.containerCycle) {
            try ContainmentValidator.validateNoContainerCycle(
                movingContainerID: moving,
                proposedParentID: moving,
                parentByContainerID: [:]
            )
        }
        assertError(.containerCycle) {
            try ContainmentValidator.validateNoContainerCycle(
                movingContainerID: moving,
                proposedParentID: parent,
                parentByContainerID: [parent: grandparent, grandparent: moving]
            )
        }
    }

    private func reference(placeID: UUID) -> PlaceOwnedReference {
        PlaceOwnedReference(placeID: placeID)
    }

    private func assertError(
        _ expectedError: DomainValidationError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? DomainValidationError, expectedError, file: file, line: line)
        }
    }
}
