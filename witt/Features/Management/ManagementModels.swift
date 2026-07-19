import Foundation

enum ManagementRoute: Identifiable, Hashable {
    case createPlace
    case createRoom(placeID: UUID?)
    case createArea(roomID: UUID?)
    case createContainer(destination: ContainerDestination?)
    case createThing(destination: ThingDestination?)
    case editPlace(UUID)
    case editRoom(UUID)
    case editArea(UUID)
    case editContainer(UUID)
    case editThing(UUID)

    var id: Self { self }
}

enum ThingPostSaveAction: Hashable, Sendable {
    case addAnotherHere
    case scanNext
    case viewThing
    case done
}

enum ThingPostSaveHandoff: Equatable, Sendable {
    case scanNext
    case viewThing(UUID)
    case done

    init?(action: ThingPostSaveAction, thingID: UUID) {
        switch action {
        case .addAnotherHere:
            return nil
        case .scanNext:
            self = .scanNext
        case .viewThing:
            self = .viewThing(thingID)
        case .done:
            self = .done
        }
    }
}

struct ThingPostSaveDismissalState: Equatable, Sendable {
    private(set) var pendingHandoff: ThingPostSaveHandoff?

    mutating func begin(_ handoff: ThingPostSaveHandoff) {
        pendingHandoff = handoff
    }

    mutating func finish() -> ThingPostSaveHandoff? {
        defer { pendingHandoff = nil }
        return pendingHandoff
    }
}

extension ThingDestination {
    init(home: ThingSnapshotHome) {
        switch home {
        case .room(let id):
            self = .room(id)
        case .area(let id):
            self = .area(id)
        case .container(let id):
            self = .container(id)
        }
    }
}

extension ContainerDestination {
    init(parent: ContainerSnapshotParent) {
        switch parent {
        case .room(let id):
            self = .room(id)
        case .area(let id):
            self = .area(id)
        case .container(let id):
            self = .container(id)
        }
    }
}

enum ManagementPhotoSelection: Hashable, Sendable {
    case unchanged
    case replacement(NormalizedPhoto)
    case removed

    var createPhoto: NormalizedPhoto? {
        guard case .replacement(let photo) = self else { return nil }
        return photo
    }

    var updateMutation: PhotoMutation {
        switch self {
        case .unchanged: .unchanged
        case .replacement(let photo): .replace(photo)
        case .removed: .remove
        }
    }
}

struct ManagementFormValues: Hashable, Sendable {
    var name = ""
    var notes = ""
    var detail = ""
    var keywords = ""

    var normalizedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var normalizedNotes: String? { Self.optional(notes) }
    var normalizedDetail: String? { Self.optional(detail) }
    var parsedKeywords: [String] {
        keywords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func optional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum ManagementPreselection {
    static func place(context: UUID?, places: [PlaceSnapshot]) -> UUID? {
        if let context, places.contains(where: { $0.id == context }) { return context }
        return places.first?.id
    }

    static func room(context: UUID?, rooms: [RoomSnapshot]) -> UUID? {
        if let context, rooms.contains(where: { $0.id == context }) { return context }
        return rooms.first?.id
    }

    static func containerDestination(
        context: ContainerDestination?,
        options: [ContainerParentOption]
    ) -> ContainerDestination? {
        if let context, options.contains(where: { $0.destination == context }) { return context }
        return options.first?.destination
    }

    static func thingDestination(
        context: ThingDestination?,
        options: [ThingDestinationOption]
    ) -> ThingDestination? {
        if let context, options.contains(where: { $0.destination == context }) { return context }
        return options.first?.destination
    }
}

nonisolated enum ManagementAIEditableField: Hashable, Sendable {
    case name
    case keywords
    case notes
}

struct ManagementAISuggestionApplication: Hashable, Sendable {
    let values: ManagementFormValues
    let suppliedName: Bool
    let suppliedKeywords: Bool
    let suppliedNotes: Bool

    static func apply(
        _ suggestion: ThingLabelSuggestion,
        to currentValues: ManagementFormValues,
        preserving editedFields: Set<ManagementAIEditableField> = []
    ) -> Self {
        var values = currentValues
        var suppliedName = false
        var suppliedKeywords = false
        var suppliedNotes = false

        if !editedFields.contains(.name), values.normalizedName.isEmpty {
            let proposedName = suggestion.proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !proposedName.isEmpty {
                values.name = proposedName
                suppliedName = true
            }
        }

        if !editedFields.contains(.keywords), values.parsedKeywords.isEmpty {
            let keywords = ThingKeywordNormalizer.normalize(suggestion.keywords)
            if !keywords.isEmpty {
                values.keywords = keywords.joined(separator: ", ")
                suppliedKeywords = true
            }
        }

        if !editedFields.contains(.notes), values.normalizedNotes == nil,
            let detail = ManagementFormValues.optional(suggestion.detail ?? "")
        {
            values.notes = detail
            suppliedNotes = true
        }

        return Self(
            values: values,
            suppliedName: suppliedName,
            suppliedKeywords: suppliedKeywords,
            suppliedNotes: suppliedNotes
        )
    }
}

struct ManagementArchiveFacts: Hashable, Sendable {
    let roomCount: Int
    let storageAreaCount: Int
    let containerCount: Int
    let thingCount: Int
    let containsBoundQRCode: Bool

    init(_ impact: ArchiveImpactSummary, roomCount: Int = 0) {
        self.roomCount = roomCount
        storageAreaCount = impact.storageAreaCount
        containerCount = impact.containerCount
        thingCount = impact.thingCount
        containsBoundQRCode = impact.containsBoundQRCode
    }

    var message: String {
        var facts: [String] = []
        if roomCount > 0 { facts.append(Self.count(roomCount, singular: "Room")) }
        if storageAreaCount > 0 { facts.append(Self.count(storageAreaCount, singular: "Storage Area")) }
        if containerCount > 0 { facts.append(Self.count(containerCount, singular: "Container")) }
        if thingCount > 0 { facts.append(Self.count(thingCount, singular: "Thing")) }

        var sentences: [String] = []
        if facts.isEmpty {
            sentences.append("This removes it from the active catalog while preserving its record.")
        } else {
            sentences.append("\(Self.list(facts)) will also be archived.")
        }
        if containsBoundQRCode {
            sentences.append("One or more QR codes will need attention before they can be reused.")
        }
        return sentences.joined(separator: " ")
    }

    private static func count(_ value: Int, singular: String) -> String {
        "\(value) \(singular)\(value == 1 ? "" : "s")"
    }

    private static func list(_ values: [String]) -> String {
        switch values.count {
        case 0:
            return ""
        case 1:
            return values[0]
        case 2:
            return values.joined(separator: " and ")
        default:
            guard let last = values.last else { return "" }
            return values.dropLast().joined(separator: ", ") + ", and " + last
        }
    }
}
