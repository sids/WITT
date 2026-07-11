import CoreData
import XCTest
@testable import witt

final class CatalogRepositoryTests: XCTestCase {
    func testSeedOnlyRunsForEmptyCatalogAndCreatesAnEmptyHomePlace() async throws {
        let (repository, _) = makeRepository()

        let seedResult = try await repository.seedHomeIfNeeded()
        let seeded = try XCTUnwrap(seedResult)
        XCTAssertEqual(seeded.name, "Home")
        XCTAssertTrue(seeded.rooms.isEmpty)
        XCTAssertTrue(seeded.areas.isEmpty)
        XCTAssertTrue(seeded.containers.isEmpty)
        XCTAssertTrue(seeded.things.isEmpty)
        let secondSeed = try await repository.seedHomeIfNeeded()
        let fetched = try await repository.fetchPlaces()
        XCTAssertNil(secondSeed)
        XCTAssertEqual(fetched, [seeded])
    }

    func testSaveReviewedThingCreatesKeywordsPhotoAndExactlyOneHome() async throws {
        let (repository, persistence, place) = try await makeSampleRepository()
        let area = try XCTUnwrap(place.areas.first)
        let photoData = Data([0x01, 0x02, 0x03])

        let saved = try await repository.saveThing(
            ReviewedThingDraft(
                name: "  USB-C Cable  ",
                keywords: [" Cable ", "cable", "Electronics"],
                notes: "  Spare cable.  ",
                nameSource: "user",
                photo: NormalizedPhoto(
                    jpegData: photoData,
                    thumbnailJPEGData: Data([0x01]),
                    dimensions: PhotoDimensions(width: 1200, height: 900),
                    source: .camera
                )
            ),
            to: .area(area.id)
        )

        XCTAssertEqual(saved.name, "USB-C Cable")
        XCTAssertEqual(saved.keywords, ["Cable", "Electronics"])
        XCTAssertEqual(saved.notes, "Spare cable.")
        XCTAssertEqual(saved.home, .area(area.id))
        XCTAssertEqual(saved.primaryPhoto?.data, photoData)
        XCTAssertEqual(saved.primaryPhoto?.byteSize, photoData.count)

        let context = persistence.newBackgroundContext(author: "witt.catalog.tests")
        try await context.perform {
            let request = NSFetchRequest<Thing>(entityName: "Thing")
            request.predicate = NSPredicate(format: "id == %@", saved.id as CVarArg)
            let thing = try XCTUnwrap(context.fetch(request).first)
            XCTAssertNil(thing.homeRoom)
            XCTAssertNotNil(thing.homeArea)
            XCTAssertNil(thing.homeContainer)
            XCTAssertNoThrow(try ManagedObjectDomainValidator.validate(thing))
            XCTAssertNoThrow(try ManagedObjectDomainValidator.validate(try XCTUnwrap(thing.primaryPhoto)))
            for keyword in (thing.keywords?.allObjects as? [ThingKeyword]) ?? [] {
                XCTAssertNoThrow(try ManagedObjectDomainValidator.validate(keyword))
            }
        }
    }

    func testUnassignedTargetsBindAndResolve() async throws {
        let (repository, _, place) = try await makeSampleRepository()
        let targets = try await repository.unassignedQRCodeTargets()
        XCTAssertEqual(targets.count, place.areas.count + place.containers.count)
        let area = try XCTUnwrap(targets.first { $0.kind == .area })
        let token = try XCTUnwrap(QRToken(rawValue: "AAAAAAAAAAAAAAAAAAAAAA"))

        let binding = try await repository.bindQRCode(.init(token: token, target: area.bindingTarget))
        XCTAssertEqual(binding.target, area.bindingTarget)
        let resolution = try await repository.resolve(token)
        let remainingTargets = try await repository.unassignedQRCodeTargets()
        XCTAssertEqual(resolution, .knownArea(QRTargetID(rawValue: area.id)))
        XCTAssertFalse(remainingTargets.contains { $0.id == area.id })
    }

    func testResolveReportsRepairAndConflictFromStoredRows() async throws {
        let (repository, persistence, place) = try await makeSampleRepository()
        let token = try XCTUnwrap(QRToken(rawValue: "BBBBBBBBBBBBBBBBBBBBBA"))
        let area = try XCTUnwrap(place.areas.first)
        let container = try XCTUnwrap(place.containers.first)
        let context = persistence.viewContext

        try await context.perform {
            let placeObject: Place = try Self.fetch(id: place.id, entity: "Place", in: context)
            let broken: QRCode = Self.insert("QRCode", into: context)
            broken.token = token.rawValue
            broken.state = "bound"
            broken.place = placeObject
            try context.save()
        }
        let repair = try await repository.resolve(token)
        guard case .needsRepair(let issue) = repair else { return XCTFail("Expected repair, got \(repair)") }
        XCTAssertEqual(issue.reason, .missingTarget)

        try await context.perform {
            let rows = try context.fetch(NSFetchRequest<QRCode>(entityName: "QRCode"))
            rows.forEach(context.delete)
            let placeObject: Place = try Self.fetch(id: place.id, entity: "Place", in: context)
            let areaObject: Area = try Self.fetch(id: area.id, entity: "Area", in: context)
            let containerObject: Container = try Self.fetch(id: container.id, entity: "Container", in: context)
            let first: QRCode = Self.insert("QRCode", into: context)
            first.token = token.rawValue
            first.state = "bound"
            first.place = placeObject
            first.area = areaObject
            let second: QRCode = Self.insert("QRCode", into: context)
            second.token = token.rawValue
            second.state = "bound"
            second.place = placeObject
            second.container = containerObject
            try context.save()
        }

        let conflict = try await repository.resolve(token)
        guard case .conflict(let issue) = conflict else { return XCTFail("Expected conflict, got \(conflict)") }
        XCTAssertEqual(Set(issue.targets), Set([.area(QRTargetID(rawValue: area.id)), .container(QRTargetID(rawValue: container.id))]))
    }

    func testSavingToEachDestinationMaintainsOneCurrentHome() async throws {
        let (repository, persistence, place) = try await makeSampleRepository()
        let destinations: [ThingDestination] = [
            .room(try XCTUnwrap(place.rooms.first?.id)),
            .area(try XCTUnwrap(place.areas.first?.id)),
            .container(try XCTUnwrap(place.containers.first?.id))
        ]
        for (index, destination) in destinations.enumerated() {
            _ = try await repository.saveThing(ReviewedThingDraft(name: "Thing \(index)"), to: destination)
        }

        let context = persistence.newBackgroundContext(author: "witt.catalog.home-tests")
        try await context.perform {
            let things = try context.fetch(NSFetchRequest<Thing>(entityName: "Thing"))
            for thing in things {
                let homes = [thing.homeRoom, thing.homeArea, thing.homeContainer].compactMap { $0 }
                XCTAssertEqual(homes.count, 1)
                XCTAssertNoThrow(try ManagedObjectDomainValidator.validate(thing))
            }
        }
    }

    func testCreateAndBindBuildsNewRoomAreaAndContainerAtomically() async throws {
        let (repository, _) = makeRepository()
        let seedResult = try await repository.seedHomeIfNeeded()
        let place = try XCTUnwrap(seedResult)
        let token = try QRToken.generate()

        let target = try await repository.createTargetAndBindQRCode(.init(
            token: token,
            placeID: place.id,
            room: .new(name: " Utility Room "),
            area: .new(name: " High Shelf "),
            attachment: .newContainer(name: " Red Crate ")
        ))
        let fetchedPlaces = try await repository.fetchPlaces()
        let fetched = try XCTUnwrap(fetchedPlaces.first { $0.id == place.id })
        let room = try XCTUnwrap(fetched.rooms.first { $0.name == "Utility Room" })
        let area = try XCTUnwrap(fetched.areas.first { $0.name == "High Shelf" })
        let container = try XCTUnwrap(fetched.containers.first { $0.name == "Red Crate" })
        let resolution = try await repository.resolve(token)

        XCTAssertEqual(target.id, container.id)
        XCTAssertEqual(target.kind, .container)
        XCTAssertEqual(room.placeID, place.id)
        XCTAssertEqual(area.placeID, place.id)
        XCTAssertEqual(area.roomID, room.id)
        XCTAssertEqual(container.placeID, place.id)
        XCTAssertEqual(container.parent, .area(area.id))
        XCTAssertEqual(fetched.rooms.count, place.rooms.count + 1)
        XCTAssertEqual(fetched.areas.count, place.areas.count + 1)
        XCTAssertEqual(fetched.containers.count, place.containers.count + 1)
        XCTAssertEqual(resolution, .knownContainer(QRTargetID(rawValue: container.id)))
    }

    func testCreateAndBindSupportsExistingGraphAndNewAreaUnderExistingRoom() async throws {
        let (repository, _, place) = try await makeSampleRepository()
        let room = try XCTUnwrap(place.rooms.first { $0.name == "Hall Closet" })
        let area = try XCTUnwrap(place.areas.first { $0.roomID == room.id })
        let container = try XCTUnwrap(place.containers.first {
            $0.parent == .area(area.id) && $0.name == "Winter Basket"
        })
        let existingToken = try QRToken.generate()

        let existingTarget = try await repository.createTargetAndBindQRCode(.init(
            token: existingToken,
            placeID: place.id,
            room: .existing(room.id),
            area: .existing(area.id),
            attachment: .existingContainer(container.id)
        ))
        let existingResolution = try await repository.resolve(existingToken)
        XCTAssertEqual(existingTarget.id, container.id)
        XCTAssertEqual(existingResolution, .knownContainer(QRTargetID(rawValue: container.id)))

        let newAreaToken = try QRToken.generate()
        let newAreaTarget = try await repository.createTargetAndBindQRCode(.init(
            token: newAreaToken,
            placeID: place.id,
            room: .existing(room.id),
            area: .new(name: "Lower Shelf"),
            attachment: .area
        ))
        let fetchedPlaces = try await repository.fetchPlaces()
        let fetched = try XCTUnwrap(fetchedPlaces.first { $0.id == place.id })
        let newArea = try XCTUnwrap(fetched.areas.first { $0.id == newAreaTarget.id })
        let newAreaResolution = try await repository.resolve(newAreaToken)

        XCTAssertEqual(newAreaTarget.kind, .area)
        XCTAssertEqual(newArea.roomID, room.id)
        XCTAssertEqual(newArea.placeID, place.id)
        XCTAssertEqual(newAreaResolution, .knownArea(QRTargetID(rawValue: newArea.id)))
    }

    func testCreateAndBindRejectsMismatchedRoomAndAreaWithoutChangingGraph() async throws {
        let (repository, _, place) = try await makeSampleRepository()
        let hallCloset = try XCTUnwrap(place.rooms.first { $0.name == "Hall Closet" })
        let garage = try XCTUnwrap(place.rooms.first { $0.name == "Garage" })
        let garageArea = try XCTUnwrap(place.areas.first { $0.roomID == garage.id })
        let token = try QRToken.generate()

        do {
            _ = try await repository.createTargetAndBindQRCode(.init(
                token: token,
                placeID: place.id,
                room: .existing(hallCloset.id),
                area: .existing(garageArea.id),
                attachment: .area
            ))
            XCTFail("Expected the mismatched Area selection to fail")
        } catch {
            XCTAssertEqual(error as? CatalogRepositoryError, .selectionDoesNotBelongToParent)
        }

        let fetched = try await repository.fetchPlaces()
        let resolution = try await repository.resolve(token)
        XCTAssertEqual(fetched, [place])
        XCTAssertEqual(resolution, .unknown)
    }

    func testArchivedDestinationsAreExcludedAndKnownQRNeedsRepair() async throws {
        let (repository, persistence, place) = try await makeSampleRepository()
        let boundArea = try XCTUnwrap(place.areas.first)
        let otherArea = try XCTUnwrap(place.areas.first { $0.id != boundArea.id })
        let token = try QRToken.generate()
        _ = try await repository.bindQRCode(.init(
            token: token,
            target: .area(QRTargetID(rawValue: boundArea.id))
        ))

        let context = persistence.viewContext
        try await context.perform {
            let first: Area = try Self.fetch(id: boundArea.id, entity: "Area", in: context)
            let second: Area = try Self.fetch(id: otherArea.id, entity: "Area", in: context)
            first.archivedAt = Date()
            second.archivedAt = Date()
            try context.save()
        }

        let resolution = try await repository.resolve(token)
        let targets = try await repository.unassignedQRCodeTargets()
        guard case .needsRepair(let repair) = resolution else {
            return XCTFail("Expected an archived QR destination to need repair")
        }
        XCTAssertEqual(repair.reason, .missingTarget)
        XCTAssertFalse(targets.contains { $0.id == otherArea.id })

        do {
            _ = try await repository.saveThing(
                ReviewedThingDraft(name: "Archived destination test"),
                to: .area(boundArea.id)
            )
            XCTFail("Expected saving into an archived destination to fail")
        } catch {
            XCTAssertEqual(error as? CatalogRepositoryError, .destinationNotFound)
        }
    }

    private func makeRepository() -> (CoreDataCatalogRepository, PersistenceController) {
        let persistence = PersistenceController.inMemory()
        return (CoreDataCatalogRepository(persistenceController: persistence), persistence)
    }

    private func makeSampleRepository() async throws -> (
        CoreDataCatalogRepository,
        PersistenceController,
        PlaceSnapshot
    ) {
        let (repository, persistence) = makeRepository()
        let seedResult = try await repository.seedHomeIfNeeded()
        let seeded = try XCTUnwrap(seedResult)
        let context = persistence.viewContext

        try await context.perform {
            let place: Place = try Self.fetch(id: seeded.id, entity: "Place", in: context)
            let hallCloset: Room = Self.insert("Room", into: context)
            hallCloset.name = "Hall Closet"
            hallCloset.sortOrder = 0
            hallCloset.place = place
            let garage: Room = Self.insert("Room", into: context)
            garage.name = "Garage"
            garage.sortOrder = 1
            garage.place = place
            let study: Room = Self.insert("Room", into: context)
            study.name = "Study"
            study.sortOrder = 2
            study.place = place

            let topShelf: Area = Self.insert("Area", into: context)
            topShelf.name = "Top Shelf"
            topShelf.room = hallCloset
            topShelf.place = place
            let workbench: Area = Self.insert("Area", into: context)
            workbench.name = "Workbench"
            workbench.room = garage
            workbench.place = place
            let filingCabinet: Area = Self.insert("Area", into: context)
            filingCabinet.name = "Filing Cabinet"
            filingCabinet.room = study
            filingCabinet.place = place

            let blueBin: Container = Self.insert("Container", into: context)
            blueBin.name = "Blue Bin"
            blueBin.sortOrder = 0
            blueBin.parentArea = topShelf
            blueBin.place = place
            let winterBasket: Container = Self.insert("Container", into: context)
            winterBasket.name = "Winter Basket"
            winterBasket.sortOrder = 1
            winterBasket.parentArea = topShelf
            winterBasket.place = place
            let toolCase: Container = Self.insert("Container", into: context)
            toolCase.name = "Tool Case"
            toolCase.parentArea = workbench
            toolCase.place = place
            let documentsBox: Container = Self.insert("Container", into: context)
            documentsBox.name = "Documents Box"
            documentsBox.parentArea = filingCabinet
            documentsBox.place = place
            try context.save()
        }

        let places = try await repository.fetchPlaces()
        let place = try XCTUnwrap(places.first { $0.id == seeded.id })
        return (repository, persistence, place)
    }

    private static func fetch<T: NSManagedObject>(
        id: UUID,
        entity: String,
        in context: NSManagedObjectContext
    ) throws -> T {
        let request = NSFetchRequest<T>(entityName: entity)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try XCTUnwrap(context.fetch(request).first)
    }

    private static func insert<T: NSManagedObject>(_ entity: String, into context: NSManagedObjectContext) -> T {
        NSEntityDescription.insertNewObject(forEntityName: entity, into: context) as! T
    }
}
