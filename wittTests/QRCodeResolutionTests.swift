import XCTest
@testable import witt

final class QRCodeResolutionTests: XCTestCase {
    func testBindingRequestsSupportAreaAndContainerTargets() throws {
        let token = try XCTUnwrap(QRToken(rawValue: "AAAAAAAAAAAAAAAAAAAAAA"))
        let areaID = QRTargetID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let containerID = QRTargetID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)

        XCTAssertEqual(QRCodeBindingRequest(token: token, target: .area(areaID)).target, .area(areaID))
        XCTAssertEqual(QRCodeBinding(token: token, target: .container(containerID)).target, .container(containerID))
    }

    func testResolutionStatesRetainTheirAssociatedValues() {
        let areaID = QRTargetID(rawValue: UUID())
        let containerID = QRTargetID(rawValue: UUID())
        let repairID = UUID()
        let conflict = QRCodeConflict(
            firstTarget: .area(areaID),
            secondTarget: .container(containerID),
            additionalTargets: [.area(areaID)]
        )

        XCTAssertEqual(QRCodeResolution.knownArea(areaID), .knownArea(areaID))
        XCTAssertEqual(QRCodeResolution.knownContainer(containerID), .knownContainer(containerID))
        XCTAssertEqual(QRCodeResolution.unknown, .unknown)
        XCTAssertEqual(
            QRCodeResolution.needsRepair(.init(reason: .missingTarget, bindingID: repairID)),
            .needsRepair(.init(reason: .missingTarget, bindingID: repairID))
        )
        XCTAssertEqual(conflict.targets, [.area(areaID), .container(containerID), .area(areaID)])
        XCTAssertEqual(QRCodeResolution.conflict(conflict), .conflict(conflict))
    }
}
