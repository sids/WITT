import Foundation

public struct PhotoAssetSnapshot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let data: Data?
    public let thumbnailData: Data?
    public let contentType: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let byteSize: Int
    public let capturedAt: Date?
}

public struct PlaceSnapshot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let notes: String?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let archivedAt: Date?
    public let primaryPhoto: PhotoAssetSnapshot?
    public let rooms: [RoomSnapshot]
    public let areas: [AreaSnapshot]
    public let containers: [ContainerSnapshot]
    public let things: [ThingSnapshot]
}

public struct RoomSnapshot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let placeID: UUID
    public let name: String
    public let sortOrder: Int
    public let archivedAt: Date?
}

public struct AreaSnapshot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let placeID: UUID
    public let roomID: UUID
    public let name: String
    public let detail: String?
    public let sortOrder: Int
    public let archivedAt: Date?
    public let primaryPhoto: PhotoAssetSnapshot?
    public let hasQRCode: Bool
}

public enum ContainerSnapshotParent: Hashable, Sendable {
    case room(UUID)
    case area(UUID)
    case container(UUID)
}

public struct ContainerSnapshot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let placeID: UUID
    public let name: String
    public let detail: String?
    public let sortOrder: Int
    public let archivedAt: Date?
    public let parent: ContainerSnapshotParent
    public let primaryPhoto: PhotoAssetSnapshot?
    public let hasQRCode: Bool
}

public enum ThingSnapshotHome: Hashable, Sendable {
    case room(UUID)
    case area(UUID)
    case container(UUID)
}

public struct ThingSnapshot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let placeID: UUID
    public let name: String
    public let keywords: [String]
    public let notes: String?
    public let nameSource: String
    public let home: ThingSnapshotHome
    public let createdAt: Date?
    public let updatedAt: Date?
    public let archivedAt: Date?
    public let primaryPhoto: PhotoAssetSnapshot?
}

public enum QRAttachTargetKind: String, Hashable, Sendable {
    case area
    case container
}

public struct QRAttachTargetSnapshot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let placeID: UUID
    public let kind: QRAttachTargetKind
    public let name: String
    public let locationComponents: [String]

    public var bindingTarget: QRBindingTarget {
        switch kind {
        case .area:
            .area(QRTargetID(rawValue: id))
        case .container:
            .container(QRTargetID(rawValue: id))
        }
    }
}

public enum RoomSelection: Hashable, Sendable {
    case existing(UUID)
    case new(name: String)
}

public enum AreaSelection: Hashable, Sendable {
    case existing(UUID)
    case new(name: String)
}

public enum QRCodeAttachmentSelection: Hashable, Sendable {
    case area
    case existingContainer(UUID)
    case newContainer(name: String)
}

public struct CreateAndBindQRCodeRequest: Hashable, Sendable {
    public let token: QRToken
    public let placeID: UUID
    public let room: RoomSelection
    public let area: AreaSelection
    public let attachment: QRCodeAttachmentSelection

    public init(
        token: QRToken,
        placeID: UUID,
        room: RoomSelection,
        area: AreaSelection,
        attachment: QRCodeAttachmentSelection
    ) {
        self.token = token
        self.placeID = placeID
        self.room = room
        self.area = area
        self.attachment = attachment
    }
}

public enum ThingDestination: Hashable, Sendable {
    case room(UUID)
    case area(UUID)
    case container(UUID)
}

public struct ReviewedThingDraft: Hashable, Sendable {
    public let name: String
    public let keywords: [String]
    public let notes: String?
    public let nameSource: String
    public let photo: NormalizedPhoto?

    public init(
        name: String,
        keywords: [String] = [],
        notes: String? = nil,
        nameSource: String = "user",
        photo: NormalizedPhoto? = nil
    ) {
        self.name = name
        self.keywords = keywords
        self.notes = notes
        self.nameSource = nameSource
        self.photo = photo
    }
}

public enum CatalogRepositoryError: Error, Equatable, Sendable {
    case persistenceNotLoaded
    case invalidDraft
    case destinationNotFound
    case targetNotFound
    case targetAlreadyHasQRCode
    case tokenAlreadyBound
    case selectionDoesNotBelongToParent
    case missingIdentity
    case invalidStoredHierarchy
}

extension CatalogRepositoryError: LocalizedError {
    nonisolated public var errorDescription: String? {
        switch self {
        case .persistenceNotLoaded:
            "WITT's catalog is still loading. Try again."
        case .invalidDraft:
            "Enter a valid name and details before saving."
        case .destinationNotFound:
            "That storage destination is no longer available."
        case .targetNotFound:
            "That Storage Area or Container is no longer available."
        case .targetAlreadyHasQRCode:
            "That Storage Area or Container already has a QR code."
        case .tokenAlreadyBound:
            "This QR code is already attached."
        case .selectionDoesNotBelongToParent:
            "The selected Room, Storage Area, and Container do not belong together."
        case .missingIdentity:
            "Some catalog data is missing its identity."
        case .invalidStoredHierarchy:
            "Some catalog data has an invalid storage hierarchy."
        }
    }
}

public protocol CatalogRepository: QRCodeResolving {
    func fetchPlaces() async throws -> [PlaceSnapshot]
    @discardableResult func seedHomeIfNeeded() async throws -> PlaceSnapshot?
    func saveThing(_ draft: ReviewedThingDraft, to destination: ThingDestination) async throws -> ThingSnapshot
    func unassignedQRCodeTargets() async throws -> [QRAttachTargetSnapshot]
    @discardableResult func bindQRCode(_ request: QRCodeBindingRequest) async throws -> QRCodeBinding
    @discardableResult func createTargetAndBindQRCode(
        _ request: CreateAndBindQRCodeRequest
    ) async throws -> QRAttachTargetSnapshot
}
