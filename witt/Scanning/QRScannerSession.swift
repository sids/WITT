@preconcurrency import AVFoundation
import Foundation

final class QRScannerSession: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    enum SessionError: LocalizedError {
        case noCamera
        case inputUnavailable(Error)
        case cannotAddInput
        case cannotAddOutput
        case qrScanningUnavailable

        var errorDescription: String? {
            switch self {
            case .noCamera:
                "No camera is available on this device."
            case .inputUnavailable:
                "WITT could not access the camera input."
            case .cannotAddInput, .cannotAddOutput, .qrScanningUnavailable:
                "WITT could not configure QR code scanning."
            }
        }
    }

    let captureSession = AVCaptureSession()

    var cameraIsAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
            || AVCaptureDevice.default(for: .video) != nil
    }

    private let sessionQueue = DispatchQueue(label: "in.sids.witt.qr-scanner.session")
    private var cameraDevice: AVCaptureDevice?
    private var isConfigured = false
    private var wantsToRun = false
    private var payloadDeduplicator: QRScannerPayloadDeduplicator
    private let onPayload: @MainActor @Sendable (String) -> Void
    private let onEvent: @MainActor @Sendable (QRScannerStateMachine.Event) -> Void
    private let onTorchAvailability: @MainActor @Sendable (Bool, Bool) -> Void

    init(
        suppressionInterval: TimeInterval,
        onPayload: @escaping @MainActor @Sendable (String) -> Void,
        onEvent: @escaping @MainActor @Sendable (QRScannerStateMachine.Event) -> Void,
        onTorchAvailability: @escaping @MainActor @Sendable (Bool, Bool) -> Void
    ) {
        payloadDeduplicator = QRScannerPayloadDeduplicator(
            suppressionInterval: suppressionInterval
        )
        self.onPayload = onPayload
        self.onEvent = onEvent
        self.onTorchAvailability = onTorchAvailability
        super.init()
    }

    func start() {
        sessionQueue.async { [self] in
            wantsToRun = true

            do {
                if !isConfigured {
                    try configureSession()
                }
                guard wantsToRun else { return }

                if !captureSession.isRunning {
                    captureSession.startRunning()
                }
                emit(.sessionStarted)
            } catch {
                emit(.failed(error.localizedDescription))
            }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            wantsToRun = false
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
            payloadDeduplicator.reset()
            emit(.sessionStopped)
            emitTorchAvailability(isOn: false)
        }
    }

    func setTorch(enabled: Bool) {
        sessionQueue.async { [self] in
            guard let cameraDevice, cameraDevice.hasTorch else {
                emitTorchAvailability(isOn: false)
                return
            }

            do {
                try cameraDevice.lockForConfiguration()
                defer { cameraDevice.unlockForConfiguration() }

                if enabled, cameraDevice.isTorchModeSupported(.on) {
                    try cameraDevice.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                } else {
                    cameraDevice.torchMode = .off
                }
                emitTorchAvailability(isOn: cameraDevice.torchMode == .on)
            } catch {
                emit(.failed("WITT could not change the flashlight setting."))
            }
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard wantsToRun else { return }

        for case let code as AVMetadataMachineReadableCodeObject in metadataObjects
        where code.type == .qr {
            guard let payload = code.stringValue,
                  payloadDeduplicator.shouldEmit(payload) else {
                continue
            }

            Task { @MainActor [onPayload] in
                onPayload(payload)
            }
            return
        }
    }

    private func configureSession() throws {
        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) ?? AVCaptureDevice.default(for: .video) else {
            throw SessionError.noCamera
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: camera)
        } catch {
            throw SessionError.inputUnavailable(error)
        }

        let output = AVCaptureMetadataOutput()
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.sessionPreset = .high
        guard captureSession.canAddInput(input) else {
            throw SessionError.cannotAddInput
        }
        captureSession.addInput(input)

        guard captureSession.canAddOutput(output) else {
            throw SessionError.cannotAddOutput
        }
        captureSession.addOutput(output)

        guard output.availableMetadataObjectTypes.contains(.qr) else {
            throw SessionError.qrScanningUnavailable
        }
        output.setMetadataObjectsDelegate(self, queue: sessionQueue)
        output.metadataObjectTypes = [.qr]

        cameraDevice = camera
        isConfigured = true
        emitTorchAvailability(isOn: false)
    }

    private func emit(_ event: QRScannerStateMachine.Event) {
        Task { @MainActor [onEvent] in
            onEvent(event)
        }
    }

    private func emitTorchAvailability(isOn: Bool) {
        let isAvailable = cameraDevice?.hasTorch == true
        Task { @MainActor [onTorchAvailability] in
            onTorchAvailability(isAvailable, isOn)
        }
    }
}
