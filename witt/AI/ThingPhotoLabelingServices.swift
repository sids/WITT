import Foundation

#if DEBUG
struct DebugThingPhotoLabelingService: ThingPhotoLabelingService {
    func suggestLabel(for photo: PhotoInput) async throws -> ThingLabelSuggestion {
        try await Task.sleep(for: .milliseconds(250))
        return ThingLabelSuggestion(
            proposedName: "LED Flashlight",
            keywords: ["flashlight", "torch", "emergency", "battery"],
            detail: "Compact black flashlight.",
            confidence: 0.94
        )
    }
}
#endif

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
           let model {
            let configuration = OpenAICompatibleThingPhotoLabelingConfiguration(
                endpointURL: endpointURL,
                model: model
            )
            if configuration.isValid {
                return OpenAICompatibleThingPhotoLabelingService(
                    configuration: configuration,
                    bearerTokenProvider: { token },
                    session: session
                )
            }
        }

        if endpointValue != nil || model != nil || token != nil {
            return UnavailableThingPhotoLabelingService()
        }

        #if DEBUG
        return DebugThingPhotoLabelingService()
        #else
        return UnavailableThingPhotoLabelingService()
        #endif
    }
}
