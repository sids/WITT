import Foundation

public struct ThingPhotoLabelingRelayConfiguration: Hashable, Sendable {
    public let endpointURL: URL
    public let timeout: TimeInterval
    public let maxPhotoSize: Int
    public let maxResponseSize: Int
    public let minimumCredentialValidity: TimeInterval
    public let maximumCredentialLifetime: TimeInterval

    public init(
        endpointURL: URL,
        timeout: TimeInterval = 15,
        maxPhotoSize: Int = 8 * 1_024 * 1_024,
        maxResponseSize: Int = 64 * 1_024,
        minimumCredentialValidity: TimeInterval = 30,
        maximumCredentialLifetime: TimeInterval = 10 * 60
    ) {
        self.endpointURL = endpointURL
        self.timeout = timeout
        self.maxPhotoSize = maxPhotoSize
        self.maxResponseSize = maxResponseSize
        self.minimumCredentialValidity = minimumCredentialValidity
        self.maximumCredentialLifetime = maximumCredentialLifetime
    }
}

public struct ThingPhotoLabelingRelayCredential: Hashable, Sendable {
    public enum Scheme: String, Hashable, Sendable {
        case bearer = "Bearer"
        case dpop = "DPoP"
    }

    public let scheme: Scheme
    public let accessToken: String
    public let issuedAt: Date
    public let expiresAt: Date
    public let proof: String?

    public init(
        scheme: Scheme,
        accessToken: String,
        issuedAt: Date,
        expiresAt: Date,
        proof: String? = nil
    ) {
        self.scheme = scheme
        self.accessToken = accessToken
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.proof = proof
    }
}

public final class RelayThingPhotoLabelingService: ThingPhotoLabelingService, @unchecked Sendable {
    public typealias CredentialProvider = @Sendable () async throws -> ThingPhotoLabelingRelayCredential

    static let contractVersion = "1"
    private static let maxNameCharacterCount = 120
    private static let maxDetailCharacterCount = 240
    private static let maxKeywordCharacterCount = 80
    private static let maxKeywordCount = 12

    private let configuration: ThingPhotoLabelingRelayConfiguration
    private let credentialProvider: CredentialProvider
    private let session: URLSession
    private let now: @Sendable () -> Date
    private let requestIDProvider: @Sendable () -> UUID

    public convenience init(
        configuration: ThingPhotoLabelingRelayConfiguration,
        credentialProvider: @escaping CredentialProvider,
        now: @escaping @Sendable () -> Date = Date.init,
        requestIDProvider: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.init(
            configuration: configuration,
            credentialProvider: credentialProvider,
            session: Self.makeDefaultSession(),
            now: now,
            requestIDProvider: requestIDProvider
        )
    }

    public init(
        configuration: ThingPhotoLabelingRelayConfiguration,
        credentialProvider: @escaping CredentialProvider,
        session: URLSession,
        now: @escaping @Sendable () -> Date = Date.init,
        requestIDProvider: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.configuration = configuration
        self.credentialProvider = credentialProvider
        self.session = session
        self.now = now
        self.requestIDProvider = requestIDProvider
    }

    public func suggestLabel(for photo: PhotoInput) async throws -> ThingLabelSuggestion {
        try validate(photo)

        let credential: ThingPhotoLabelingRelayCredential
        do {
            credential = try await credentialProvider()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ThingPhotoLabelingError.serviceUnavailable
        }

        let requestID = requestIDProvider()
        let request = try makeRequest(for: photo, credential: credential, requestID: requestID)

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
        guard httpResponse.url == configuration.endpointURL,
              httpResponse.mimeType?.lowercased() == "application/json",
              data.count <= configuration.maxResponseSize else {
            throw ThingPhotoLabelingError.invalidResponse
        }
        return try parseResponse(data, requestID: requestID)
    }

    func makeRequest(
        for photo: PhotoInput,
        credential: ThingPhotoLabelingRelayCredential,
        requestID: UUID
    ) throws -> URLRequest {
        try validate(photo)
        try validate(credential)

        var request = URLRequest(
            url: configuration.endpointURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: configuration.timeout
        )
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.contractVersion, forHTTPHeaderField: "WITT-Relay-Version")
        request.setValue(requestID.uuidString.lowercased(), forHTTPHeaderField: "Idempotency-Key")
        request.setValue(
            "\(credential.scheme.rawValue) \(credential.accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        if credential.scheme == .dpop {
            request.setValue(credential.proof, forHTTPHeaderField: "DPoP")
        }

        let body = RelayRequest(
            contractVersion: Self.contractVersion,
            requestID: requestID.uuidString.lowercased(),
            purpose: "thing_photo_labeling",
            photo: .init(
                contentType: "image/jpeg",
                dataBase64: photo.data.base64EncodedString(),
                width: photo.dimensions?.width,
                height: photo.dimensions?.height
            ),
            privacy: .init(
                relayRetentionSeconds: 0,
                allowProviderStorage: false,
                allowTraining: false
            )
        )
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw ThingPhotoLabelingError.serviceUnavailable
        }
        return request
    }

    private func validate(_ photo: PhotoInput) throws {
        guard Self.isAllowedEndpoint(configuration.endpointURL),
              configuration.timeout > 0,
              configuration.maxPhotoSize > 0,
              configuration.maxResponseSize > 0,
              configuration.minimumCredentialValidity >= 0,
              configuration.maximumCredentialLifetime > 0 else {
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

    private func validate(_ credential: ThingPhotoLabelingRelayCredential) throws {
        let currentDate = now()
        let tokenLifetime = credential.expiresAt.timeIntervalSince(credential.issuedAt)
        let remainingLifetime = credential.expiresAt.timeIntervalSince(currentDate)

        guard credential.issuedAt <= currentDate,
              tokenLifetime > 0,
              tokenLifetime <= configuration.maximumCredentialLifetime,
              remainingLifetime >= configuration.minimumCredentialValidity,
              Self.isToken68(credential.accessToken) else {
            throw ThingPhotoLabelingError.unauthorized
        }

        switch credential.scheme {
        case .bearer:
            guard credential.proof == nil else {
                throw ThingPhotoLabelingError.unauthorized
            }
        case .dpop:
            guard let proof = credential.proof, Self.isToken68(proof) else {
                throw ThingPhotoLabelingError.unauthorized
            }
        }
    }

    private func validate(statusCode: Int) throws {
        switch statusCode {
        case 200:
            return
        case 400, 422:
            throw ThingPhotoLabelingError.invalidResponse
        case 401:
            throw ThingPhotoLabelingError.unauthorized
        case 403:
            throw ThingPhotoLabelingError.forbidden
        case 408:
            throw ThingPhotoLabelingError.timedOut
        case 413:
            throw ThingPhotoLabelingError.photoTooLarge
        case 429:
            throw ThingPhotoLabelingError.rateLimited
        case 500...599:
            throw ThingPhotoLabelingError.serverError
        default:
            throw ThingPhotoLabelingError.unexpectedStatusCode(statusCode)
        }
    }

    private func parseResponse(_ data: Data, requestID: UUID) throws -> ThingLabelSuggestion {
        let response: RelayResponse
        do {
            response = try JSONDecoder().decode(RelayResponse.self, from: data)
        } catch {
            throw ThingPhotoLabelingError.malformedResponse
        }

        guard response.contractVersion == Self.contractVersion,
              response.requestID == requestID.uuidString.lowercased() else {
            throw ThingPhotoLabelingError.malformedResponse
        }

        switch response.outcome {
        case .refusal:
            guard response.suggestion == nil else {
                throw ThingPhotoLabelingError.malformedResponse
            }
            throw ThingPhotoLabelingError.refused
        case .suggestion:
            guard let suggestion = response.suggestion else {
                throw ThingPhotoLabelingError.missingOutput
            }
            let proposedName = Self.normalizedWhitespace(suggestion.proposedName)
            guard !proposedName.isEmpty else {
                throw ThingPhotoLabelingError.emptyName
            }
            if let confidence = suggestion.confidence,
               !confidence.isFinite || !(0...1).contains(confidence) {
                throw ThingPhotoLabelingError.invalidConfidence
            }

            let detail = suggestion.detail
                .map(Self.normalizedWhitespace)
                .flatMap { $0.isEmpty ? nil : $0 }
            let keywords = ThingKeywordNormalizer.normalize(suggestion.keywords)
            guard proposedName.count <= Self.maxNameCharacterCount,
                  detail.map({ $0.count <= Self.maxDetailCharacterCount }) ?? true,
                  keywords.count <= Self.maxKeywordCount,
                  keywords.allSatisfy({ $0.count <= Self.maxKeywordCharacterCount }) else {
                throw ThingPhotoLabelingError.malformedStructuredOutput
            }
            return ThingLabelSuggestion(
                proposedName: proposedName,
                keywords: keywords,
                detail: detail,
                confidence: suggestion.confidence
            )
        }
    }

    private func map(_ error: URLError) -> ThingPhotoLabelingError {
        switch error.code {
        case .timedOut:
            return .timedOut
        default:
            return .connectionUnavailable
        }
    }

    nonisolated static func isAllowedEndpoint(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host.map { !$0.isEmpty } == true
            && url.user == nil
            && url.password == nil
            && url.query == nil
            && url.fragment == nil
    }

    nonisolated private static func isToken68(_ value: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~+/=")
        return !value.isEmpty && value.unicodeScalars.allSatisfy {
            $0.isASCII && allowed.contains($0)
        }
    }

    nonisolated private static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        return URLSession(
            configuration: configuration,
            delegate: RelayRedirectRejectingDelegate(),
            delegateQueue: nil
        )
    }

    nonisolated private static func normalizedWhitespace(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

private final class RelayRedirectRejectingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private struct RelayRequest: Encodable {
    let contractVersion: String
    let requestID: String
    let purpose: String
    let photo: Photo
    let privacy: Privacy

    struct Photo: Encodable {
        let contentType: String
        let dataBase64: String
        let width: Int?
        let height: Int?

        enum CodingKeys: String, CodingKey {
            case contentType = "content_type"
            case dataBase64 = "data_base64"
            case width
            case height
        }
    }

    struct Privacy: Encodable {
        let relayRetentionSeconds: Int
        let allowProviderStorage: Bool
        let allowTraining: Bool

        enum CodingKeys: String, CodingKey {
            case relayRetentionSeconds = "relay_retention_seconds"
            case allowProviderStorage = "allow_provider_storage"
            case allowTraining = "allow_training"
        }
    }

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case requestID = "request_id"
        case purpose
        case photo
        case privacy
    }
}

private struct RelayResponse: Decodable {
    enum Outcome: String, Decodable {
        case suggestion
        case refusal
    }

    let contractVersion: String
    let requestID: String
    let outcome: Outcome
    let suggestion: Suggestion?

    struct Suggestion: Decodable {
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

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case requestID = "request_id"
        case outcome
        case suggestion
    }
}
