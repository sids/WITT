import CoreData
import Foundation

public enum ManagedObjectDomainValidator {
    public static func validate(_ place: Place) throws {
        guard place.id != nil else { throw DomainValidationError.missingPlace }
        try validatePrimaryPhoto(place.primaryPhoto, expectedOwner: place)
    }

    public static func validate(_ room: Room) throws {
        guard room.place?.id != nil else { throw DomainValidationError.missingPlace }
    }

    public static func validate(_ area: Area) throws {
        try ContainmentValidator.validatePlaceOwnership(
            childPlaceID: area.place?.id,
            parentPlaceID: area.room?.place?.id
        )
        try validatePrimaryPhoto(area.primaryPhoto, expectedOwner: area)
    }

    public static func validate(_ thing: Thing) throws {
        let homes = try [
            thing.homeRoom.map { ThingHome.room(try reference(for: $0, place: $0.place)) },
            thing.homeArea.map { ThingHome.area(try reference(for: $0, place: $0.place)) },
            thing.homeContainer.map {
                ThingHome.container(try reference(for: $0, place: $0.place))
            }
        ].compactMap { $0 }

        try ContainmentValidator.validateThing(placeID: thing.place?.id, homes: homes)
        try validatePrimaryPhoto(thing.primaryPhoto, expectedOwner: thing)
    }

    public static func validate(_ container: Container) throws {
        let parents = try [
            container.parentRoom.map {
                ContainerParent.room(try reference(for: $0, place: $0.place))
            },
            container.parentArea.map {
                ContainerParent.area(try reference(for: $0, place: $0.place))
            },
            container.parentContainer.map {
                ContainerParent.container(try reference(for: $0, place: $0.place))
            }
        ].compactMap { $0 }

        try ContainmentValidator.validateContainer(placeID: container.place?.id, parents: parents)
        try validateNoCycle(container)
        try validatePrimaryPhoto(container.primaryPhoto, expectedOwner: container)
    }

    public static func validate(_ qrCode: QRCode) throws {
        let targets = try [
            qrCode.area.map { QRCodeTarget.area(try reference(for: $0, place: $0.place)) },
            qrCode.container.map {
                QRCodeTarget.container(try reference(for: $0, place: $0.place))
            }
        ].compactMap { $0 }

        try ContainmentValidator.validateQRCode(
            placeID: qrCode.place?.id,
            targets: targets,
            isBound: qrCode.state == "bound"
        )
    }

    public static func validate(_ photo: PhotoAsset) throws {
        let owners = try [
            photo.placeOwner.map { owner in
                guard let id = owner.id else { throw DomainValidationError.missingPlace }
                return PhotoOwner.place(id)
            },
            photo.areaOwner.map { PhotoOwner.area(try reference(for: $0, place: $0.place)) },
            photo.containerOwner.map {
                PhotoOwner.container(try reference(for: $0, place: $0.place))
            },
            photo.thingOwner.map { PhotoOwner.thing(try reference(for: $0, place: $0.place)) }
        ].compactMap { $0 }

        try ContainmentValidator.validatePhoto(placeID: photo.place?.id, owners: owners)
    }

    public static func validate(_ keyword: ThingKeyword) throws {
        try ContainmentValidator.validatePlaceOwnership(
            childPlaceID: keyword.place?.id,
            parentPlaceID: keyword.thing?.place?.id
        )
    }

    private static func reference(
        for _: NSManagedObject,
        place: Place?
    ) throws -> PlaceOwnedReference {
        guard let placeID = place?.id else { throw DomainValidationError.missingPlace }
        return PlaceOwnedReference(placeID: placeID)
    }

    private static func validateNoCycle(_ container: Container) throws {
        try ContainmentValidator.validateNoCycle(
            moving: container,
            proposedParent: container.parentContainer,
            id: \.objectID,
            parent: \.parentContainer
        )
    }

    private static func validatePrimaryPhoto(
        _ photo: PhotoAsset?,
        expectedOwner: NSManagedObject
    ) throws {
        guard let photo else { return }
        let matchesOwner = photo.thingOwner === expectedOwner
            || photo.containerOwner === expectedOwner
            || photo.areaOwner === expectedOwner
            || photo.placeOwner === expectedOwner
        guard matchesOwner else { throw DomainValidationError.crossPlaceRelationship }
    }
}
