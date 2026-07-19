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

struct AIAssistedThingFormState: Hashable, Sendable {
    private enum AnalysisStatus: Hashable, Sendable {
        case idle
        case analyzing(UUID)
        case succeeded
        case failed(String)
    }

    var values = ManagementFormValues()
    private var status: AnalysisStatus = .idle
    private var editedFields: Set<ManagementAIEditableField> = []
    private var aiAppliedName: String?
    private var aiAppliedKeywords: String?
    private var aiAppliedNotes: String?

    var isAnalyzing: Bool {
        guard case .analyzing = status else { return false }
        return true
    }

    var analysisSucceeded: Bool { status == .succeeded }

    var analysisError: String? {
        guard case .failed(let message) = status else { return nil }
        return message
    }

    var nameWasAISupplied: Bool {
        aiAppliedName.map { $0 == values.normalizedName } == true
    }

    mutating func markEdited(_ field: ManagementAIEditableField) {
        guard case .analyzing = status else { return }
        editedFields.insert(field)
    }

    mutating func beginAnalysis(discardingAppliedValues: Bool = false) -> UUID {
        if discardingAppliedValues {
            discardCurrentSuggestions()
        }
        let requestID = UUID()
        status = .analyzing(requestID)
        editedFields = []
        return requestID
    }

    @discardableResult
    mutating func apply(_ suggestion: ThingLabelSuggestion, requestID: UUID) -> Bool {
        guard case .analyzing(requestID) = status else { return false }

        if !editedFields.contains(.name), values.normalizedName.isEmpty {
            let name = suggestion.proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                values.name = name
                aiAppliedName = name
            }
        }
        if !editedFields.contains(.keywords), values.parsedKeywords.isEmpty {
            let keywords = ThingKeywordNormalizer.normalize(suggestion.keywords)
            if !keywords.isEmpty {
                values.keywords = keywords.joined(separator: ", ")
                aiAppliedKeywords = values.keywords
            }
        }
        if !editedFields.contains(.notes), values.normalizedNotes == nil,
           let detail = ManagementFormValues.optional(suggestion.detail ?? "")
        {
            values.notes = detail
            aiAppliedNotes = detail
        }
        status = .succeeded
        editedFields = []
        return true
    }

    @discardableResult
    mutating func fail(requestID: UUID, message: String) -> Bool {
        guard case .analyzing(requestID) = status else { return false }
        status = .failed(message)
        editedFields = []
        return true
    }

    mutating func cancel(requestID: UUID) {
        guard case .analyzing(requestID) = status else { return }
        invalidateAnalysis()
    }

    mutating func invalidateAnalysis() {
        status = .idle
        editedFields = []
    }

    mutating func discardCurrentSuggestions() {
        invalidateAnalysis()
        if let aiAppliedName, values.normalizedName == aiAppliedName {
            values.name = ""
        }
        if let aiAppliedKeywords,
           values.parsedKeywords.joined(separator: ", ") == aiAppliedKeywords
        {
            values.keywords = ""
        }
        if let aiAppliedNotes, values.normalizedNotes == aiAppliedNotes {
            values.notes = ""
        }
        aiAppliedName = nil
        aiAppliedKeywords = nil
        aiAppliedNotes = nil
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
