import Foundation

public enum DomainValidationError: Error, Equatable, Sendable {
    case missingPlace
    case missingParent
    case multipleParents
    case missingTarget
    case multipleTargets
    case targetOnUnboundQRCode
    case missingOwner
    case multipleOwners
    case crossPlaceRelationship
    case containerCycle
}

public struct PlaceOwnedReference: Equatable, Sendable {
    public let id: UUID
    public let placeID: UUID

    public init(id: UUID, placeID: UUID) {
        self.id = id
        self.placeID = placeID
    }
}

public enum ThingHome: Equatable, Sendable {
    case room(PlaceOwnedReference)
    case area(PlaceOwnedReference)
    case container(PlaceOwnedReference)
}

public enum ContainerParent: Equatable, Sendable {
    case room(PlaceOwnedReference)
    case area(PlaceOwnedReference)
    case container(PlaceOwnedReference)

    public var reference: PlaceOwnedReference {
        switch self {
        case .room(let reference), .area(let reference), .container(let reference):
            reference
        }
    }
}

public enum QRCodeTarget: Equatable, Sendable {
    case area(PlaceOwnedReference)
    case container(PlaceOwnedReference)

    public var reference: PlaceOwnedReference {
        switch self {
        case .area(let reference), .container(let reference):
            reference
        }
    }
}

public enum PhotoOwner: Equatable, Sendable {
    case place(UUID)
    case area(PlaceOwnedReference)
    case container(PlaceOwnedReference)
    case thing(PlaceOwnedReference)

    public var placeID: UUID {
        switch self {
        case .place(let placeID):
            placeID
        case .area(let reference), .container(let reference), .thing(let reference):
            reference.placeID
        }
    }
}

public enum ContainmentValidator {
    public static func validateThing(
        placeID: UUID?,
        homes: [ThingHome]
    ) throws {
        let placeID = try required(placeID)
        try requireExactlyOne(homes, missing: .missingParent, multiple: .multipleParents)

        let homePlaceID: UUID
        switch homes[0] {
        case .room(let reference), .area(let reference), .container(let reference):
            homePlaceID = reference.placeID
        }
        try requireSamePlace(placeID, homePlaceID)
    }

    public static func validateContainer(
        placeID: UUID?,
        parents: [ContainerParent]
    ) throws {
        let placeID = try required(placeID)
        try requireExactlyOne(parents, missing: .missingParent, multiple: .multipleParents)
        try requireSamePlace(placeID, parents[0].reference.placeID)
    }

    public static func validateQRCode(
        placeID: UUID?,
        targets: [QRCodeTarget],
        isBound: Bool
    ) throws {
        if isBound {
            let placeID = try required(placeID)
            try requireExactlyOne(targets, missing: .missingTarget, multiple: .multipleTargets)
            try requireSamePlace(placeID, targets[0].reference.placeID)
        } else if !targets.isEmpty {
            throw DomainValidationError.targetOnUnboundQRCode
        }
    }

    public static func validatePhoto(
        placeID: UUID?,
        owners: [PhotoOwner]
    ) throws {
        let placeID = try required(placeID)
        try requireExactlyOne(owners, missing: .missingOwner, multiple: .multipleOwners)
        try requireSamePlace(placeID, owners[0].placeID)
    }

    public static func validatePlaceOwnership(
        childPlaceID: UUID?,
        parentPlaceID: UUID?
    ) throws {
        let childPlaceID = try required(childPlaceID)
        let parentPlaceID = try required(parentPlaceID)
        try requireSamePlace(childPlaceID, parentPlaceID)
    }

    public static func validateNoContainerCycle(
        movingContainerID: UUID,
        proposedParentID: UUID?,
        parentByContainerID: [UUID: UUID?]
    ) throws {
        var visited = Set<UUID>()
        var current = proposedParentID

        while let containerID = current {
            guard containerID != movingContainerID, visited.insert(containerID).inserted else {
                throw DomainValidationError.containerCycle
            }
            current = parentByContainerID[containerID] ?? nil
        }
    }

    private static func required(_ placeID: UUID?) throws -> UUID {
        guard let placeID else { throw DomainValidationError.missingPlace }
        return placeID
    }

    private static func requireExactlyOne<T>(
        _ values: [T],
        missing: DomainValidationError,
        multiple: DomainValidationError
    ) throws {
        guard !values.isEmpty else { throw missing }
        guard values.count == 1 else { throw multiple }
    }

    private static func requireSamePlace(_ lhs: UUID, _ rhs: UUID) throws {
        guard lhs == rhs else { throw DomainValidationError.crossPlaceRelationship }
    }
}
