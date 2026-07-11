import SwiftUI
import UIKit

public struct CameraCaptureView: View {
    private let normalizer: PhotoNormalizer
    private let onCancel: () -> Void
    private let onResult: (NormalizedPhoto) -> Void
    private let onError: (Error) -> Void

    @State private var reportedUnavailableCamera = false

    public init(
        normalizer: PhotoNormalizer = PhotoNormalizer(),
        onCancel: @escaping () -> Void,
        onResult: @escaping (NormalizedPhoto) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.normalizer = normalizer
        self.onCancel = onCancel
        self.onResult = onResult
        self.onError = onError
    }

    public var body: some View {
        Group {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                SystemCameraPicker(
                    normalizer: normalizer,
                    onCancel: onCancel,
                    onResult: onResult,
                    onError: onError
                )
                .ignoresSafeArea()
            } else {
                ContentUnavailableView {
                    Label("Camera Unavailable", systemImage: "camera.fill")
                } description: {
                    Text("Choose a photo from the library instead.")
                } actions: {
                    Button("Cancel", action: onCancel)
                }
                .onAppear {
                    guard !reportedUnavailableCamera else { return }
                    reportedUnavailableCamera = true
                    onError(CameraCaptureError.cameraUnavailable)
                }
            }
        }
    }
}

public enum CameraCaptureError: Error, Equatable, LocalizedError, Sendable {
    case cameraUnavailable
    case imageUnavailable
    case imageEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            "The camera is unavailable on this device."
        case .imageUnavailable:
            "The camera did not return a photo."
        case .imageEncodingFailed:
            "WITT could not prepare the captured photo."
        }
    }
}

private struct SystemCameraPicker: UIViewControllerRepresentable {
    let normalizer: PhotoNormalizer
    let onCancel: () -> Void
    let onResult: (NormalizedPhoto) -> Void
    let onError: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: SystemCameraPicker

        init(parent: SystemCameraPicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                parent.onError(CameraCaptureError.imageUnavailable)
                return
            }
            guard let data = image.jpegData(compressionQuality: 1) else {
                parent.onError(CameraCaptureError.imageEncodingFailed)
                return
            }

            let capturedPhoto = CapturedPhoto(
                data: data,
                contentType: "image/jpeg",
                source: .camera,
                capturedAt: Date()
            )

            let normalizer = parent.normalizer
            Task { @MainActor [parent] in
                do {
                    let normalizedPhoto = try await Task.detached(priority: .userInitiated) {
                        try normalizer.normalize(capturedPhoto)
                    }.value
                    parent.onResult(normalizedPhoto)
                } catch {
                    parent.onError(error)
                }
            }
        }
    }
}
