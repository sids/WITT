import Foundation

public struct QRTargetID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public enum QRBindingTarget: Hashable, Sendable, Codable {
    case area(QRTargetID)
    case container(QRTargetID)
}

public struct QRCodeBindingRequest: Hashable, Sendable, Codable {
    public let token: QRToken
    public let target: QRBindingTarget

    public init(token: QRToken, target: QRBindingTarget) {
        self.token = token
        self.target = target
    }
}

public struct QRCodeBinding: Hashable, Sendable, Codable {
    public let token: QRToken
    public let target: QRBindingTarget

    public init(token: QRToken, target: QRBindingTarget) {
        self.token = token
        self.target = target
    }
}

public enum QRCodeRepairReason: Hashable, Sendable, Codable {
    case missingTarget
    case unsupportedTargetKind
    case invalidStoredToken
    case duplicateBindings
}

public struct QRCodeRepair: Hashable, Sendable, Codable {
    public let reason: QRCodeRepairReason
    public let bindingID: UUID?

    public init(reason: QRCodeRepairReason, bindingID: UUID? = nil) {
        self.reason = reason
        self.bindingID = bindingID
    }
}

public struct QRCodeConflict: Hashable, Sendable, Codable {
    public let firstTarget: QRBindingTarget
    public let secondTarget: QRBindingTarget
    public let additionalTargets: [QRBindingTarget]

    public init(
        firstTarget: QRBindingTarget,
        secondTarget: QRBindingTarget,
        additionalTargets: [QRBindingTarget] = []
    ) {
        self.firstTarget = firstTarget
        self.secondTarget = secondTarget
        self.additionalTargets = additionalTargets
    }

    public var targets: [QRBindingTarget] {
        [firstTarget, secondTarget] + additionalTargets
    }
}

public enum QRCodeResolution: Hashable, Sendable, Codable {
    case knownArea(QRTargetID)
    case knownContainer(QRTargetID)
    case unknown
    case needsRepair(QRCodeRepair)
    case conflict(QRCodeConflict)
}

public enum QRCodeRepairIssue: Hashable, Sendable {
    case unavailable(QRCodeRepair)
    case conflict(QRCodeConflict)
}

public struct QRCodeRepairRoute: Hashable, Sendable {
    public let token: QRToken
    public let issue: QRCodeRepairIssue

    public init(token: QRToken, issue: QRCodeRepairIssue) {
        self.token = token
        self.issue = issue
    }
}

public protocol QRCodeResolving: Sendable {
    func resolve(_ token: QRToken) async throws -> QRCodeResolution
}
