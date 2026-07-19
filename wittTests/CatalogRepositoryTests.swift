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

        try await repository.bindQRCode(.init(token: token, target: area.bindingTarget))
        let resolution = try await repository.resolve(token)
        let remainingTargets = try await repository.unassignedQRCodeTargets()
        XCTAssertEqual(resolution, .knownArea(QRTargetID(rawValue: area.id)))
        XCTAssertFalse(remainingTargets.contains { $0.id == area.id })
    }

    func testResolveLeavesRetiredScanMetadataUnsetAndPreservesLegacyValues() async throws {
        let (repository, persistence, place) = try await makeSampleRepository()
        let area = try XCTUnwrap(place.areas.first)
        let token = try QRToken.generate()
        let target = QRBindingTarget.area(QRTargetID(rawValue: area.id))

        _ = try await repository.bindQRCode(.init(token: token, target: target))

        let legacyValue = Date(timeIntervalSince1970: 1_700_000_000)
        let context = persistence.viewContext
        try await context.perform {
            let rows = try Self.qrRows(token: token, in: context)
            XCTAssertEqual(rows.count, 1)
            let row = try XCTUnwrap(rows.first)
            XCTAssertNil(row.value(forKey: "lastScannedAt"))
            row.setValue(legacyValue, forKey: "lastScannedAt")
            try context.save()
        }

        let resolution = try await repository.resolve(token)

        XCTAssertEqual(resolution, .knownArea(QRTargetID(rawValue: area.id)))
        let verificationContext = persistence.newBackgroundContext(author: "witt.catalog.qr-retired-scan-metadata")
        try await verificationContext.perform {
            let rows = try Self.qrRows(token: token, in: verificationContext)
            XCTAssertEqual(rows.count, 1)
            let row = try XCTUnwrap(rows.first)
            XCTAssertEqual(row.value(forKey: "lastScannedAt") as? Date, legacyValue)
        }
    }

    func testArbitraryPayloadBindsAndResolvesByExactIdentity() async throws {
        let (repository, _, place) = try await makeSampleRepository()
        let area = try XCTUnwrap(place.areas.first)
        let target = QRBindingTarget.area(QRTargetID(rawValue: area.id))
        let payload = try XCTUnwrap(QRToken(rawValue: "  vendor:item/42?serial=A+B  "))

        _ = try await repository.bindQRCode(.init(token: payload, target: target))

        let exactResolution = try await repository.resolve(payload)
        let trimmedPayload = try XCTUnwrap(QRToken(rawValue: "vendor:item/42?serial=A+B"))
        let trimmedResolution = try await repository.resolve(trimmedPayload)
        XCTAssertEqual(exactResolution, .knownArea(QRTargetID(rawValue: area.id)))
        XCTAssertEqual(trimmedResolution, .unknown)
    }

    func testCreateAreaWithQRCodeIsAtomicAndPreservesDraftFields() async throws {
        let (repository, persistence, place) = try await makeSampleRepository()
        let room = try XCTUnwrap(place.rooms.first)
        let token = try QRToken.generate()
        let photo = Self.photo(bytes: [0x11, 0x22, 0x33])

        let area = try await repository.createArea(.init(
            roomID: room.id,
            name: " Seasonal Shelf ",
            detail: " Above the coats ",
            photo: photo,
            qrToken: token
        ))

        XCTAssertEqual(area.name, "Seasonal Shelf")
        XCTAssertEqual(area.detail, "Above the coats")
        XCTAssertEqual(area.primaryPhoto?.data, photo.jpegData)
        XCTAssertTrue(area.hasQRCode)
        let resolution = try await repository.resolve(token)
        XCTAssertEqual(resolution, .knownArea(QRTargetID(rawValue: area.id)))

        let context = persistence.newBackgroundContext(author: "witt.catalog.area-qr-tests")
        try await context.perform {
            let storedArea: Area = try Self.fetch(id: area.id, entity: "Area", in: context)
            let qrCode = try XCTUnwrap((storedArea.qrCodes?.allObjects as? [QRCode])?.first)
            XCTAssertEqual(qrCode.objectID.persistentStore, storedArea.objectID.persistentStore)
            XCTAssertEqual(storedArea.primaryPhoto?.objectID.persistentStore, storedArea.objectID.persistentStore)
        }
    }

    func testCreateContainerWithQRCodeIsAtomicAndPreservesDraftFields() async throws {
        let (repository, persistence, place) = try await makeSampleRepository()
        let area = try XCTUnwrap(place.areas.first)
        let token = try QRToken.generate()
        let photo = Self.photo(bytes: [0x44, 0x55, 0x66])

        let container = try await repository.createContainer(.init(
            name: " Green Crate ",
            detail: " Holiday lights ",
            destination: .area(area.id),
            photo: photo,
            qrToken: token
        ))

        XCTAssertEqual(container.name, "Green Crate")
        XCTAssertEqual(container.detail, "Holiday lights")
        XCTAssertEqual(container.primaryPhoto?.data, photo.jpegData)
        XCTAssertTrue(container.hasQRCode)
        let resolution = try await repository.resolve(token)
        XCTAssertEqual(resolution, .knownContainer(QRTargetID(rawValue: container.id)))

        let context = persistence.newBackgroundContext(author: "witt.catalog.container-qr-tests")
        try await context.perform {
            let stored: Container = try Self.fetch(id: container.id, entity: "Container", in: context)
            let qrCode = try XCTUnwrap((stored.qrCodes?.allObjects as? [QRCode])?.first)
            XCTAssertEqual(qrCode.objectID.persistentStore, stored.objectID.persistentStore)
            XCTAssertEqual(stored.primaryPhoto?.objectID.persistentStore, stored.objectID.persistentStore)
        }
    }

    func testCreateTargetsAtomicallyBindArbitraryPayloads() async throws {
        let (repository, _, place) = try await makeSampleRepository()
        let room = try XCTUnwrap(place.rooms.first)
        let area = try XCTUnwrap(place.areas.first)
        let areaPayload = try XCTUnwrap(QRToken(rawValue: "AREA 001 / upper shelf"))
        let containerPayload = try XCTUnwrap(QRToken(rawValue: "https://labels.example/box?id=7&lot=A+B"))

        let createdArea = try await repository.createArea(.init(
            roomID: room.id, name: "Arbitrary Area", qrToken: areaPayload
        ))
        let createdContainer = try await repository.createContainer(.init(
            name: "Arbitrary Container", destination: .area(area.id), qrToken: containerPayload
        ))

        let areaResolution = try await repository.resolve(areaPayload)
        let containerResolution = try await repository.resolve(containerPayload)
        XCTAssertEqual(areaResolution, .knownArea(QRTargetID(rawValue: createdArea.id)))
        XCTAssertEqual(containerResolution, .knownContainer(QRTargetID(rawValue: createdContainer.id)))
    }

    func testCreateTargetsRejectUsedQRCodeWithoutCreatingTargets() async throws {
        let (repository, _, place) = try await makeSampleRepository()
        let room = try XCTUnwrap(place.rooms.first)
        let area = try XCTUnwrap(place.areas.first)
        let existingTarget = try XCTUnwrap(place.areas.first { $0.id != area.id })
        let token = try QRToken.generate()
        let existingBindingTarget = QRBindingTarget.area(QRTargetID(rawValue: existingTarget.id))
        _ = try await repository.bindQRCode(.init(token: token, target: existingBindingTarget))
        let before = try await repository.fetchPlaces()

        await assertRepositoryError(.tokenAlreadyBound) {
            _ = try await repository.createArea(.init(
                roomID: room.id, name: "Must Not Exist", qrToken: token
            ))
        }
        await assertRepositoryError(.tokenAlreadyBound) {
            _ = try await repository.createContainer(.init(
                name: "Also Must Not Exist", destination: .area(area.id), qrToken: token
            ))
        }

        let after = try await repository.fetchPlaces()
        XCTAssertEqual(after, before)
    }

    func testReplaceQRCodesForAreaAndContainerReleasesOldTokens() async throws {
        let (repository, _, place) = try await makeSampleRepository()
        let area = try XCTUnwrap(place.areas.first)
        let container = try XCTUnwrap(place.containers.first)
        let oldAreaToken = try QRToken.generate()
        let newAreaToken = try XCTUnwrap(QRToken(rawValue: "custom area label / lower shelf"))
        let oldContainerToken = try QRToken.generate()
        let newContainerToken = try QRToken.generate()
        let areaTarget = QRBindingTarget.area(QRTargetID(rawValue: area.id))
        let containerTarget = QRBindingTarget.container(QRTargetID(rawValue: container.id))
        _ = try await repository.bindQRCode(.init(token: oldAreaToken, target: areaTarget))
        _ = try await repository.bindQRCode(.init(token: oldContainerToken, target: containerTarget))

        _ = try await repository.replaceQRCode(.init(token: newAreaToken, target: areaTarget))
        _ = try await repository.replaceQRCode(.init(token: newContainerToken, target: containerTarget))

        let oldAreaResolution = try await repository.resolve(oldAreaToken)
        let newAreaResolution = try await repository.resolve(newAreaToken)
        let oldContainerResolution = try await repository.resolve(oldContainerToken)
        let newContainerResolution = try await repository.resolve(newContainerToken)
        XCTAssertEqual(oldAreaResolution, .unknown)
        XCTAssertEqual(newAreaResolution, .knownArea(QRTargetID(rawValue: area.id)))
        XCTAssertEqual(oldContainerResolution, .unknown)
        XCTAssertEqual(newContainerResolution, .knownContainer(QRTargetID(rawValue: container.id)))
    }

    func testReplaceQRCodeRefusesTokenBoundElsewhereAndPreservesBothBindings() async throws {
        let (repository, _, place) = try await makeSampleRepository()
        let areas = place.areas.prefix(2)
        let first = try XCTUnwrap(areas.first)
        let second = try XCTUnwrap(areas.last)
        let firstToken = try QRToken.generate()
        let secondToken = try QRToken.generate()
        let firstTarget = QRBindingTarget.area(QRTargetID(rawValue: first.id))
        let secondTarget = QRBindingTarget.area(QRTargetID(rawValue: second.id))
        _ = try await repository.bindQRCode(.init(token: firstToken, target: firstTarget))
        _ = try await repository.bindQRCode(.init(token: secondToken, target: secondTarget))

        await assertRepositoryError(.tokenAlreadyBound) {
            _ = try await repository.replaceQRCode(.init(token: secondToken, target: firstTarget))
        }

        let firstResolution = try await repository.resolve(firstToken)
        let secondResolution = try await repository.resolve(secondToken)
        XCTAssertEqual(firstResolution, .knownArea(QRTargetID(rawValue: first.id)))
        XCTAssertEqual(secondResolution, .knownArea(QRTargetID(rawValue: second.id)))
    }

    func testReplaceArbitraryPayloadReleasesOldBindingAndRefusesConflict() async throws {
        let (repository, _, place) = try await makeSampleRepository()
        let areas = place.areas.prefix(2)
        let first = try XCTUnwrap(areas.first)
        let second = try XCTUnwrap(areas.last)
        let oldPayload = try XCTUnwrap(QRToken(rawValue: "legacy generated-like label"))
        let replacement = try XCTUnwrap(QRToken(rawValue: "external://label/42?x=A+B"))
        let occupied = try XCTUnwrap(QRToken(rawValue: "occupied payload"))
        let firstTarget = QRBindingTarget.area(QRTargetID(rawValue: first.id))
        let secondTarget = QRBindingTarget.area(QRTargetID(rawValue: second.id))
        _ = try await repository.bindQRCode(.init(token: oldPayload, target: firstTarget))
        _ = try await repository.bindQRCode(.init(token: occupied, target: secondTarget))

        _ = try await repository.replaceQRCode(.init(token: replacement, target: firstTarget))
        await assertRepositoryError(.tokenAlreadyBound) {
            _ = try await repository.replaceQRCode(.init(token: occupied, target: firstTarget))
        }

        let oldResolution = try await repository.resolve(oldPayload)
        let replacementResolution = try await repository.resolve(replacement)
        let occupiedResolution = try await repository.resolve(occupied)
        XCTAssertEqual(oldResolution, .unknown)
        XCTAssertEqual(replacementResolution, .knownArea(QRTargetID(rawValue: first.id)))
        XCTAssertEqual(occupiedResolution, .knownArea(QRTargetID(rawValue: second.id)))
    }

    func testReplaceQRCodeWithSameTargetIsIdempotentAndRemovesOtherTargetRows() async throws {
        let (repository, persistence, place) = try await makeSampleRepository()
        let area = try XCTUnwrap(place.areas.first)
        let retainedToken = try QRToken.generate()
        let obsoleteToken = try QRToken.generate()
        let areaTarget = QRBindingTarget.area(QRTargetID(rawValue: area.id))
        _ = try await repository.bindQRCode(.init(token: retainedToken, target: areaTarget))

        let context = persistence.viewContext
        try await context.perform {
            let storedArea: Area = try Self.fetch(id: area.id, entity: "Area", in: context)
            let obsolete: QRCode = Self.insert("QRCode", into: context)
            obsolete.token = obsoleteToken.rawValue
            obsolete.state = "bound"
            obsolete.place = storedArea.place
            obsolete.area = storedArea
            try context.save()
        }

        try await repository.replaceQRCode(.init(
            token: retainedToken, target: areaTarget
        ))

        let retainedResolution = try await repository.resolve(retainedToken)
        let obsoleteResolution = try await repository.resolve(obsoleteToken)
        XCTAssertEqual(retainedResolution, .knownArea(QRTargetID(rawValue: area.id)))
        XCTAssertEqual(obsoleteResolution, .unknown)
        try await context.perform {
            let storedArea: Area = try Self.fetch(id: area.id, entity: "Area", in: context)
            XCTAssertEqual((storedArea.qrCodes?.allObjects as? [QRCode])?.count, 1)
        }
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

    func testRepairMissingBindingToUnassignedTargetLeavesExactlyOneValidRow() async throws {
        let (repository, persistence, place) = try await makeSampleRepository()
        let target = try XCTUnwrap(place.areas.first)
        let token = try XCTUnwrap(QRToken(rawValue: "missing target repair"))
        let context = persistence.viewContext

        try await context.perform {
            let placeObject: Place = try Self.fetch(id: place.id, entity: "Place", in: context)
            let broken: QRCode = Self.insert("QRCode", into: context)
            broken.token = token.rawValue
            broken.state = "bound"
            broken.place = placeObject
            try context.save()
        }

        try await repository.repairQRCode(.init(
            token: token,
            target: .area(QRTargetID(rawValue: target.id))
        ))

        let resolution = try await repository.resolve(token)
        XCTAssertEqual(resolution, .knownArea(QRTargetID(rawValue: target.id)))
        try await context.perform {
            let rows = try Self.qrRows(token: token, in: context)
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows.first?.area?.id, target.id)
            XCTAssertEqual(rows.first?.objectID.persistentStore, rows.first?.area?.objectID.persistentStore)
        }
    }

    func testDuplicateRowsForOneTargetRequireRepairAndConsolidateToOneRow() async throws {
        let (repository, persistence, place) = try await makeSampleRepository()
        let target = try XCTUnwrap(place.areas.first)
        let token = try XCTUnwrap(QRToken(rawValue: "duplicate same target"))
        let context = persistence.viewContext

        try await context.perform {
            let placeObject: Place = try Self.fetch(id: place.id, entity: "Place", in: context)
            let areaObject: Area = try Self.fetch(id: target.id, entity: "Area", in: context)
            for _ in 0..<2 {
                let row: QRCode = Self.insert("QRCode", into: context)
                row.token = token.rawValue
                row.state = "bound"
                row.place = placeObject
                row.area = areaObject
            }
            try context.save()
        }

        guard case .needsRepair(let repair) = try await repository.resolve(token) else {
            return XCTFail("Duplicate bindings should require repair")
        }
        XCTAssertEqual(repair.reason, .duplicateBindings)

        _ = try await repository.repairQRCode(.init(
            token: token,
            target: .area(QRTargetID(rawValue: target.id))
        ))

        let resolution = try await repository.resolve(token)
        XCTAssertEqual(resolution, .knownArea(QRTargetID(rawValue: target.id)))
        try await context.perform {
            XCTAssertEqual(try Self.qrRows(token: token, in: context).count, 1)
        }
    }

    func testRepairArchivedBindingMovesCodeToActiveUnassignedTarget() async throws {
        let (repository, _, place) = try await makeSampleRepository()
        let archivedArea = try XCTUnwrap(place.areas.first)
        let destination = try XCTUnwrap(place.areas.first { $0.id != archivedArea.id })
        let token = try QRToken.generate()
        _ = try await repository.bindQRCode(.init(
            token: token,
            target: .area(QRTargetID(rawValue: archivedArea.id))
        ))
        _ = try await repository.archiveArea(id: archivedArea.id)

        _ = try await repository.repairQRCode(.init(
            token: token,
            target: .area(QRTargetID(rawValue: destination.id))
        ))

        let resolution = try await repository.resolve(token)
        XCTAssertEqual(resolution, .knownArea(QRTargetID(rawValue: destination.id)))
        let places = try await repository.fetchPlaces()
        let fetched = try XCTUnwrap(places.first)
        XCTAssertFalse(try XCTUnwrap(fetched.areas.first { $0.id == archivedArea.id }).hasQRCode)
        XCTAssertTrue(try XCTUnwrap(fetched.areas.first { $0.id == destination.id }).hasQRCode)
    }

    func testRepairConflictChooseOneConsolidatesAllRows() async throws {
        let (repository, persistence, place) = try await makeSampleRepository()
        let area = try XCTUnwrap(place.areas.first)
        let container = try XCTUnwrap(place.containers.first)
        let token = try XCTUnwrap(QRToken(rawValue: "conflict choose one"))
        let context = persistence.viewContext

        try await context.perform {
            let placeObject: Place = try Self.fetch(id: place.id, entity: "Place", in: context)
            let areaObject: Area = try Self.fetch(id: area.id, entity: "Area", in: context)
            let containerObject: Container = try Self.fetch(id: container.id, entity: "Container", in: context)
            let areaRow: QRCode = Self.insert("QRCode", into: context)
            areaRow.token = token.rawValue
            areaRow.state = "bound"
            areaRow.place = placeObject
            areaRow.area = areaObject
            let containerRow: QRCode = Self.insert("QRCode", into: context)
            containerRow.token = token.rawValue
            containerRow.state = "bound"
            containerRow.place = placeObject
            containerRow.container = containerObject
            try context.save()
        }

        let areaIsEligible = try await repository.repairQRCodeTargetIsEligible(.init(
            token: token,
            target: .area(QRTargetID(rawValue: area.id))
        ))
        let containerIsEligible = try await repository.repairQRCodeTargetIsEligible(.init(
            token: token,
            target: .container(QRTargetID(rawValue: container.id))
        ))
        XCTAssertTrue(areaIsEligible)
        XCTAssertTrue(containerIsEligible)

        _ = try await repository.repairQRCode(.init(
            token: token,
            target: .container(QRTargetID(rawValue: container.id))
        ))

        let resolution = try await repository.resolve(token)
        XCTAssertEqual(resolution, .knownContainer(QRTargetID(rawValue: container.id)))
        try await context.perform {
            let rows = try Self.qrRows(token: token, in: context)
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows.first?.container?.id, container.id)
            let storedArea: Area = try Self.fetch(id: area.id, entity: "Area", in: context)
            XCTAssertTrue(((storedArea.qrCodes?.allObjects as? [QRCode]) ?? []).isEmpty)
        }
    }

    func testRepairCreateAndBindRemovesDamageAndCreatesOneBoundTarget() async throws {
        let (repository, persistence) = makeRepository()
        let seeded = try await repository.seedHomeIfNeeded()
        let place = try XCTUnwrap(seeded)
        let token = try XCTUnwrap(QRToken(rawValue: "repair create payload"))
        let context = persistence.viewContext
        try await context.perform {
            let placeObject: Place = try Self.fetch(id: place.id, entity: "Place", in: context)
            let broken: QRCode = Self.insert("QRCode", into: context)
            broken.token = token.rawValue
            broken.state = "bound"
            broken.place = placeObject
            try context.save()
        }

        let target = try await repository.repairCreateTargetAndBindQRCode(.init(
            token: token,
            placeID: place.id,
            room: .new(name: "Utility"),
            area: .new(name: "Upper Shelf"),
            attachment: .newContainer(name: "Repair Box")
        ))

        XCTAssertEqual(target.kind, .container)
        let resolution = try await repository.resolve(token)
        XCTAssertEqual(resolution, .knownContainer(QRTargetID(rawValue: target.id)))
        try await context.perform {
            let rows = try Self.qrRows(token: token, in: context)
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows.first?.container?.id, target.id)
            XCTAssertEqual(rows.first?.objectID.persistentStore, rows.first?.container?.objectID.persistentStore)
        }
    }

    func testReleaseRepairableQRCodeMakesConflictTokenRetryableForDraft() async throws {
        let (repository, persistence, place) = try await makeSampleRepository()
        let area = try XCTUnwrap(place.areas.first)
        let container = try XCTUnwrap(place.containers.first)
        let token = try XCTUnwrap(QRToken(rawValue: "release conflict for draft"))
        let context = persistence.viewContext
        try await context.perform {
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

        try await repository.releaseRepairableQRCode(token)

        let resolution = try await repository.resolve(token)
        XCTAssertEqual(resolution, .unknown)
        try await context.perform {
            XCTAssertTrue(try Self.qrRows(token: token, in: context).isEmpty)
        }
    }

    func testRepairOperationsRefuseUnknownAndHealthyKnownTokens() async throws {
        let (repository, _, place) = try await makeSampleRepository()
        let area = try XCTUnwrap(place.areas.first)
        let room = try XCTUnwrap(place.rooms.first)
        let unknown = try XCTUnwrap(QRToken(rawValue: "unknown repair refusal"))
        let healthy = try XCTUnwrap(QRToken(rawValue: "healthy repair refusal"))
        let target = QRBindingTarget.area(QRTargetID(rawValue: area.id))
        _ = try await repository.bindQRCode(.init(token: healthy, target: target))

        for token in [unknown, healthy] {
            await assertRepositoryError(.qrCodeNotRepairable) {
                _ = try await repository.repairQRCode(.init(token: token, target: target))
            }
            await assertRepositoryError(.qrCodeNotRepairable) {
                try await repository.releaseRepairableQRCode(token)
            }
            await assertRepositoryError(.qrCodeNotRepairable) {
                _ = try await repository.repairCreateTargetAndBindQRCode(.init(
                    token: token,
                    placeID: place.id,
                    room: .existing(room.id),
                    area: .new(name: "Must Not Exist"),
                    attachment: .area
                ))
            }
        }

        let unknownResolution = try await repository.resolve(unknown)
        let healthyResolution = try await repository.resolve(healthy)
        XCTAssertEqual(unknownResolution, .unknown)
        XCTAssertEqual(healthyResolution, .knownArea(QRTargetID(rawValue: area.id)))
    }

    func testRepairRefusesChosenTargetWithDifferentHealthyQRCode() async throws {
        let (repository, persistence, place) = try await makeSampleRepository()
        let conflictArea = try XCTUnwrap(place.areas.first)
        let occupiedArea = try XCTUnwrap(place.areas.first { $0.id != conflictArea.id })
        let conflictContainer = try XCTUnwrap(place.containers.first)
        let conflictToken = try XCTUnwrap(QRToken(rawValue: "conflict cannot take occupied"))
        let healthyToken = try XCTUnwrap(QRToken(rawValue: "healthy occupied target"))
        _ = try await repository.bindQRCode(.init(
            token: healthyToken,
            target: .area(QRTargetID(rawValue: occupiedArea.id))
        ))
        let context = persistence.viewContext
        try await context.perform {
            let placeObject: Place = try Self.fetch(id: place.id, entity: "Place", in: context)
            let areaObject: Area = try Self.fetch(id: conflictArea.id, entity: "Area", in: context)
            let containerObject: Container = try Self.fetch(id: conflictContainer.id, entity: "Container", in: context)
            let first: QRCode = Self.insert("QRCode", into: context)
            first.token = conflictToken.rawValue
            first.state = "bound"
            first.place = placeObject
            first.area = areaObject
            let second: QRCode = Self.insert("QRCode", into: context)
            second.token = conflictToken.rawValue
            second.state = "bound"
            second.place = placeObject
            second.container = containerObject
            try context.save()
        }

        let occupiedIsEligible = try await repository.repairQRCodeTargetIsEligible(.init(
            token: conflictToken,
            target: .area(QRTargetID(rawValue: occupiedArea.id))
        ))
        XCTAssertFalse(occupiedIsEligible)

        await assertRepositoryError(.targetAlreadyHasQRCode) {
            _ = try await repository.repairQRCode(.init(
                token: conflictToken,
                target: .area(QRTargetID(rawValue: occupiedArea.id))
            ))
        }

        guard case .conflict = try await repository.resolve(conflictToken) else {
            return XCTFail("The conflicting rows should be preserved after refusal")
        }
        let healthyResolution = try await repository.resolve(healthyToken)
        XCTAssertEqual(healthyResolution, .knownArea(QRTargetID(rawValue: occupiedArea.id)))
    }

    func testContextualRepairCanExplicitlyReplaceChosenTargetsHealthyQRCode() async throws {
        let (repository, persistence, place) = try await makeSampleRepository()
        let target = try XCTUnwrap(place.areas.first)
        let damagedToken = try XCTUnwrap(QRToken(rawValue: "damaged contextual reattach"))
        let replacedToken = try XCTUnwrap(QRToken(rawValue: "healthy code being replaced"))
        let targetBinding = QRBindingTarget.area(QRTargetID(rawValue: target.id))
        _ = try await repository.bindQRCode(.init(
            token: replacedToken,
            target: targetBinding
        ))

        let context = persistence.viewContext
        try await context.perform {
            let placeObject: Place = try Self.fetch(id: place.id, entity: "Place", in: context)
            let broken: QRCode = Self.insert("QRCode", into: context)
            broken.token = damagedToken.rawValue
            broken.state = "bound"
            broken.place = placeObject
            try context.save()
        }

        _ = try await repository.repairAndReplaceQRCode(.init(
            token: damagedToken,
            target: targetBinding
        ))

        let repairedResolution = try await repository.resolve(damagedToken)
        let replacedResolution = try await repository.resolve(replacedToken)
        XCTAssertEqual(repairedResolution, .knownArea(QRTargetID(rawValue: target.id)))
        XCTAssertEqual(replacedResolution, .unknown)
        try await context.perform {
            let storedArea: Area = try Self.fetch(id: target.id, entity: "Area", in: context)
            let rows = (storedArea.qrCodes?.allObjects as? [QRCode]) ?? []
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows.first?.token, damagedToken.rawValue)
        }
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

    private static func qrRows(
        token: QRToken,
        in context: NSManagedObjectContext
    ) throws -> [QRCode] {
        let request = NSFetchRequest<QRCode>(entityName: "QRCode")
        request.predicate = NSPredicate(format: "token == %@", token.rawValue)
        return try context.fetch(request)
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
