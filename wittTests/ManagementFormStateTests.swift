import XCTest

@testable import witt

final class ManagementFormStateTests: XCTestCase {
    func testRouteIdentityIsStableAndIncludesAssociatedContext() {
        let id = UUID()
        let route = ManagementRoute.createRoom(placeID: id)

        XCTAssertEqual(route.id, route.id)
        XCTAssertEqual(route.id, route)
        XCTAssertNotEqual(route.id, .createRoom(placeID: nil))
        XCTAssertNotEqual(ManagementRoute.editThing(id).id, .editContainer(id))
    }

    func testThingPostSaveHandoffKeepsAddAnotherInsideTheCurrentFlow() {
        XCTAssertNil(ThingPostSaveHandoff(action: .addAnotherHere, thingID: UUID()))
    }

    func testThingPostSaveHandoffPreservesRoutingIntentAndSavedThingID() {
        let thingID = UUID()

        XCTAssertEqual(
            ThingPostSaveHandoff(action: .scanNext, thingID: thingID),
            .scanNext
        )
        XCTAssertEqual(
            ThingPostSaveHandoff(action: .viewThing, thingID: thingID),
            .viewThing(thingID)
        )
        XCTAssertEqual(
            ThingPostSaveHandoff(action: .done, thingID: thingID),
            .done
        )
    }

    func testThingPostSaveDismissalStateConsumesHandoffOnlyAfterDismissalFinishes() {
        let thingID = UUID()
        var state = ThingPostSaveDismissalState()

        XCTAssertNil(state.finish())
        state.begin(.viewThing(thingID))
        XCTAssertEqual(state.pendingHandoff, .viewThing(thingID))
        XCTAssertEqual(state.finish(), .viewThing(thingID))
        XCTAssertNil(state.pendingHandoff)
        XCTAssertNil(state.finish())
    }

    func testThingDestinationUsesSavedThingsExactHome() {
        let roomID = UUID()
        let areaID = UUID()
        let containerID = UUID()

        XCTAssertEqual(ThingDestination(home: .room(roomID)), .room(roomID))
        XCTAssertEqual(ThingDestination(home: .area(areaID)), .area(areaID))
        XCTAssertEqual(ThingDestination(home: .container(containerID)), .container(containerID))
    }

    func testValuesNormalizeDraftTextAndKeywords() {
        let values = ManagementFormValues(
            name: "  Flashlight  ",
            notes: " \n ",
            detail: "  Top shelf ",
            keywords: " torch, emergency, , battery  "
        )

        XCTAssertEqual(values.normalizedName, "Flashlight")
        XCTAssertNil(values.normalizedNotes)
        XCTAssertEqual(values.normalizedDetail, "Top shelf")
        XCTAssertEqual(values.parsedKeywords, ["torch", "emergency", "battery"])
    }

    func testPhotoSelectionMapsCreateAndUpdateMutations() {
        let photo = makePhoto()
        XCTAssertNil(ManagementPhotoSelection.unchanged.createPhoto)
        XCTAssertEqual(ManagementPhotoSelection.replacement(photo).createPhoto, photo)
        XCTAssertEqual(ManagementPhotoSelection.unchanged.updateMutation, .unchanged)
        XCTAssertEqual(ManagementPhotoSelection.replacement(photo).updateMutation, .replace(photo))
        XCTAssertEqual(ManagementPhotoSelection.removed.updateMutation, .remove)
    }

    func testContextPreselectionUsesValidContextThenFirstOption() {
        let firstID = UUID()
        let secondID = UUID()
        let options = [
            ThingDestinationOption(destination: .room(firstID), locationComponents: ["Home", "Office"]),
            ThingDestinationOption(
                destination: .area(secondID), locationComponents: ["Home", "Garage", "Shelf"]),
        ]

        XCTAssertEqual(
            ManagementPreselection.thingDestination(context: .area(secondID), options: options),
            .area(secondID)
        )
        XCTAssertEqual(
            ManagementPreselection.thingDestination(context: .container(UUID()), options: options),
            .room(firstID)
        )
        XCTAssertNil(ManagementPreselection.thingDestination(context: nil, options: []))
    }

    func testArchiveFactsMentionOnlyNonzeroDescendantsAndQRAttention() {
        let facts = ManagementArchiveFacts(
            ArchiveImpactSummary(
                storageAreaCount: 1,
                containerCount: 2,
                thingCount: 0,
                containsBoundQRCode: true
            ), roomCount: 1)

        XCTAssertTrue(facts.message.contains("1 Room"))
        XCTAssertTrue(facts.message.contains("1 Storage Area"))
        XCTAssertTrue(facts.message.contains("2 Containers"))
        XCTAssertFalse(facts.message.contains("0 Things"))
        XCTAssertTrue(facts.message.contains("QR codes"))
        XCTAssertTrue(facts.message.contains("will also be archived"))
    }

    func testAIAnalysisRunsForCreateButNotEditPhotoSelection() {
        XCTAssertEqual(ManagementAIDecision.afterSelectingPhoto(isCreating: true), .analyze)
        XCTAssertEqual(ManagementAIDecision.afterSelectingPhoto(isCreating: false), .skip)
    }

    func testQRAssignmentDecisionAcceptsUnknownAndExpectedTargetsWithoutStealing() {
        let areaID = QRTargetID(rawValue: UUID())
        let containerID = QRTargetID(rawValue: UUID())

        XCTAssertEqual(
            QRAssignmentDecision.evaluate(resolution: .unknown, expectedTarget: nil),
            .assign
        )
        XCTAssertEqual(
            QRAssignmentDecision.evaluate(
                resolution: .knownArea(areaID), expectedTarget: .area(areaID)),
            .accept
        )
        XCTAssertEqual(
            QRAssignmentDecision.evaluate(
                resolution: .knownContainer(containerID), expectedTarget: .area(areaID)),
            .alreadyAttached
        )
        XCTAssertEqual(
            QRAssignmentDecision.evaluate(
                resolution: .knownArea(areaID), expectedTarget: nil),
            .alreadyAttached
        )
    }

    func testQRAssignmentDecisionPreservesActionableRepairDetails() {
        let target = QRBindingTarget.area(QRTargetID(rawValue: UUID()))
        let repair = QRCodeRepair(reason: .missingTarget)
        let conflict = QRCodeConflict(firstTarget: target, secondTarget: target)

        XCTAssertEqual(
            QRAssignmentDecision.evaluate(
                resolution: .needsRepair(repair), expectedTarget: target),
            .repair(.unavailable(repair))
        )
        XCTAssertEqual(
            QRAssignmentDecision.evaluate(
                resolution: .conflict(conflict), expectedTarget: target),
            .repair(.conflict(conflict))
        )
    }

    func testAISuggestionOnlyClaimsNameWhenItSuppliesTheName() {
        let suggestion = ThingLabelSuggestion(
            proposedName: "Flashlight",
            keywords: ["torch", "battery"],
            detail: "Black aluminum body."
        )
        let userNamed = ManagementAISuggestionApplication.apply(
            suggestion,
            to: ManagementFormValues(name: "My Torch")
        )

        XCTAssertEqual(userNamed.values.name, "My Torch")
        XCTAssertEqual(userNamed.values.parsedKeywords, ["torch", "battery"])
        XCTAssertFalse(userNamed.suppliedName)
        XCTAssertTrue(userNamed.suppliedKeywords)
        XCTAssertTrue(userNamed.suppliedNotes)

        let aiNamed = ManagementAISuggestionApplication.apply(
            suggestion,
            to: ManagementFormValues()
        )
        XCTAssertEqual(aiNamed.values.name, "Flashlight")
        XCTAssertTrue(aiNamed.suppliedName)

        let empty = ManagementAISuggestionApplication.apply(
            ThingLabelSuggestion(proposedName: "  ", detail: nil),
            to: ManagementFormValues()
        )
        XCTAssertFalse(empty.suppliedName)
        XCTAssertFalse(empty.suppliedKeywords)
        XCTAssertFalse(empty.suppliedNotes)
    }

    func testAISuggestionPreservesManualEditsMadeWhileAnalysisWasPending() {
        let suggestion = ThingLabelSuggestion(
            proposedName: "Flashlight",
            keywords: ["torch", "battery"],
            detail: "Black aluminum body."
        )
        let current = ManagementFormValues(
            name: "My Torch",
            notes: "",
            keywords: ""
        )

        let application = ManagementAISuggestionApplication.apply(
            suggestion,
            to: current,
            preserving: [.name, .notes]
        )

        XCTAssertEqual(application.values.name, "My Torch")
        XCTAssertEqual(application.values.notes, "")
        XCTAssertEqual(application.values.parsedKeywords, ["torch", "battery"])
        XCTAssertFalse(application.suppliedName)
        XCTAssertFalse(application.suppliedNotes)
        XCTAssertTrue(application.suppliedKeywords)
    }

    func testAISuggestionDoesNotFillAFieldThatWasEditedThenCleared() {
        let suggestion = ThingLabelSuggestion(
            proposedName: "Flashlight",
            keywords: ["torch"],
            detail: "Black aluminum body."
        )

        let application = ManagementAISuggestionApplication.apply(
            suggestion,
            to: ManagementFormValues(),
            preserving: [.name, .keywords, .notes]
        )

        XCTAssertEqual(application.values, ManagementFormValues())
        XCTAssertFalse(application.suppliedName)
        XCTAssertFalse(application.suppliedKeywords)
        XCTAssertFalse(application.suppliedNotes)
    }

    private func makePhoto() -> NormalizedPhoto {
        NormalizedPhoto(
            jpegData: Data([1, 2, 3]),
            thumbnailJPEGData: Data([1]),
            dimensions: PhotoDimensions(width: 10, height: 20),
            source: .camera
        )
    }
}
