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
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task {
                await loadAndNormalize(item)
                selection = nil
            }
        }
    }

    private func loadAndNormalize(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw PhotoLibraryPickerError.imageDataUnavailable
            }
            let capturedPhoto = CapturedPhoto(
                data: data,
                contentType: item.supportedContentTypes.first?.identifier
                    ?? "application/octet-stream",
                source: .photoLibrary
            )
            let normalizer = normalizer
            let normalizedPhoto = try await Task.detached(priority: .userInitiated) {
                try normalizer.normalize(capturedPhoto)
            }.value
            onResult(normalizedPhoto)
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
