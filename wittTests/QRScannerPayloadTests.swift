import XCTest
@testable import witt

final class QRScannerPayloadTests: XCTestCase {
    func testDeduplicatorSuppressesSamePayloadInsideWindow() {
        var deduplicator = QRScannerPayloadDeduplicator(suppressionInterval: 2)
        let start = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertTrue(deduplicator.shouldEmit("witt://qr/v1/first", at: start))
        XCTAssertFalse(
            deduplicator.shouldEmit(
                "witt://qr/v1/first",
                at: start.addingTimeInterval(1.99)
            )
        )
    }

    func testDeduplicatorEmitsAgainAtEndOfWindow() {
        var deduplicator = QRScannerPayloadDeduplicator(suppressionInterval: 2)
        let start = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertTrue(deduplicator.shouldEmit("same", at: start))
        XCTAssertTrue(deduplicator.shouldEmit("same", at: start.addingTimeInterval(2)))
    }

    func testDeduplicatorTracksDifferentPayloadsIndependently() {
        var deduplicator = QRScannerPayloadDeduplicator(suppressionInterval: 2)
        let start = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertTrue(deduplicator.shouldEmit("first", at: start))
        XCTAssertTrue(deduplicator.shouldEmit("second", at: start))
        XCTAssertFalse(deduplicator.shouldEmit("first", at: start.addingTimeInterval(1)))
    }

    func testDeduplicatorRejectsEmptyPayloadAndResetAllowsImmediateEmission() {
        var deduplicator = QRScannerPayloadDeduplicator(suppressionInterval: 10)
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertFalse(deduplicator.shouldEmit("", at: now))
        XCTAssertTrue(deduplicator.shouldEmit("payload", at: now))
        deduplicator.reset()
        XCTAssertTrue(deduplicator.shouldEmit("payload", at: now))
    }

    func testStateMachineCoversAuthorizationRunningAndPause() {
        var stateMachine = QRScannerStateMachine()

        XCTAssertEqual(stateMachine.state, .notDetermined)
        stateMachine.handle(.requestAuthorization)
        XCTAssertEqual(stateMachine.state, .requesting)
        stateMachine.handle(.authorizationGranted)
        XCTAssertEqual(stateMachine.state, .authorized)
        stateMachine.handle(.sessionStarted)
        XCTAssertEqual(stateMachine.state, .running)
        stateMachine.handle(.sessionStopped)
        XCTAssertEqual(stateMachine.state, .authorized)
    }

    func testStateMachineCoversDeniedUnavailableAndFailure() {
        var stateMachine = QRScannerStateMachine()

        stateMachine.handle(.authorizationDeniedOrRestricted)
        XCTAssertEqual(stateMachine.state, .deniedOrRestricted)
        stateMachine.handle(.cameraUnavailable)
        XCTAssertEqual(stateMachine.state, .unavailable)
        stateMachine.handle(.failed("Configuration failed"))
        XCTAssertEqual(stateMachine.state, .failure("Configuration failed"))
    }
}
