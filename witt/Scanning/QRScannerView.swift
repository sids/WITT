@preconcurrency import AVFoundation
import Combine
import SwiftUI
import UIKit

struct QRScannerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var scanner: QRScannerController
    let isPaused: Bool

    init(
        isPaused: Bool = false,
        duplicateSuppressionInterval: TimeInterval = 1.5,
        onPayload: @escaping @MainActor @Sendable (String) -> Void
    ) {
        self.isPaused = isPaused
        _scanner = StateObject(
            wrappedValue: QRScannerController(
                duplicateSuppressionInterval: duplicateSuppressionInterval,
                onPayload: onPayload
            )
        )
    }

    var body: some View {
        ZStack {
            CameraPreviewView(session: scanner.captureSession)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            statusContent
        }
        .background(Color.black)
        .overlay(alignment: .topTrailing) {
            if scanner.isTorchAvailable, scanner.state == .running {
                Button {
                    scanner.toggleTorch()
                } label: {
                    Image(systemName: scanner.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                }
                .accessibilityLabel(scanner.isTorchOn ? "Turn flashlight off" : "Turn flashlight on")
                .padding()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("QR code scanner")
        .onAppear {
            if !isPaused { scanner.resume() }
        }
        .onDisappear {
            scanner.pause()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !isPaused {
                scanner.resume()
            } else {
                scanner.pause()
            }
        }
        .onChange(of: isPaused) { _, paused in
            if paused {
                scanner.pause()
            } else if scenePhase == .active {
                scanner.resume()
            }
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch scanner.state {
        case .notDetermined, .requesting:
            ProgressView("Requesting camera access")
                .tint(.white)
                .foregroundStyle(.white)
        case .authorized:
            ProgressView("Starting scanner")
                .tint(.white)
                .foregroundStyle(.white)
        case .deniedOrRestricted:
            ContentUnavailableView(
                "Camera Access Required",
                systemImage: "camera.fill",
                description: Text("Allow camera access in Settings to scan QR codes.")
            )
            .foregroundStyle(.white)
        case .unavailable:
            ContentUnavailableView(
                "Camera Unavailable",
                systemImage: "camera.slash",
                description: Text("QR scanning requires a device with a camera. It is not available in this simulator.")
            )
            .foregroundStyle(.white)
        case let .failure(message):
            ContentUnavailableView(
                "Scanner Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
            .foregroundStyle(.white)
        case .running:
            Color.clear
                .accessibilityLabel("Camera is ready. Point it at a QR code.")
        }
    }
}

@MainActor
private final class QRScannerController: ObservableObject {
    @Published private(set) var state: QRScannerState = .notDetermined
    @Published private(set) var isTorchAvailable = false
    @Published private(set) var isTorchOn = false

    var captureSession: AVCaptureSession { session.captureSession }

    private var stateMachine = QRScannerStateMachine()
    private var shouldBeRunning = false
    private lazy var session: QRScannerSession = {
        QRScannerSession(
            suppressionInterval: duplicateSuppressionInterval,
            onPayload: onPayload,
            onEvent: { [weak self] event in
                self?.receive(event)
            },
            onTorchAvailability: { [weak self] isAvailable, isOn in
                self?.isTorchAvailable = isAvailable
                self?.isTorchOn = isOn
            }
        )
    }()
    private let duplicateSuppressionInterval: TimeInterval
    private let onPayload: @MainActor @Sendable (String) -> Void

    init(
        duplicateSuppressionInterval: TimeInterval,
        onPayload: @escaping @MainActor @Sendable (String) -> Void
    ) {
        self.duplicateSuppressionInterval = duplicateSuppressionInterval
        self.onPayload = onPayload
    }

    func resume() {
        guard !shouldBeRunning else { return }
        shouldBeRunning = true

        guard session.cameraIsAvailable else {
            receive(.cameraUnavailable)
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            receive(.requestAuthorization)
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                guard shouldBeRunning else { return }
                if granted {
                    receive(.authorizationGranted)
                    session.start()
                } else {
                    receive(.authorizationDeniedOrRestricted)
                }
            }
        case .authorized:
            receive(.authorizationGranted)
            session.start()
        case .denied, .restricted:
            receive(.authorizationDeniedOrRestricted)
        @unknown default:
            receive(.authorizationDeniedOrRestricted)
        }
    }

    func pause() {
        guard shouldBeRunning else { return }
        shouldBeRunning = false
        session.stop()
    }

    func toggleTorch() {
        session.setTorch(enabled: !isTorchOn)
    }

    private func receive(_ event: QRScannerStateMachine.Event) {
        if event == .sessionStarted, !shouldBeRunning {
            session.stop()
            return
        }

        stateMachine.handle(event)
        state = stateMachine.state
    }
}

private struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        CameraPreviewUIView(session: session)
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.updateVideoRotation()
    }
}

private final class CameraPreviewUIView: UIView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        updateVideoRotation()
    }

    func updateVideoRotation() {
        guard let connection = previewLayer.connection,
              let orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation else {
            return
        }

        let angle: CGFloat = switch orientation {
        case .portrait: 90
        case .portraitUpsideDown: 270
        case .landscapeLeft: 0
        case .landscapeRight: 180
        default: 90
        }

        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }
}
