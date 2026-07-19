@preconcurrency import AVFoundation
import SwiftUI
import UIKit

enum CameraAuthorizationState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable

    init(isCameraAvailable: Bool, authorizationStatus: AVAuthorizationStatus) {
        guard isCameraAvailable else {
            self = .unavailable
            return
        }

        switch authorizationStatus {
        case .notDetermined:
            self = .notDetermined
        case .authorized:
            self = .authorized
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        @unknown default:
            self = .restricted
        }
    }

    var offersSettingsRecovery: Bool {
        self == .denied || self == .restricted
    }

#if DEBUG
    static var demoOverride: CameraAuthorizationState? {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--demo-camera-denied") {
            return .denied
        }
        if arguments.contains("--demo-camera-restricted") {
            return .restricted
        }
        return nil
    }
#endif
}

public struct CameraCaptureView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private let normalizer: PhotoNormalizer
    private let onCancel: () -> Void
    private let onResult: (NormalizedPhoto) -> Void
    private let onError: (Error) -> Void

    @State private var authorizationState: CameraAuthorizationState = .notDetermined
    @State private var isRequestingAuthorization = false

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
            switch authorizationState {
            case .authorized:
                SystemCameraPicker(
                    normalizer: normalizer,
                    onCancel: onCancel,
                    onResult: onResult,
                    onError: onError
                )
                .ignoresSafeArea()
            case .notDetermined:
                ProgressView(
                    isRequestingAuthorization
                        ? "Requesting camera access"
                        : "Checking camera access"
                )
            case .denied:
                cameraAccessRecovery(
                    title: "Camera Access Required",
                    description: "Allow camera access in Settings to take photos."
                )
            case .restricted:
                cameraAccessRecovery(
                    title: "Camera Access Restricted",
                    description: "Camera access is restricted by Screen Time or device management. Review your device settings or contact the device administrator."
                )
            case .unavailable:
                ContentUnavailableView {
                    Label("Camera Unavailable", systemImage: "camera.slash")
                } description: {
                    Text("This device does not have a camera available. Choose a photo from the library instead.")
                } actions: {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier("cameraCapture.cancel")
                }
            }
        }
        .task {
            await refreshAuthorization()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await refreshAuthorization()
            }
        }
    }

    private func cameraAccessRecovery(title: String, description: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "camera.fill")
        } description: {
            Text(description)
        } actions: {
            Button("Open Settings", systemImage: "gear") {
                guard authorizationState.offersSettingsRecovery,
                      let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
                    return
                }
                openURL(settingsURL)
            }
            .accessibilityIdentifier("cameraCapture.openSettings")

            Button("Cancel", action: onCancel)
                .accessibilityIdentifier("cameraCapture.cancel")
        }
    }

    @MainActor
    private func refreshAuthorization() async {
#if DEBUG
        if let demoOverride = CameraAuthorizationState.demoOverride {
            authorizationState = demoOverride
            return
        }
#endif

        let currentState = CameraAuthorizationState(
            isCameraAvailable: UIImagePickerController.isSourceTypeAvailable(.camera),
            authorizationStatus: AVCaptureDevice.authorizationStatus(for: .video)
        )
        authorizationState = currentState

        guard currentState == .notDetermined, !isRequestingAuthorization else { return }
        isRequestingAuthorization = true
        _ = await AVCaptureDevice.requestAccess(for: .video)
        isRequestingAuthorization = false
        authorizationState = CameraAuthorizationState(
            isCameraAvailable: UIImagePickerController.isSourceTypeAvailable(.camera),
            authorizationStatus: AVCaptureDevice.authorizationStatus(for: .video)
        )
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
