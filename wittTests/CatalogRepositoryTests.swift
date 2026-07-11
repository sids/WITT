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

    func testCreateAndUpdateEveryEntityNormalizesTextAndSupportsSamePlaceMoves() async throws {
        let (repository, _) = makeRepository()
        let place = try await repository.createPlace(.init(
            name: "  Lake House  ", notes: "  Weekend storage.  "
        ))
        let firstRoom = try await repository.createRoom(.init(placeID: place.id, name: "  Entry  "))
        let secondRoom = try await repository.createRoom(.init(placeID: place.id, name: " Garage "))
        let area = try await repository.createArea(.init(
            roomID: firstRoom.id, name: "  Upper Shelf  ", detail: "  Near door.  "
        ))
        let container = try await repository.createContainer(.init(
            name: "  Blue Tote  ", detail: "   ", destination: .area(area.id)
        ))
        let thing = try await repository.saveThing(
            .init(name: " Extension Cord ", keywords: [" Power "]), to: .container(container.id)
        )

        XCTAssertEqual(place.name, "Lake House")
        XCTAssertEqual(place.notes, "Weekend storage.")
        XCTAssertEqual(firstRoom.name, "Entry")
        XCTAssertEqual(area.name, "Upper Shelf")
        XCTAssertEqual(area.detail, "Near door.")
        XCTAssertEqual(container.name, "Blue Tote")
        XCTAssertNil(container.detail)

        let updatedPlace = try await repository.updatePlace(
            id: place.id, with: .init(name: "  Cabin  ", notes: "   ")
        )
        let updatedRoom = try await repository.updateRoom(
            id: firstRoom.id, with: .init(name: "  Mudroom  ")
        )
        let updatedArea = try await repository.updateArea(
            id: area.id,
            with: .init(name: "  Shelving  ", detail: "  Metal unit  ", roomID: secondRoom.id)
        )
        let updatedContainer = try await repository.updateContainer(
            id: container.id,
            with: .init(name: "  Cord Tote  ", detail: "  Heavy  ", destination: .room(secondRoom.id))
        )
        let updatedThing = try await repository.updateThing(
            id: thing.id,
            with: .init(
                name: "  Outdoor Cord  ",
                keywords: [" Power ", "power", " Garden Gear "],
                notes: "   ",
                destination: .area(updatedArea.id)
            )
        )

        XCTAssertEqual(updatedPlace.name, "Cabin")
        XCTAssertNil(updatedPlace.notes)
        XCTAssertEqual(updatedRoom.name, "Mudroom")
        XCTAssertEqual(updatedArea.name, "Shelving")
        XCTAssertEqual(updatedArea.detail, "Metal unit")
        XCTAssertEqual(updatedArea.roomID, secondRoom.id)
        XCTAssertEqual(updatedContainer.name, "Cord Tote")
        XCTAssertEqual(updatedContainer.detail, "Heavy")
        XCTAssertEqual(updatedContainer.parent, .room(secondRoom.id))
        XCTAssertEqual(updatedThing.name, "Outdoor Cord")
        XCTAssertEqual(updatedThing.keywords, ["Garden Gear", "Power"])
        XCTAssertNil(updatedThing.notes)
        XCTAssertEqual(updatedThing.home, .area(updatedArea.id))
        XCTAssertNotNil(updatedPlace.updatedAt)
        XCTAssertNotNil(updatedThing.updatedAt)
    }

    func testMovesRejectMissingArchivedAndCrossPlaceDestinations() async throws {
        let (repository, _) = makeRepository()
        let firstPlace = try await repository.createPlace(.init(name: "First"))
        let firstRoom = try await repository.createRoom(.init(placeID: firstPlace.id, name: "Room"))
        let firstArea = try await repository.createArea(.init(roomID: firstRoom.id, name: "Area"))
        let firstContainer = try await repository.createContainer(.init(
            name: "Container", destination: .area(firstArea.id)
        ))
        let thing = try await repository.saveThing(.init(name: "Thing"), to: .area(firstArea.id))

        let secondPlace = try await repository.createPlace(.init(name: "Second"))
        let secondRoom = try await repository.createRoom(.init(placeID: secondPlace.id, name: "Other Room"))
        let secondArea = try await repository.createArea(.init(roomID: secondRoom.id, name: "Other Area"))

        await assertRepositoryError(.crossPlaceMove) {
            _ = try await repository.updateArea(
                id: firstArea.id, with: .init(name: "Area", roomID: secondRoom.id)
            )
        }
        await assertRepositoryError(.crossPlaceMove) {
            _ = try await repository.updateContainer(
                id: firstContainer.id,
                with: .init(name: "Container", destination: .area(secondArea.id))
            )
        }
        await assertRepositoryError(.crossPlaceMove) {
            _ = try await repository.updateThing(
                id: thing.id, with: .init(name: "Thing", destination: .area(secondArea.id))
            )
        }
        await assertRepositoryError(.destinationNotFound) {
            _ = try await repository.createContainer(.init(
                name: "Missing", destination: .room(UUID())
            ))
        }

        _ = try await repository.archiveArea(id: firstArea.id)
        await assertRepositoryError(.destinationNotFound) {
            _ = try await repository.saveThing(.init(name: "Nope"), to: .area(firstArea.id))
        }
        await assertRepositoryError(.destinationNotFound) {
            _ = try await repository.createContainer(.init(
                name: "Nope", destination: .area(firstArea.id)
            ))
        }
    }

    func testThingAndContainerMovesKeepExactlyOneHomeAndParent() async throws {
        let (repository, persistence, place) = try await makeSampleRepository()
        let room = try XCTUnwrap(place.rooms.first { $0.name == "Garage" })
        let area = try XCTUnwrap(place.areas.first { $0.roomID == room.id })
        let outer = try await repository.createContainer(.init(name: "Outer", destination: .room(room.id)))
        let inner = try await repository.createContainer(.init(name: "Inner", destination: .container(outer.id)))
        let thing = try await repository.saveThing(.init(name: "Meter"), to: .room(room.id))

        _ = try await repository.updateContainer(
            id: inner.id, with: .init(name: "Inner", destination: .area(area.id))
        )
        _ = try await repository.updateThing(
            id: thing.id, with: .init(name: "Meter", destination: .container(inner.id))
        )

        let context = persistence.newBackgroundContext(author: "witt.catalog.exactly-one")
        try await context.perform {
            let storedContainer: Container = try Self.fetch(id: inner.id, entity: "Container", in: context)
            XCTAssertEqual([
                storedContainer.parentRoom, storedContainer.parentArea, storedContainer.parentContainer
            ].compactMap { $0 }.count, 1)
            let storedThing: Thing = try Self.fetch(id: thing.id, entity: "Thing", in: context)
            XCTAssertEqual([
                storedThing.homeRoom, storedThing.homeArea, storedThing.homeContainer
            ].compactMap { $0 }.count, 1)
            XCTAssertNoThrow(try ManagedObjectDomainValidator.validate(storedContainer))
            XCTAssertNoThrow(try ManagedObjectDomainValidator.validate(storedThing))
        }
    }

    func testContainerCycleIsRejectedAndRolledBack() async throws {
        let (repository, _, place) = try await makeSampleRepository()
        let area = try XCTUnwrap(place.areas.first)
        let parent = try await repository.createContainer(.init(name: "Parent", destination: .area(area.id)))
        let child = try await repository.createContainer(.init(name: "Child", destination: .container(parent.id)))

        await assertRepositoryError(.containerCycle) {
            _ = try await repository.updateContainer(
                id: parent.id,
                with: .init(name: "Changed but rolled back", destination: .container(child.id))
            )
        }

        let places = try await repository.fetchPlaces()
        let fetched = try XCTUnwrap(places.first { $0.id == place.id })
        let unchanged = try XCTUnwrap(fetched.containers.first { $0.id == parent.id })
        XCTAssertEqual(unchanged.name, "Parent")
        XCTAssertEqual(unchanged.parent, .area(area.id))
    }

    func testPhotoReplaceAndRemoveDeleteObsoleteAssets() async throws {
        let (repository, persistence) = makeRepository()
        let firstPhoto = Self.photo(bytes: [0x01, 0x02])
        let secondPhoto = Self.photo(bytes: [0x03, 0x04, 0x05])
        let place = try await repository.createPlace(.init(name: "Home", photo: firstPhoto))
        let firstPhotoID = try XCTUnwrap(place.primaryPhoto?.id)

        let replaced = try await repository.updatePlace(
            id: place.id,
            with: .init(name: "Home", photo: .replace(secondPhoto))
        )
        XCTAssertNotEqual(replaced.primaryPhoto?.id, firstPhotoID)
        XCTAssertEqual(replaced.primaryPhoto?.data, secondPhoto.jpegData)
        try await assertPhotoAssets(in: persistence, expectedCount: 1, missingID: firstPhotoID)

        await assertRepositoryError(.invalidDraft) {
            _ = try await repository.updatePlace(
                id: place.id,
                with: .init(
                    name: "This name must roll back",
                    photo: .replace(.init(
                        jpegData: Data(),
                        thumbnailJPEGData: Data(),
                        dimensions: .init(width: 0, height: 0),
                        source: .camera
                    ))
                )
            )
        }
        let placesAfterFailedReplacement = try await repository.fetchPlaces()
        let afterFailedReplacement = try XCTUnwrap(
            placesAfterFailedReplacement.first { $0.id == place.id }
        )
        XCTAssertEqual(afterFailedReplacement.name, "Home")
        XCTAssertEqual(afterFailedReplacement.primaryPhoto?.id, replaced.primaryPhoto?.id)
        try await assertPhotoAssets(in: persistence, expectedCount: 1)

        let replacementID = try XCTUnwrap(replaced.primaryPhoto?.id)
        let removed = try await repository.updatePlace(
            id: place.id, with: .init(name: "Home", photo: .remove)
        )
        XCTAssertNil(removed.primaryPhoto)
        try await assertPhotoAssets(in: persistence, expectedCount: 0, missingID: replacementID)
    }

    func testArchivePreservesQRCodeAndPhotoAndResolutionNeedsRepair() async throws {
        let (repository, persistence, place) = try await makeSampleRepository()
        let area = try XCTUnwrap(place.areas.first)
        let token = try QRToken.generate()
        _ = try await repository.bindQRCode(.init(
            token: token, target: .area(QRTargetID(rawValue: area.id))
        ))
        _ = try await repository.updateArea(
            id: area.id,
            with: .init(
                name: area.name,
                roomID: area.roomID,
                photo: .replace(Self.photo(bytes: [0x0A]))
            )
        )

        let archived = try await repository.archiveArea(id: area.id)
        XCTAssertNotNil(archived.archivedAt)
        XCTAssertNotNil(archived.primaryPhoto)
        XCTAssertTrue(archived.hasQRCode)
        guard case .needsRepair(let repair) = try await repository.resolve(token) else {
            return XCTFail("Expected archived QR target to need repair")
        }
        XCTAssertEqual(repair.reason, .missingTarget)

        let context = persistence.newBackgroundContext(author: "witt.catalog.archive-qr")
        try await context.perform {
            let rows = try context.fetch(NSFetchRequest<QRCode>(entityName: "QRCode"))
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows.first?.area?.id, area.id)
            XCTAssertEqual(try context.count(for: NSFetchRequest<PhotoAsset>(entityName: "PhotoAsset")), 1)
        }
    }

    func testArchiveCascadesThroughSelectedSubtreeAndEveryEntityCanBeArchived() async throws {
        let (repository, _, place) = try await makeSampleRepository()
        let room = try XCTUnwrap(place.rooms.first { $0.name == "Hall Closet" })
        let area = try XCTUnwrap(place.areas.first { $0.roomID == room.id })
        let container = try await repository.createContainer(.init(name: "Outer", destination: .area(area.id)))
        let child = try await repository.createContainer(.init(name: "Inner", destination: .container(container.id)))
        let thing = try await repository.saveThing(.init(name: "Gloves"), to: .container(child.id))

        let archivedRoom = try await repository.archiveRoom(id: room.id)
        let places = try await repository.fetchPlaces()
        let fetched = try XCTUnwrap(places.first { $0.id == place.id })
        XCTAssertNotNil(archivedRoom.archivedAt)
        XCTAssertNotNil(fetched.areas.first { $0.id == area.id }?.archivedAt)
        XCTAssertNotNil(fetched.containers.first { $0.id == container.id }?.archivedAt)
        XCTAssertNotNil(fetched.containers.first { $0.id == child.id }?.archivedAt)
        XCTAssertNotNil(fetched.things.first { $0.id == thing.id }?.archivedAt)

        let originalThingArchiveDate = try XCTUnwrap(
            fetched.things.first { $0.id == thing.id }?.archivedAt
        )
        _ = try await repository.archivePlace(id: place.id)
        let placesAfterPlaceArchive = try await repository.fetchPlaces()
        let refetchedPlace = try XCTUnwrap(
            placesAfterPlaceArchive.first { $0.id == place.id }
        )
        XCTAssertEqual(
            refetchedPlace.things.first { $0.id == thing.id }?.archivedAt,
            originalThingArchiveDate
        )

        let separateActivePlace = try await repository.createPlace(.init(name: "Still Active"))
        let activeRoom = try await repository.createRoom(.init(
            placeID: separateActivePlace.id,
            name: "Room"
        ))
        let loneArea = try await repository.createArea(.init(roomID: activeRoom.id, name: "Lone Area"))
        let archivedArea = try await repository.archiveArea(id: loneArea.id)
        XCTAssertNotNil(archivedArea.archivedAt)
        let loneContainer = try await repository.createContainer(.init(
            name: "Lone Container", destination: .room(activeRoom.id)
        ))
        let archivedContainer = try await repository.archiveContainer(id: loneContainer.id)
        XCTAssertNotNil(archivedContainer.archivedAt)
        let loneThing = try await repository.saveThing(.init(name: "Lone Thing"), to: .room(activeRoom.id))
        let archivedThing = try await repository.archiveThing(id: loneThing.id)
        XCTAssertNotNil(archivedThing.archivedAt)

        let separatePlace = try await repository.createPlace(.init(name: "Archive Me"))
        let separateRoom = try await repository.createRoom(.init(placeID: separatePlace.id, name: "Room"))
        _ = try await repository.createArea(.init(roomID: separateRoom.id, name: "Area"))
        let archivedPlace = try await repository.archivePlace(id: separatePlace.id)
        XCTAssertNotNil(archivedPlace.archivedAt)
        XCTAssertTrue(archivedPlace.rooms.allSatisfy { $0.archivedAt != nil })
        XCTAssertTrue(archivedPlace.areas.allSatisfy { $0.archivedAt != nil })
    }

    func testNewDescendantsUseTheirPlacesPersistentStore() async throws {
        let (repository, persistence) = makeRepository()
        let place = try await repository.createPlace(.init(name: "Home"))
        let room = try await repository.createRoom(.init(placeID: place.id, name: "Room"))
        let area = try await repository.createArea(.init(
            roomID: room.id, name: "Area", photo: Self.photo(bytes: [0x01])
        ))
        let container = try await repository.createContainer(.init(
            name: "Container", destination: .area(area.id), photo: Self.photo(bytes: [0x02])
        ))
        let thing = try await repository.saveThing(
            .init(name: "Thing", keywords: ["Keyword"], photo: Self.photo(bytes: [0x03])),
            to: .container(container.id)
        )

        let context = persistence.newBackgroundContext(author: "witt.catalog.store-assignment")
        try await context.perform {
            let storedPlace: Place = try Self.fetch(id: place.id, entity: "Place", in: context)
            let expectedStore = try XCTUnwrap(storedPlace.objectID.persistentStore)
            let objects: [NSManagedObject] = [
                try Self.fetch(id: room.id, entity: "Room", in: context) as Room,
                try Self.fetch(id: area.id, entity: "Area", in: context) as Area,
                try Self.fetch(id: container.id, entity: "Container", in: context) as Container,
                try Self.fetch(id: thing.id, entity: "Thing", in: context) as Thing
            ]
            XCTAssertTrue(objects.allSatisfy { $0.objectID.persistentStore === expectedStore })
            let photos = try context.fetch(NSFetchRequest<PhotoAsset>(entityName: "PhotoAsset"))
            let keywords = try context.fetch(NSFetchRequest<ThingKeyword>(entityName: "ThingKeyword"))
            XCTAssertTrue((photos + keywords).allSatisfy { $0.objectID.persistentStore === expectedStore })
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

    private static func photo(bytes: [UInt8]) -> NormalizedPhoto {
        NormalizedPhoto(
            jpegData: Data(bytes),
            thumbnailJPEGData: Data(bytes.prefix(1)),
            dimensions: PhotoDimensions(width: 20, height: 10),
            source: .camera
        )
    }

    private func assertRepositoryError(
        _ expected: CatalogRepositoryError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(error as? CatalogRepositoryError, expected)
        }
    }

    private func assertPhotoAssets(
        in persistence: PersistenceController,
        expectedCount: Int,
        missingID: UUID? = nil
    ) async throws {
        let context = persistence.newBackgroundContext(author: "witt.catalog.photo-count")
        try await context.perform {
            let photos = try context.fetch(NSFetchRequest<PhotoAsset>(entityName: "PhotoAsset"))
            XCTAssertEqual(photos.count, expectedCount)
            if let missingID {
                XCTAssertFalse(photos.contains { $0.id == missingID })
            }
        }
    }
}
