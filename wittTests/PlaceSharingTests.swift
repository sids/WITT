import CloudKit
import CoreData
import XCTest
@testable import witt

/*
 Real-device integration test (two devices, two iCloud accounts):
 - Configure iCloud.in.sids.witt, CloudKit, remote notifications, CKSharingSupported, and the
   scene delegate wiring described in CloudKitShareDelegates.swift. Deploy the CloudKit schema.
 - Share one of two Places containing every entity type, nested containers, QR codes, keywords,
   and full/thumbnail PhotoAsset binaries. Verify no object from the second Place moves.
 - Accept from cold launch and while running. Verify complete graph import, external binary data,
   bidirectional edits, participant state, read/write access, revocation, and stop-participating.
 - Repeat with iCloud disabled, offline, read-only access, a nonowner reshare attempt, and an
   expired invitation. These are device/network integration checks, not unit tests.
 */
final class PlaceSharingTests: XCTestCase {
    func testGraphValidatorAcceptsCompleteSinglePlaceGraph() throws {
        let context = PersistenceController.inMemory().viewContext
        let place: Place = insert("Place", into: context)
        let room: Room = insert("Room", into: context)
        let area: Area = insert("Area", into: context)
        let container: Container = insert("Container", into: context)
        let thing: Thing = insert("Thing", into: context)
        let keyword: ThingKeyword = insert("ThingKeyword", into: context)
        let qrCode: QRCode = insert("QRCode", into: context)
        let photo: PhotoAsset = insert("PhotoAsset", into: context)

        place.name = "Home"
        room.name = "Office"
        room.place = place
        area.name = "Shelves"
        area.place = place
        area.room = room
        container.name = "Cable box"
        container.place = place
        container.parentArea = area
        thing.name = "USB-C cable"
        thing.place = place
        thing.homeContainer = container
        keyword.displayValue = "Cable"
        keyword.normalizedValue = "cable"
        keyword.place = place
        keyword.thing = thing
        qrCode.token = "test-token"
        qrCode.place = place
        qrCode.container = container
        photo.place = place
        photo.thingOwner = thing
        thing.primaryPhoto = photo

        XCTAssertNoThrow(try PlaceGraphValidator.validate(place))
    }

    func testGraphValidatorRejectsRelationshipIntoAnotherPlace() {
        let context = PersistenceController.inMemory().viewContext
        let firstPlace: Place = insert("Place", into: context)
        let secondPlace: Place = insert("Place", into: context)
        let firstRoom: Room = insert("Room", into: context)
        let secondArea: Area = insert("Area", into: context)

        firstPlace.name = "Home"
        secondPlace.name = "Studio"
        firstRoom.name = "Office"
        firstRoom.place = firstPlace
        secondArea.name = "Shelf"
        secondArea.place = secondPlace
        secondArea.room = firstRoom

        XCTAssertThrowsError(try PlaceGraphValidator.validate(firstPlace)) { error in
            XCTAssertEqual(error as? PlaceSharingError, .graphContainsDifferentPlace("Area"))
        }
    }

    func testGraphValidatorRejectsObjectWithoutPlace() {
        let context = PersistenceController.inMemory().viewContext
        let place: Place = insert("Place", into: context)
        let room: Room = insert("Room", into: context)
        let area: Area = insert("Area", into: context)

        place.name = "Home"
        room.name = "Office"
        room.place = place
        area.name = "Shelf"
        area.room = room

        XCTAssertThrowsError(try PlaceGraphValidator.validate(place)) { error in
            XCTAssertEqual(error as? PlaceSharingError, .graphObjectMissingPlace("Area"))
        }
    }

    func testSharingStateMapsCloudKitRolesAndPermissions() {
        XCTAssertFalse(PlaceSharingState.notShared.isShared)
        XCTAssertTrue(
            PlaceSharingState(
                role: .owner,
                permission: .readWrite,
                publicPermission: .none,
                participants: []
            ).isShared
        )
        XCTAssertEqual(PlaceSharingState.role(for: .owner), .owner)
        XCTAssertEqual(PlaceSharingState.role(for: .administrator), .administrator)
        XCTAssertEqual(PlaceSharingState.role(for: .privateUser), .participant)
        XCTAssertEqual(PlaceSharingState.permission(for: .readOnly), .readOnly)
        XCTAssertEqual(PlaceSharingState.permission(for: .readWrite), .readWrite)
        XCTAssertEqual(
            PlaceSharingState.permission(for: CKShare.ParticipantPermission.none),
            .none
        )
    }

    func testStoreLocatorSelectsDescriptionsByCloudKitDatabaseScope() {
        let privateDescription = cloudDescription(scope: .private)
        let sharedDescription = cloudDescription(scope: .shared)
        let localDescription = NSPersistentStoreDescription()

        XCTAssertTrue(
            PlaceSharingStoreLocator.description(
                scope: .private,
                among: [localDescription, sharedDescription, privateDescription]
            ) === privateDescription
        )
        XCTAssertTrue(
            PlaceSharingStoreLocator.description(
                scope: .shared,
                among: [localDescription, sharedDescription, privateDescription]
            ) === sharedDescription
        )
    }

    func testInMemoryContainerReportsCloudKitDisabled() {
        let persistence = PersistenceController.inMemory()
        let service = PlaceSharingService(persistentContainer: persistence.container)

        XCTAssertThrowsError(try service.cloudKitContainer()) { error in
            XCTAssertEqual(error as? PlaceSharingError, .cloudKitDisabled)
        }
    }

    func testErrorsProvideUserFacingDescriptions() {
        XCTAssertFalse(PlaceSharingError.cloudKitDisabled.localizedDescription.isEmpty)
        XCTAssertFalse(PlaceSharingError.privateStoreUnavailable.localizedDescription.isEmpty)
        XCTAssertFalse(PlaceSharingError.sharedStoreUnavailable.localizedDescription.isEmpty)
        XCTAssertFalse(PlaceSharingError.alreadyShared.localizedDescription.isEmpty)
        XCTAssertFalse(PlaceSharingError.permissionDenied.localizedDescription.isEmpty)
        XCTAssertFalse(PlaceSharingError.invitationFailure("Expired").localizedDescription.isEmpty)
    }

    private func insert<T: NSManagedObject>(
        _ entityName: String,
        into context: NSManagedObjectContext
    ) -> T {
        NSEntityDescription.insertNewObject(forEntityName: entityName, into: context) as! T
    }

    private func cloudDescription(scope: CKDatabase.Scope) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription()
        let options = NSPersistentCloudKitContainerOptions(
            containerIdentifier: PlaceSharingService.cloudKitContainerIdentifier
        )
        options.databaseScope = scope
        description.cloudKitContainerOptions = options
        return description
    }
}
