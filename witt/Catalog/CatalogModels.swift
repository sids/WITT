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

public enum ContainerDestination: Hashable, Sendable {
    case room(UUID)
    case area(UUID)
    case container(UUID)
}

public enum PhotoMutation: Hashable, Sendable {
    case unchanged
    case replace(NormalizedPhoto)
    case remove
}

public struct CreatePlaceDraft: Hashable, Sendable {
    public let name: String
    public let notes: String?
    public let photo: NormalizedPhoto?

    public init(name: String, notes: String? = nil, photo: NormalizedPhoto? = nil) {
        self.name = name
        self.notes = notes
        self.photo = photo
    }
}

public struct UpdatePlaceDraft: Hashable, Sendable {
    public let name: String
    public let notes: String?
    public let photo: PhotoMutation

    public init(name: String, notes: String? = nil, photo: PhotoMutation = .unchanged) {
        self.name = name
        self.notes = notes
        self.photo = photo
    }
}

public struct CreateRoomDraft: Hashable, Sendable {
    public let placeID: UUID
    public let name: String

    public init(placeID: UUID, name: String) {
        self.placeID = placeID
        self.name = name
    }
}

public struct UpdateRoomDraft: Hashable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct CreateAreaDraft: Hashable, Sendable {
    public let roomID: UUID
    public let name: String
    public let detail: String?
    public let photo: NormalizedPhoto?
    public let qrToken: QRToken?

    public init(
        roomID: UUID,
        name: String,
        detail: String? = nil,
        photo: NormalizedPhoto? = nil,
        qrToken: QRToken? = nil
    ) {
        self.roomID = roomID
        self.name = name
        self.detail = detail
        self.photo = photo
        self.qrToken = qrToken
    }
}

public struct UpdateAreaDraft: Hashable, Sendable {
    public let name: String
    public let detail: String?
    public let roomID: UUID
    public let photo: PhotoMutation

    public init(
        name: String,
        detail: String? = nil,
        roomID: UUID,
        photo: PhotoMutation = .unchanged
    ) {
        self.name = name
        self.detail = detail
        self.roomID = roomID
        self.photo = photo
    }
}

public struct CreateContainerDraft: Hashable, Sendable {
    public let name: String
    public let detail: String?
    public let destination: ContainerDestination
    public let photo: NormalizedPhoto?
    public let qrToken: QRToken?

    public init(
        name: String,
        detail: String? = nil,
        destination: ContainerDestination,
        photo: NormalizedPhoto? = nil,
        qrToken: QRToken? = nil
    ) {
        self.name = name
        self.detail = detail
        self.destination = destination
        self.photo = photo
        self.qrToken = qrToken
    }
}

public struct UpdateContainerDraft: Hashable, Sendable {
    public let name: String
    public let detail: String?
    public let destination: ContainerDestination
    public let photo: PhotoMutation

    public init(
        name: String,
        detail: String? = nil,
        destination: ContainerDestination,
        photo: PhotoMutation = .unchanged
    ) {
        self.name = name
        self.detail = detail
        self.destination = destination
        self.photo = photo
    }
}

public struct UpdateThingDraft: Hashable, Sendable {
    public let name: String
    public let keywords: [String]
    public let notes: String?
    public let destination: ThingDestination
    public let photo: PhotoMutation

    public init(
        name: String,
        keywords: [String] = [],
        notes: String? = nil,
        destination: ThingDestination,
        photo: PhotoMutation = .unchanged
    ) {
        self.name = name
        self.keywords = keywords
        self.notes = notes
        self.destination = destination
        self.photo = photo
    }
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
    case qrCodeNotRepairable
    case selectionDoesNotBelongToParent
    case missingIdentity
    case invalidStoredHierarchy
    case placeNotFound
    case roomNotFound
    case areaNotFound
    case containerNotFound
    case thingNotFound
    case crossPlaceMove
    case containerCycle
    case invalidManagedObjectModel
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
        case .qrCodeNotRepairable:
            "This QR code does not have a repairable attachment."
        case .selectionDoesNotBelongToParent:
            "The selected Room, Storage Area, and Container do not belong together."
        case .missingIdentity:
            "Some catalog data is missing its identity."
        case .invalidStoredHierarchy:
            "Some catalog data has an invalid storage hierarchy."
        case .placeNotFound:
            "That Place is no longer available."
        case .roomNotFound:
            "That Room is no longer available."
        case .areaNotFound:
            "That Storage Area is no longer available."
        case .containerNotFound:
            "That Container is no longer available."
        case .thingNotFound:
            "That Thing is no longer available."
        case .crossPlaceMove:
            "Storage Areas, Containers, and Things can only be moved within the same Place."
        case .containerCycle:
            "A Container cannot be placed inside itself or one of its descendants."
        case .invalidManagedObjectModel:
            "WITT's catalog configuration is invalid. Update the app and try again."
        }
    }
}

public protocol CatalogRepository: QRCodeResolving {
    func fetchPlaces() async throws -> [PlaceSnapshot]
    @discardableResult func seedHomeIfNeeded() async throws -> PlaceSnapshot?
    func createPlace(_ draft: CreatePlaceDraft) async throws -> PlaceSnapshot
    func createRoom(_ draft: CreateRoomDraft) async throws -> RoomSnapshot
    func createArea(_ draft: CreateAreaDraft) async throws -> AreaSnapshot
    func createContainer(_ draft: CreateContainerDraft) async throws -> ContainerSnapshot
    func updatePlace(id: UUID, with draft: UpdatePlaceDraft) async throws -> PlaceSnapshot
    func updateRoom(id: UUID, with draft: UpdateRoomDraft) async throws -> RoomSnapshot
    func updateArea(id: UUID, with draft: UpdateAreaDraft) async throws -> AreaSnapshot
    func updateContainer(id: UUID, with draft: UpdateContainerDraft) async throws -> ContainerSnapshot
    func updateThing(id: UUID, with draft: UpdateThingDraft) async throws -> ThingSnapshot
    func archivePlace(id: UUID) async throws -> PlaceSnapshot
    func archiveRoom(id: UUID) async throws -> RoomSnapshot
    func archiveArea(id: UUID) async throws -> AreaSnapshot
    func archiveContainer(id: UUID) async throws -> ContainerSnapshot
    func archiveThing(id: UUID) async throws -> ThingSnapshot
    func saveThing(_ draft: ReviewedThingDraft, to destination: ThingDestination) async throws -> ThingSnapshot
    func unassignedQRCodeTargets() async throws -> [QRAttachTargetSnapshot]
    @discardableResult func bindQRCode(_ request: QRCodeBindingRequest) async throws -> QRCodeBinding
    @discardableResult func replaceQRCode(_ request: QRCodeBindingRequest) async throws -> QRCodeBinding
    @discardableResult func repairQRCode(
        _ request: QRCodeBindingRequest
    ) async throws -> QRCodeBinding
    @discardableResult func repairAndReplaceQRCode(
        _ request: QRCodeBindingRequest
    ) async throws -> QRCodeBinding
    func repairQRCodeTargetIsEligible(
        _ request: QRCodeBindingRequest
    ) async throws -> Bool
    func releaseRepairableQRCode(_ token: QRToken) async throws
    @discardableResult func createTargetAndBindQRCode(
        _ request: CreateAndBindQRCodeRequest
    ) async throws -> QRAttachTargetSnapshot
    @discardableResult func repairCreateTargetAndBindQRCode(
        _ request: CreateAndBindQRCodeRequest
    ) async throws -> QRAttachTargetSnapshot
}
