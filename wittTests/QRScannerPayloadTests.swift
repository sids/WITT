import XCTest
@testable import witt

final class QRScannerPayloadTests: XCTestCase {
    func testScannerOutcomeUnwrapsGeneratedURLForLegacyStoredTokenLookup() throws {
        let payload = "witt://qr/v1/BBBBBBBBBBBBBBBBBBBBBA"
        let storedToken = try XCTUnwrap(QRToken(rawValue: "BBBBBBBBBBBBBBBBBBBBBA"))

        XCTAssertEqual(ScannerOutcome(payload: payload), .payload(storedToken))
    }

    func testScannerOutcomeAcceptsAndExactlyPreservesArbitraryPayload() throws {
        let payload = "  vendor:item/42?serial=A+B  "

        XCTAssertEqual(ScannerOutcome(payload: payload), .payload(try XCTUnwrap(QRToken(rawValue: payload))))
    }

    func testScannerOutcomeRejectsEmptyPayload() {
        XCTAssertEqual(ScannerOutcome(payload: ""), .invalidPayload)
    }

    func testScannerOutcomePreservesMalformedWITTLikePayloadAsArbitraryIdentity() throws {
        let payload = "witt://qr/v2/not-a-generated-token"

        XCTAssertEqual(
            ScannerOutcome(payload: payload),
            .payload(try XCTUnwrap(QRToken(rawValue: payload)))
        )
    }

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

    func testStateMachineCoversDeniedRestrictedUnavailableAndFailure() {
        var stateMachine = QRScannerStateMachine()

        stateMachine.handle(.authorizationDenied)
        XCTAssertEqual(stateMachine.state, .denied)
        stateMachine.handle(.authorizationRestricted)
        XCTAssertEqual(stateMachine.state, .restricted)
        stateMachine.handle(.cameraUnavailable)
        XCTAssertEqual(stateMachine.state, .unavailable)
        stateMachine.handle(.failed("Configuration failed"))
        XCTAssertEqual(stateMachine.state, .failure("Configuration failed"))
    }

    func testStateMachineRecoversFromDeniedAuthorization() {
        var stateMachine = QRScannerStateMachine()

        stateMachine.handle(.authorizationDenied)
        stateMachine.handle(.authorizationGranted)
        XCTAssertEqual(stateMachine.state, .authorized)
        stateMachine.handle(.sessionStarted)
        XCTAssertEqual(stateMachine.state, .running)
    }

    func testStateMachineRecoversFromRestrictedAuthorization() {
        var stateMachine = QRScannerStateMachine()

        stateMachine.handle(.authorizationRestricted)
        stateMachine.handle(.authorizationGranted)
        XCTAssertEqual(stateMachine.state, .authorized)
    }
}
