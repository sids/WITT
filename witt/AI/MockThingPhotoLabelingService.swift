import Foundation

public struct MockThingPhotoLabelingService: ThingPhotoLabelingService {
    public enum Mode: Sendable {
        case success(ThingLabelSuggestion)
        case delayedSuccess(ThingLabelSuggestion, delay: Duration)
        case failure(ThingPhotoLabelingError)
    }

    private let mode: Mode

    public init(mode: Mode) {
        self.mode = mode
    }

    public func suggestLabel(for photo: PhotoInput) async throws -> ThingLabelSuggestion {
        switch mode {
        case let .success(suggestion):
            return suggestion
        case let .delayedSuccess(suggestion, delay):
            try await Task.sleep(for: delay)
            return suggestion
        case let .failure(error):
            throw error
        }
    }
}
