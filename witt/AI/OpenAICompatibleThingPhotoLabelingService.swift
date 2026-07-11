import Foundation

public struct OpenAICompatibleThingPhotoLabelingConfiguration: Hashable, Sendable {
    public let endpointURL: URL
    public let model: String
    public let timeout: TimeInterval
    public let maxPhotoSize: Int

    public init(
        endpointURL: URL,
        model: String,
        timeout: TimeInterval = 30,
        maxPhotoSize: Int = 8 * 1_024 * 1_024
    ) {
        self.endpointURL = endpointURL
        self.model = model
        self.timeout = timeout
        self.maxPhotoSize = maxPhotoSize
    }
}

public final class OpenAICompatibleThingPhotoLabelingService: ThingPhotoLabelingService, @unchecked Sendable {
    public typealias BearerTokenProvider = @Sendable () async throws -> String?

    private static let maxOutputTokens = 300
    private static let systemPrompt = """
    Identify the single household item visible in the photo so a person can find it later. \
    Do not invent a brand, model, material, size, or other detail that is not visible. \
    Use a short practical name, concise search keywords, and an optional brief distinguishing detail.
    """

    private let configuration: OpenAICompatibleThingPhotoLabelingConfiguration
    private let bearerTokenProvider: BearerTokenProvider
    private let session: URLSession

    public init(
        configuration: OpenAICompatibleThingPhotoLabelingConfiguration,
        bearerTokenProvider: @escaping BearerTokenProvider = { nil },
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.bearerTokenProvider = bearerTokenProvider
        self.session = session
    }

    public func suggestLabel(for photo: PhotoInput) async throws -> ThingLabelSuggestion {
        try validate(photo)

        let token: String?
        do {
            token = try await bearerTokenProvider()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ThingPhotoLabelingError.serviceUnavailable
        }

        let request = try makeRequest(for: photo, bearerToken: token)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled, Task.isCancelled {
                throw CancellationError()
            }
            throw map(error)
        } catch {
            throw ThingPhotoLabelingError.connectionUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ThingPhotoLabelingError.invalidResponse
        }
        try validate(statusCode: httpResponse.statusCode)
        return try parseResponse(data)
    }

    func makeRequest(for photo: PhotoInput, bearerToken token: String?) throws -> URLRequest {
        var request = URLRequest(url: configuration.endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            guard token.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0)
            }) else {
                throw ThingPhotoLabelingError.serviceUnavailable
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try makeRequestBody(for: photo)
        return request
    }

    private func validate(_ photo: PhotoInput) throws {
        guard Self.isAllowedEndpoint(configuration.endpointURL),
              !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              configuration.timeout > 0,
              configuration.maxPhotoSize > 0 else {
            throw ThingPhotoLabelingError.serviceUnavailable
        }

        let contentType = photo.contentType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard contentType == "image/jpeg" || contentType == "image/jpg" else {
            throw ThingPhotoLabelingError.unsupportedContentType
        }
        guard photo.data.count >= 3,
              photo.data[photo.data.startIndex] == 0xFF,
              photo.data[photo.data.startIndex + 1] == 0xD8,
              photo.data[photo.data.startIndex + 2] == 0xFF,
              photo.dimensions.map({ $0.width > 0 && $0.height > 0 }) ?? true else {
            throw ThingPhotoLabelingError.invalidPhoto
        }
        guard photo.data.count <= configuration.maxPhotoSize else {
            throw ThingPhotoLabelingError.photoTooLarge
        }
    }

    private func makeRequestBody(for photo: PhotoInput) throws -> Data {
        let imageURL = "data:image/jpeg;base64,\(photo.data.base64EncodedString())"
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "proposed_name": ["type": "string", "minLength": 1],
                "keywords": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "detail": ["type": ["string", "null"]],
                "confidence": [
                    "type": ["number", "null"],
                    "minimum": 0,
                    "maximum": 1
                ]
            ],
            "required": ["proposed_name", "keywords", "detail", "confidence"],
            "additionalProperties": false
        ]
        let body: [String: Any] = [
            "model": configuration.model.trimmingCharacters(in: .whitespacesAndNewlines),
            "store": false,
            "max_output_tokens": Self.maxOutputTokens,
            "input": [
                [
                    "role": "system",
                    "content": [["type": "input_text", "text": Self.systemPrompt]]
                ],
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": "Label this one household item for later search."],
                        ["type": "input_image", "image_url": imageURL]
                    ]
                ]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "thing_photo_label",
                    "strict": true,
                    "schema": schema
                ]
            ]
        ]

        do {
            return try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw ThingPhotoLabelingError.serviceUnavailable
        }
    }

    private func validate(statusCode: Int) throws {
        switch statusCode {
        case 200...299:
            return
        case 401:
            throw ThingPhotoLabelingError.unauthorized
        case 403:
            throw ThingPhotoLabelingError.forbidden
        case 408:
            throw ThingPhotoLabelingError.timedOut
        case 429:
            throw ThingPhotoLabelingError.rateLimited
        case 500...599:
            throw ThingPhotoLabelingError.serverError
        default:
            throw ThingPhotoLabelingError.unexpectedStatusCode(statusCode)
        }
    }

    private func parseResponse(_ data: Data) throws -> ThingLabelSuggestion {
        let response: ResponsesEnvelope
        do {
            response = try JSONDecoder().decode(ResponsesEnvelope.self, from: data)
        } catch {
            throw ThingPhotoLabelingError.malformedResponse
        }

        if let status = response.status, status != "completed" {
            switch status {
            case "incomplete", "in_progress", "queued":
                throw ThingPhotoLabelingError.incompleteResponse
            case "failed", "cancelled":
                throw ThingPhotoLabelingError.serviceUnavailable
            default:
                throw ThingPhotoLabelingError.malformedResponse
            }
        }

        let contents = (response.output ?? []).flatMap { $0.content ?? [] }
        if contents.contains(where: { $0.type == "refusal" || $0.refusal != nil }) {
            throw ThingPhotoLabelingError.refused
        }
        guard let outputText = contents.first(where: { $0.type == "output_text" })?.text else {
            throw ThingPhotoLabelingError.missingOutput
        }

        let structured: StructuredSuggestion
        do {
            structured = try JSONDecoder().decode(StructuredSuggestion.self, from: Data(outputText.utf8))
        } catch {
            throw ThingPhotoLabelingError.malformedStructuredOutput
        }

        let proposedName = Self.normalizedWhitespace(structured.proposedName)
        guard !proposedName.isEmpty else {
            throw ThingPhotoLabelingError.emptyName
        }
        if let confidence = structured.confidence,
           !confidence.isFinite || !(0...1).contains(confidence) {
            throw ThingPhotoLabelingError.invalidConfidence
        }

        let detail = structured.detail.map(Self.normalizedWhitespace).flatMap { $0.isEmpty ? nil : $0 }
        return ThingLabelSuggestion(
            proposedName: proposedName,
            keywords: ThingKeywordNormalizer.normalize(structured.keywords),
            detail: detail,
            confidence: structured.confidence
        )
    }

    private func map(_ error: URLError) -> ThingPhotoLabelingError {
        switch error.code {
        case .timedOut:
            return .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff,
             .dataNotAllowed, .secureConnectionFailed:
            return .connectionUnavailable
        default:
            return .connectionUnavailable
        }
    }

    nonisolated static func isAllowedEndpoint(_ url: URL) -> Bool {
        guard
            let scheme = url.scheme?.lowercased(),
            url.host != nil,
            url.user == nil,
            url.password == nil,
            url.fragment == nil
        else {
            return false
        }
        if scheme == "https" {
            return true
        }
        guard scheme == "http", let host = url.host?.lowercased() else {
            return false
        }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    nonisolated private static func normalizedWhitespace(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

private struct ResponsesEnvelope: Decodable {
    let status: String?
    let output: [ResponsesOutput]?
}

private struct ResponsesOutput: Decodable {
    let content: [ResponsesContent]?
}

private struct ResponsesContent: Decodable {
    let type: String?
    let text: String?
    let refusal: String?
}

private struct StructuredSuggestion: Decodable {
    let proposedName: String
    let keywords: [String]
    let detail: String?
    let confidence: Double?

    enum CodingKeys: String, CodingKey {
        case proposedName = "proposed_name"
        case keywords
        case detail
        case confidence
    }
}
