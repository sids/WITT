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
#if DEBUG
    func testCloudKitSchemaInitializationArgumentsAreOptIn() {
        XCTAssertNil(
            PersistenceController.CloudKitSchemaInitializationRequest.requested(
                in: ["witt", "--some-other-argument"]
            )
        )
    }

    func testCloudKitSchemaDryRunArgumentUsesDryRunAndPrintSchemaOptions() throws {
        let request = try XCTUnwrap(
            PersistenceController.CloudKitSchemaInitializationRequest.requested(
                in: ["witt", "--initialize-cloudkit-schema-dry-run"]
            )
        )

        XCTAssertEqual(request, .dryRun)
        XCTAssertEqual(request.options, [.dryRun, .printSchema])
    }

    func testCloudKitSchemaInitializationArgumentUsesPrintSchemaOption() throws {
        let request = try XCTUnwrap(
            PersistenceController.CloudKitSchemaInitializationRequest.requested(
                in: ["witt", "--initialize-cloudkit-schema"]
            )
        )

        XCTAssertEqual(request, .initialize)
        XCTAssertEqual(request.options, [.printSchema])
    }

    func testCloudKitSchemaInitializationArgumentTakesPrecedenceOverDryRun() throws {
        let request = try XCTUnwrap(
            PersistenceController.CloudKitSchemaInitializationRequest.requested(
                in: [
                    "witt",
                    "--initialize-cloudkit-schema-dry-run",
                    "--initialize-cloudkit-schema"
                ]
            )
        )

        XCTAssertEqual(request, .initialize)
    }
#endif

    func testInMemoryControllerLoadsAllEntities() {
        let persistence = PersistenceController.inMemory()

        XCTAssertTrue(persistence.isLoaded)
        XCTAssertNil(persistence.loadError)
        XCTAssertEqual(
            Set(persistence.container.managedObjectModel.entities.compactMap(\.name)),
            Set(["Place", "Room", "Area", "Container", "Thing", "ThingKeyword", "QRCode", "PhotoAsset"])
        )
    }

    func testManagedObjectClassesUsePrefixedRuntimeNamesWithoutChangingSchemaHashes() throws {
        let model = PersistenceController.inMemory().container.managedObjectModel
        let expected: [(
            entityName: String,
            className: String,
            type: NSManagedObject.Type,
            versionHash: String
        )] = [
            ("Area", "WITTArea", Area.self, "LYYQa3diYpuLlNbEPq6XW+Uej7SdJXkWE5eoWwZeRjc="),
            ("Container", "WITTContainer", Container.self, "1E7xYw/C+3Mkr/fs9n0Gimk1/JRZ0yXGYzANNsHOBe4="),
            ("PhotoAsset", "WITTPhotoAsset", PhotoAsset.self, "/WzL6Dakbp64ujT5ucGzvqxREf8wVWy84ttr6bLplvk="),
            ("Place", "WITTPlace", Place.self, "O5xjFqMU+unS3RBZqJOHDAG+nqIRbvkvdLNkzTVojFE="),
            ("QRCode", "WITTQRCode", QRCode.self, "PsHTsVyJ13WZWNScd+NjIDItyHwm7AxMZSWE6oljh3Q="),
            ("Room", "WITTRoom", Room.self, "2bwz1XgxiMnfw01wOMZ4ATYHxQQHFbypw3pw/mgZ9z8="),
            ("Thing", "WITTThing", Thing.self, "4lH/y3r7dh0HFUdZm0mQ52mp/2La4hdwYEN1cCDMZ0c="),
            ("ThingKeyword", "WITTThingKeyword", ThingKeyword.self, "fKvr5mFyUCHl0N5LhwoA2P9PEK14fCnh7ReQtZEPrUg=")
        ]

        for item in expected {
            let entity = try XCTUnwrap(model.entitiesByName[item.entityName])
            XCTAssertEqual(entity.managedObjectClassName, item.className)
            XCTAssertEqual(NSStringFromClass(item.type), item.className)
            XCTAssertTrue(NSClassFromString(item.className) === item.type)
            XCTAssertEqual(entity.versionHash.base64EncodedString(), item.versionHash)
        }
    }

    func testRetiredQRCodeLastScannedAtRemainsAnOptionalDateInTheDeployedModel() throws {
        let model = PersistenceController.inMemory().container.managedObjectModel
        let qrCode = try XCTUnwrap(model.entitiesByName["QRCode"])
        let attribute = try XCTUnwrap(qrCode.attributesByName["lastScannedAt"])

        XCTAssertEqual(attribute.attributeType, .dateAttributeType)
        XCTAssertTrue(attribute.isOptional)
        XCTAssertFalse(attribute.isTransient)
    }

    func testProductionInsertionHelperCreatesEveryManagedObjectClass() throws {
        let context = PersistenceController.inMemory().viewContext
        let place: Place = try CoreDataCatalogRepository.insert("Place", into: context)
        let room: Room = try CoreDataCatalogRepository.insert("Room", into: context)
        let area: Area = try CoreDataCatalogRepository.insert("Area", into: context)
        let container: Container = try CoreDataCatalogRepository.insert("Container", into: context)
        let thing: Thing = try CoreDataCatalogRepository.insert("Thing", into: context)
        let keyword: ThingKeyword = try CoreDataCatalogRepository.insert("ThingKeyword", into: context)
        let qrCode: QRCode = try CoreDataCatalogRepository.insert("QRCode", into: context)
        let photo: PhotoAsset = try CoreDataCatalogRepository.insert("PhotoAsset", into: context)

        XCTAssertTrue(Swift.type(of: place) == Place.self)
        XCTAssertTrue(Swift.type(of: room) == Room.self)
        XCTAssertTrue(Swift.type(of: area) == Area.self)
        XCTAssertTrue(Swift.type(of: container) == Container.self)
        XCTAssertTrue(Swift.type(of: thing) == Thing.self)
        XCTAssertTrue(Swift.type(of: keyword) == ThingKeyword.self)
        XCTAssertTrue(Swift.type(of: qrCode) == QRCode.self)
        XCTAssertTrue(Swift.type(of: photo) == PhotoAsset.self)
    }

    func testProductionInsertionHelperRejectsClassMismatchWithoutCoreDataLookup() throws {
        let sourceModel = PersistenceController.inMemory().container.managedObjectModel
        let model = try XCTUnwrap(sourceModel.copy() as? NSManagedObjectModel)
        let containerEntity = try XCTUnwrap(model.entitiesByName["Container"])
        containerEntity.managedObjectClassName = NSStringFromClass(NSObject.self)

        let persistentContainer = NSPersistentContainer(
            name: "WITT-Mismatch",
            managedObjectModel: model
        )
        let description = NSPersistentStoreDescription(
            url: URL(fileURLWithPath: "/dev/null")
        )
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        persistentContainer.persistentStoreDescriptions = [description]
        var loadError: Error?
        persistentContainer.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError)

        XCTAssertThrowsError(
            try CoreDataCatalogRepository.insert(
                "Container",
                into: persistentContainer.viewContext
            ) as Container
        ) { error in
            XCTAssertEqual(error as? CatalogRepositoryError, .invalidManagedObjectModel)
        }
    }

    func testSQLiteStoreReopensAndFetchesCreatedContainer() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("witt-class-resolution-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        do {
            let persistence = PersistenceController(
                cloudKitContainerIdentifier: nil,
                storeDirectory: directory
            )
            let repository = CoreDataCatalogRepository(persistenceController: persistence)
            let place = try await repository.createPlace(.init(name: "Home"))
            let room = try await repository.createRoom(.init(placeID: place.id, name: "Garage"))
            _ = try await repository.createContainer(.init(
                name: "Tool Chest",
                destination: .room(room.id)
            ))
        }

        do {
            let persistence = PersistenceController(
                cloudKitContainerIdentifier: nil,
                storeDirectory: directory
            )
            let repository = CoreDataCatalogRepository(persistenceController: persistence)
            let places = try await repository.fetchPlaces()

            XCTAssertEqual(places.count, 1)
            XCTAssertEqual(places[0].containers.map(\.name), ["Tool Chest"])
        }

        try FileManager.default.removeItem(at: directory)
    }

    func testMinimalGraphPassesManagedObjectValidation() throws {
        let context = PersistenceController.inMemory().viewContext
        let place: Place = try CoreDataCatalogRepository.insert("Place", into: context)
        let room: Room = try CoreDataCatalogRepository.insert("Room", into: context)
        let area: Area = try CoreDataCatalogRepository.insert("Area", into: context)
        let container: Container = try CoreDataCatalogRepository.insert("Container", into: context)
        let thing: Thing = try CoreDataCatalogRepository.insert("Thing", into: context)

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
}
