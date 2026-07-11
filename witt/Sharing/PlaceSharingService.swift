import CloudKit
import CoreData
import Foundation

nonisolated public struct PlaceShare: @unchecked Sendable {
    public let share: CKShare
    public let container: CKContainer

    public init(share: CKShare, container: CKContainer) {
        self.share = share
        self.container = container
    }
}

nonisolated public struct PlaceSharingState: Equatable, Sendable {
    public enum Role: Equatable, Sendable {
        case notShared
        case owner
        case administrator
        case participant
        case unknown
    }

    public enum Permission: Equatable, Sendable {
        case none
        case readOnly
        case readWrite
        case unknown
    }

    public struct Participant: Equatable, Sendable {
        public let name: String?
        public let role: Role
        public let permission: Permission
        public let hasAccepted: Bool
    }

    public let role: Role
    public let permission: Permission
    public let publicPermission: Permission
    public let participants: [Participant]

    public init(
        role: Role,
        permission: Permission,
        publicPermission: Permission,
        participants: [Participant]
    ) {
        self.role = role
        self.permission = permission
        self.publicPermission = publicPermission
        self.participants = participants
    }

    public static let notShared = PlaceSharingState(
        role: .notShared,
        permission: .none,
        publicPermission: .none,
        participants: []
    )

    init(share: CKShare) {
        let currentUser = share.currentUserParticipant
        role = Self.role(for: currentUser?.role)
        permission = Self.permission(for: currentUser?.permission)
        publicPermission = Self.permission(for: share.publicPermission)
        participants = share.participants.map { participant in
            Participant(
                name: PersonNameComponentsFormatter.localizedString(
                    from: participant.userIdentity.nameComponents ?? PersonNameComponents(),
                    style: .default,
                    options: []
                ).nilIfEmpty,
                role: Self.role(for: participant.role),
                permission: Self.permission(for: participant.permission),
                hasAccepted: participant.acceptanceStatus == .accepted
            )
        }
    }

    static func role(for role: CKShare.ParticipantRole?) -> Role {
        switch role {
        case .owner:
            .owner
        case .administrator:
            .administrator
        case .privateUser, .publicUser:
            .participant
        case .unknown, nil:
            .unknown
        @unknown default:
            .unknown
        }
    }

    static func permission(for permission: CKShare.ParticipantPermission?) -> Permission {
        switch permission {
        case .some(.none):
            .none
        case .readOnly:
            .readOnly
        case .readWrite:
            .readWrite
        case .unknown, nil:
            .unknown
        @unknown default:
            .unknown
        }
    }
}

nonisolated public final class PlaceSharingService {
    public nonisolated static let cloudKitContainerIdentifier = "iCloud.in.sids.witt"

    public let persistentContainer: NSPersistentCloudKitContainer
    public let containerIdentifier: String

    public init(
        persistentContainer: NSPersistentCloudKitContainer,
        containerIdentifier: String = PlaceSharingService.cloudKitContainerIdentifier
    ) {
        self.persistentContainer = persistentContainer
        self.containerIdentifier = containerIdentifier
    }

    @MainActor
    public func fetchShare(for place: Place) throws -> PlaceShare? {
        try requireCloudKitStores()
        guard !place.objectID.isTemporaryID else {
            throw PlaceSharingError.placeNotSaved
        }

        let shares = try persistentContainer.fetchShares(matching: [place.objectID])
        guard let share = shares[place.objectID] else { return nil }
        return PlaceShare(share: share, container: try cloudKitContainer())
    }

    @MainActor
    public func createShare(for place: Place) async throws -> PlaceShare {
        let privateStore = try requireStore(scope: .private)
        _ = try requireStore(scope: .shared)
        try validateForSharing(place, privateStore: privateStore)

        if try fetchShare(for: place) != nil {
            throw PlaceSharingError.alreadyShared
        }

        do {
            let result = try await share([place], to: nil)
            result.share[CKShare.SystemFieldKey.title] = shareTitle(for: place) as CKRecordValue
            result.share.publicPermission = .none
            return result
        } catch {
            throw map(error, invitation: false)
        }
    }

    @MainActor
    public func fetchOrCreateShare(for place: Place) async throws -> PlaceShare {
        if let existing = try fetchShare(for: place) {
            return existing
        }
        return try await createShare(for: place)
    }

    @MainActor
    public func state(for place: Place) throws -> PlaceSharingState {
        guard let placeShare = try fetchShare(for: place) else {
            return .notShared
        }
        return PlaceSharingState(share: placeShare.share)
    }

    @discardableResult
    @MainActor
    public func accept(_ metadata: CKShare.Metadata) async throws -> [CKShare.Metadata] {
        guard metadata.containerIdentifier == containerIdentifier else {
            throw PlaceSharingError.invitationFailure(
                "The invitation belongs to a different iCloud container."
            )
        }
        let sharedStore = try requireStore(scope: .shared)

        do {
            return try await withCheckedThrowingContinuation { continuation in
                persistentContainer.acceptShareInvitations(
                    from: [metadata],
                    into: sharedStore
                ) { acceptedMetadata, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let acceptedMetadata {
                        continuation.resume(returning: acceptedMetadata)
                    } else {
                        continuation.resume(
                            throwing: PlaceSharingError.invitationFailure(
                                "CloudKit did not return an accepted invitation."
                            )
                        )
                    }
                }
            }
        } catch {
            throw map(error, invitation: true)
        }
    }

    @MainActor
    public func cloudKitContainer() throws -> CKContainer {
        try requireCloudKitStores()
        return CKContainer(identifier: containerIdentifier)
    }

    @MainActor
    func shareTitle(for place: Place) -> String {
        let name = place.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "WITT Place" : "WITT: \(name)"
    }

    @MainActor
    func requireStore(scope: CKDatabase.Scope) throws -> NSPersistentStore {
        guard PlaceSharingStoreLocator.hasCloudKitConfiguration(in: persistentContainer) else {
            throw PlaceSharingError.cloudKitDisabled
        }
        guard let store = PlaceSharingStoreLocator.store(scope: scope, in: persistentContainer) else {
            throw scope == .shared
                ? PlaceSharingError.sharedStoreUnavailable
                : PlaceSharingError.privateStoreUnavailable
        }
        return store
    }

    @MainActor
    private func requireCloudKitStores() throws {
        _ = try requireStore(scope: .private)
        _ = try requireStore(scope: .shared)
    }

    @MainActor
    private func validateForSharing(_ place: Place, privateStore: NSPersistentStore) throws {
        guard let context = place.managedObjectContext else {
            throw PlaceSharingError.placeNotSaved
        }
        guard !place.objectID.isTemporaryID else {
            throw PlaceSharingError.placeNotSaved
        }
        guard place.objectID.persistentStore === privateStore else {
            throw PlaceSharingError.permissionDenied
        }
        try PlaceGraphValidator.validate(place)

        if context.hasChanges {
            throw PlaceSharingError.unsavedChanges
        }
    }

    @MainActor
    private func share(
        _ objects: [NSManagedObject],
        to existingShare: CKShare?
    ) async throws -> PlaceShare {
        try await withCheckedThrowingContinuation { continuation in
            persistentContainer.share(objects, to: existingShare) { _, share, container, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let share, let container {
                    continuation.resume(returning: PlaceShare(share: share, container: container))
                } else {
                    continuation.resume(
                        throwing: PlaceSharingError.sharingFailure(
                            "CloudKit did not create a share."
                        )
                    )
                }
            }
        }
    }

    private func map(_ error: Error, invitation: Bool) -> PlaceSharingError {
        if let sharingError = error as? PlaceSharingError {
            return sharingError
        }
        guard let cloudKitError = error as? CKError else {
            return invitation
                ? .invitationFailure(error.localizedDescription)
                : .sharingFailure(error.localizedDescription)
        }

        switch cloudKitError.code {
        case .notAuthenticated, .accountTemporarilyUnavailable:
            return .cloudKitDisabled
        case .permissionFailure:
            return .permissionDenied
        case .alreadyShared:
            return .alreadyShared
        default:
            return invitation
                ? .invitationFailure(cloudKitError.localizedDescription)
                : .sharingFailure(cloudKitError.localizedDescription)
        }
    }
}

nonisolated enum PlaceSharingStoreLocator {
    static func hasCloudKitConfiguration(
        in container: NSPersistentCloudKitContainer
    ) -> Bool {
        container.persistentStoreDescriptions.contains {
            $0.cloudKitContainerOptions != nil
        }
    }

    static func store(
        scope: CKDatabase.Scope,
        in container: NSPersistentCloudKitContainer
    ) -> NSPersistentStore? {
        let coordinator = container.persistentStoreCoordinator
        guard let url = description(
            scope: scope,
            among: container.persistentStoreDescriptions
        )?.url else {
            return nil
        }
        return coordinator.persistentStore(for: url)
    }

    static func description(
        scope: CKDatabase.Scope,
        among descriptions: [NSPersistentStoreDescription]
    ) -> NSPersistentStoreDescription? {
        descriptions.first {
            $0.cloudKitContainerOptions?.databaseScope == scope
        }
    }
}

nonisolated enum PlaceGraphValidator {
    static func validate(_ place: Place) throws {
        var visited = Set<NSManagedObjectID>()
        var pending: [NSManagedObject] = [place]

        while let object = pending.popLast() {
            guard visited.insert(object.objectID).inserted else { continue }

            if object !== place {
                guard object.entity.relationshipsByName["place"] != nil else {
                    throw PlaceSharingError.unsupportedGraphObject(
                        object.entity.name ?? "Unknown"
                    )
                }
                guard let objectPlace = object.value(forKey: "place") as? Place else {
                    throw PlaceSharingError.graphObjectMissingPlace(
                        object.entity.name ?? "Unknown"
                    )
                }
                guard objectPlace === place else {
                    throw PlaceSharingError.graphContainsDifferentPlace(
                        object.entity.name ?? "Unknown"
                    )
                }
            }

            for relationship in object.entity.relationshipsByName.values {
                guard let value = object.value(forKey: relationship.name) else { continue }
                if relationship.isToMany {
                    if let objects = value as? Set<NSManagedObject> {
                        pending.append(contentsOf: objects)
                    } else if let objects = value as? NSSet {
                        pending.append(contentsOf: objects.compactMap { $0 as? NSManagedObject })
                    }
                } else if let relatedObject = value as? NSManagedObject {
                    pending.append(relatedObject)
                }
            }
        }
    }
}

nonisolated public enum PlaceSharingError: Error, Equatable, LocalizedError, Sendable {
    case cloudKitDisabled
    case privateStoreUnavailable
    case sharedStoreUnavailable
    case alreadyShared
    case permissionDenied
    case placeNotSaved
    case unsavedChanges
    case graphObjectMissingPlace(String)
    case graphContainsDifferentPlace(String)
    case unsupportedGraphObject(String)
    case sharingFailure(String)
    case invitationFailure(String)

    public var errorDescription: String? {
        switch self {
        case .cloudKitDisabled:
            "iCloud sharing is unavailable. Sign in to iCloud and enable iCloud for WITT."
        case .privateStoreUnavailable:
            "WITT's private iCloud store is unavailable."
        case .sharedStoreUnavailable:
            "WITT's shared iCloud store is unavailable."
        case .alreadyShared:
            "This Place is already shared."
        case .permissionDenied:
            "You do not have permission to share this Place."
        case .placeNotSaved:
            "Save this Place before sharing it."
        case .unsavedChanges:
            "Save all changes in this Place before sharing it."
        case .graphObjectMissingPlace(let entity):
            "A \(entity) in this Place is missing its Place relationship."
        case .graphContainsDifferentPlace(let entity):
            "A \(entity) relationship crosses into a different Place."
        case .unsupportedGraphObject(let entity):
            "The Place contains an unsupported related object: \(entity)."
        case .sharingFailure(let message):
            "CloudKit could not share this Place: \(message)"
        case .invitationFailure(let message):
            "CloudKit could not accept the invitation: \(message)"
        }
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
