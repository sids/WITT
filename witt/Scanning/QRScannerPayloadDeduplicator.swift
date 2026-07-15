import Foundation

struct QRScannerPayloadDeduplicator: Sendable {
    let suppressionInterval: TimeInterval
    private var lastEmissionByPayload: [String: Date] = [:]

    init(suppressionInterval: TimeInterval = 1.5) {
        precondition(suppressionInterval >= 0)
        self.suppressionInterval = suppressionInterval
    }

    mutating func shouldEmit(_ payload: String, at date: Date = Date()) -> Bool {
        guard !payload.isEmpty else { return false }

        if let lastEmission = lastEmissionByPayload[payload],
           date.timeIntervalSince(lastEmission) < suppressionInterval {
            return false
        }

        lastEmissionByPayload[payload] = date
        removeExpiredEntries(relativeTo: date)
        return true
    }

    mutating func reset() {
        lastEmissionByPayload.removeAll(keepingCapacity: true)
    }

    private mutating func removeExpiredEntries(relativeTo date: Date) {
        lastEmissionByPayload = lastEmissionByPayload.filter {
            date.timeIntervalSince($0.value) < suppressionInterval
        }
    }
}

enum QRScannerState: Equatable, Sendable {
    case notDetermined
    case requesting
    case authorized
    case denied
    case restricted
    case unavailable
    case running
    case failure(String)
}

struct QRScannerStateMachine: Sendable {
    enum Event: Equatable, Sendable {
        case requestAuthorization
        case authorizationGranted
        case authorizationDenied
        case authorizationRestricted
        case cameraUnavailable
        case sessionStarted
        case sessionStopped
        case failed(String)
    }

    private(set) var state: QRScannerState = .notDetermined

    mutating func handle(_ event: Event) {
        switch event {
        case .requestAuthorization:
            state = .requesting
        case .authorizationGranted:
            state = .authorized
        case .authorizationDenied:
            state = .denied
        case .authorizationRestricted:
            state = .restricted
        case .cameraUnavailable:
            state = .unavailable
        case .sessionStarted:
            state = .running
        case .sessionStopped:
            if state == .running {
                state = .authorized
            }
        case let .failed(message):
            state = .failure(message)
        }
    }
}
