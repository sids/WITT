import PhotosUI
import SwiftUI

public struct PhotoLibraryPicker<Label: View>: View {
    private let normalizer: PhotoNormalizer
    private let onResult: (NormalizedPhoto) -> Void
    private let onError: (Error) -> Void
    private let label: Label

    @State private var selection: PhotosPickerItem?

    public init(
        normalizer: PhotoNormalizer = PhotoNormalizer(),
        onResult: @escaping (NormalizedPhoto) -> Void,
        onError: @escaping (Error) -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.normalizer = normalizer
        self.onResult = onResult
        self.onError = onError
        self.label = label()
    }

    public var body: some View {
        PhotosPicker(selection: $selection, matching: .images) {
            label
        }
        .disabled(selection != nil)
        .task(id: selection) {
            let item = selection
            guard let item else { return }
            await loadAndNormalize(item)
            if selection == item {
                selection = nil
            }
        }
    }

    private func loadAndNormalize(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw PhotoLibraryPickerError.imageDataUnavailable
            }
            try Task.checkCancellation()
            let capturedPhoto = CapturedPhoto(
                data: data,
                source: .photoLibrary
            )
            let normalizer = normalizer
            let normalizedPhoto = try await Task.detached(priority: .userInitiated) {
                try normalizer.normalize(capturedPhoto)
            }.value
            try Task.checkCancellation()
            onResult(normalizedPhoto)
        } catch is CancellationError {
            return
        } catch {
            onError(error)
        }
    }
}

public enum PhotoLibraryPickerError: Error, Equatable, LocalizedError, Sendable {
    case imageDataUnavailable

    public var errorDescription: String? {
        "WITT could not load that photo."
    }
}
