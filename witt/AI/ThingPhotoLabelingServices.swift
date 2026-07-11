import Foundation

public struct UnavailableThingPhotoLabelingService: ThingPhotoLabelingService {
    public init() {}

    public func suggestLabel(for photo: PhotoInput) async throws -> ThingLabelSuggestion {
        throw ThingPhotoLabelingError.serviceUnavailable
    }
}

public enum ThingPhotoLabelingServices {
    public static func appDefault() -> any ThingPhotoLabelingService {
        appDefault(environment: ProcessInfo.processInfo.environment)
    }

    static func appDefault(
        environment: [String: String],
        session: URLSession = .shared
    ) -> any ThingPhotoLabelingService {
        let endpointValue = environment["WITT_AI_RESPONSES_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let model = environment["WITT_AI_MODEL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let token = environment["WITT_AI_BEARER_TOKEN"]

        if let endpointValue,
           let endpointURL = URL(string: endpointValue),
           OpenAICompatibleThingPhotoLabelingService.isAllowedEndpoint(endpointURL),
           let model,
           !model.isEmpty {
            let configuration = OpenAICompatibleThingPhotoLabelingConfiguration(
                endpointURL: endpointURL,
                model: model
            )
            return OpenAICompatibleThingPhotoLabelingService(
                configuration: configuration,
                bearerTokenProvider: { token },
                session: session
            )
        }

        if endpointValue != nil || model != nil || token != nil {
            return UnavailableThingPhotoLabelingService()
        }

        #if DEBUG
        return MockThingPhotoLabelingService.demo
        #else
        return UnavailableThingPhotoLabelingService()
        #endif
    }
}
