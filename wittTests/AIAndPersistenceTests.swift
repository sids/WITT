import CoreData
import XCTest
@testable import witt

final class ThingPhotoLabelingTests: XCTestCase {
    private let photo = PhotoInput(data: Data([0x01]), contentType: "image/jpeg")

    func testKeywordNormalizerTrimsWhitespaceAndDeduplicatesCaseAndDiacritics() {
        XCTAssertEqual(
            ThingKeywordNormalizer.normalize(["  Power   Cable ", "power cable", "CAFÉ", "cafe", "\n", "USB-C"]),
            ["Power Cable", "CAFÉ", "USB-C"]
        )
    }

    func testMockSuccessReturnsConfiguredSuggestion() async throws {
        let expected = ThingLabelSuggestion(
            proposedName: "Power adapter",
            keywords: ["adapter", "electronics"],
            detail: "65 W",
            confidence: 0.9
        )
        let service = MockThingPhotoLabelingService(mode: .success(expected))
        let actual = try await service.suggestLabel(for: photo)

        XCTAssertEqual(actual, expected)
    }

    func testMockDelayedSuccessEventuallyReturnsConfiguredSuggestion() async throws {
        let expected = ThingLabelSuggestion(proposedName: "Cable")
        let service = MockThingPhotoLabelingService(
            mode: .delayedSuccess(expected, delay: .milliseconds(1))
        )
        let actual = try await service.suggestLabel(for: photo)

        XCTAssertEqual(actual, expected)
    }

    func testMockFailureThrowsConfiguredError() async {
        let service = MockThingPhotoLabelingService(mode: .failure(.serviceUnavailable))

        do {
            _ = try await service.suggestLabel(for: photo)
            XCTFail("Expected the mock service to throw")
        } catch {
            XCTAssertEqual(error as? ThingPhotoLabelingError, .serviceUnavailable)
        }
    }
}

final class PersistenceControllerTests: XCTestCase {
    func testInMemoryControllerLoadsAllEntities() {
        let persistence = PersistenceController.inMemory()

        XCTAssertTrue(persistence.isLoaded)
        XCTAssertNil(persistence.loadError)
        XCTAssertEqual(
            Set(persistence.container.managedObjectModel.entities.compactMap(\.name)),
            Set(["Place", "Room", "Area", "Container", "Thing", "ThingKeyword", "QRCode", "PhotoAsset"])
        )
    }

    func testMinimalGraphPassesManagedObjectValidation() throws {
        let context = PersistenceController.inMemory().viewContext
        let place: Place = insert("Place", into: context)
        let room: Room = insert("Room", into: context)
        let area: Area = insert("Area", into: context)
        let container: Container = insert("Container", into: context)
        let thing: Thing = insert("Thing", into: context)

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

        XCTAssertNoThrow(try ManagedObjectDomainValidator.validate(place))
        XCTAssertNoThrow(try ManagedObjectDomainValidator.validate(room))
        XCTAssertNoThrow(try ManagedObjectDomainValidator.validate(area))
        XCTAssertNoThrow(try ManagedObjectDomainValidator.validate(container))
        XCTAssertNoThrow(try ManagedObjectDomainValidator.validate(thing))
        XCTAssertNoThrow(try context.obtainPermanentIDs(for: [place, room, area, container, thing]))
    }

    private func insert<T: NSManagedObject>(
        _ entityName: String,
        into context: NSManagedObjectContext
    ) -> T {
        NSEntityDescription.insertNewObject(forEntityName: entityName, into: context) as! T
    }
}
