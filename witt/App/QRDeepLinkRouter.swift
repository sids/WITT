import Foundation

enum QRDeepLinkDestination: Sendable {
    case addThing
    case attach(QRToken)
    case needsRepair
    case conflict
}

struct QRDeepLinkRouter: Sendable {
    private let resolver: any QRCodeResolving

    init(resolver: any QRCodeResolving) {
        self.resolver = resolver
    }

    func destination(for url: URL) async throws -> QRDeepLinkDestination {
        let qrURL = try WITTQRCodeURL(url: url)

        switch try await resolver.resolve(qrURL.token) {
        case .knownArea, .knownContainer:
            return .addThing
        case .unknown:
            return .attach(qrURL.token)
        case .needsRepair:
            return .needsRepair
        case .conflict:
            return .conflict
        }
    }
}
