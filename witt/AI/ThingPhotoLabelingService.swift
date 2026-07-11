import Foundation

public protocol ThingPhotoLabelingService: Sendable {
    func suggestLabel(for photo: PhotoInput) async throws -> ThingLabelSuggestion
}

public struct PhotoInput: Hashable, Sendable {
    public let data: Data
    public let contentType: String
    public let dimensions: Dimensions?

    public init(data: Data, contentType: String, dimensions: Dimensions? = nil) {
        self.data = data
        self.contentType = contentType
        self.dimensions = dimensions
    }

    public struct Dimensions: Hashable, Sendable {
        public let width: Int
        public let height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }
}

public struct ThingLabelSuggestion: Hashable, Sendable {
    public let proposedName: String
    public let keywords: [String]
    public let detail: String?
    public let confidence: Double?

    public init(
        proposedName: String,
        keywords: [String] = [],
        detail: String? = nil,
        confidence: Double? = nil
    ) {
        self.proposedName = proposedName
        self.keywords = keywords
        self.detail = detail
        self.confidence = confidence
    }
}

public enum ThingPhotoLabelingError: Error, Equatable, LocalizedError, Sendable {
    case invalidPhoto
    case unsupportedContentType
    case photoTooLarge
    case serviceUnavailable
    case connectionUnavailable
    case unauthorized
    case forbidden
    case rateLimited
    case timedOut
    case serverError
    case unexpectedStatusCode(Int)
    case incompleteResponse
    case refused
    case missingOutput
    case malformedResponse
    case malformedStructuredOutput
    case emptyName
    case invalidConfidence
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidPhoto:
            return "This photo could not be read."
        case .unsupportedContentType:
            return "Only JPEG photos can be labeled."
        case .photoTooLarge:
            return "This photo is too large to label."
        case .serviceUnavailable:
            return "Photo labeling is not available right now."
        case .connectionUnavailable:
            return "Could not connect to photo labeling."
        case .unauthorized, .forbidden:
            return "Photo labeling is not configured correctly."
        case .rateLimited:
            return "Photo labeling is busy. Please try again shortly."
        case .timedOut:
            return "Photo labeling took too long. Please try again."
        case .serverError:
            return "Photo labeling is temporarily unavailable."
        case .unexpectedStatusCode:
            return "Photo labeling returned an unexpected result."
        case .incompleteResponse:
            return "Photo labeling did not finish. Please try again."
        case .refused:
            return "This photo could not be labeled."
        case .missingOutput, .malformedResponse, .malformedStructuredOutput,
             .emptyName, .invalidConfidence, .invalidResponse:
            return "Photo labeling returned an invalid result."
        }
    }
}

public enum ThingKeywordNormalizer {
    public static func normalize(_ keywords: some Sequence<String>) -> [String] {
        var seen = Set<String>()

        return keywords.compactMap { keyword in
            let normalized = keyword
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")

            guard !normalized.isEmpty else {
                return nil
            }

            let comparisonKey = normalized.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            guard seen.insert(comparisonKey).inserted else {
                return nil
            }

            return normalized
        }
    }
}
