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

    func testDeepLinkRouterPreservesKnownDestination() async throws {
        let token = try XCTUnwrap(QRToken(rawValue: "AAAAAAAAAAAAAAAAAAAAAA"))
        let areaID = QRTargetID(rawValue: UUID())
        let router = QRDeepLinkRouter(resolver: StubResolver(result: .knownArea(areaID)))

        let destination = try await router.destination(for: try WITTQRCodeURL(token: token).url)

        guard case .addThing(.area(let routedID)) = destination else {
            return XCTFail("Expected the known Storage Area destination")
        }
        XCTAssertEqual(routedID, areaID.rawValue)
    }

    func testDeepLinkRouterPreservesUnknownTokenForAttachment() async throws {
        let token = try XCTUnwrap(QRToken(rawValue: "BBBBBBBBBBBBBBBBBBBBBA"))
        let router = QRDeepLinkRouter(resolver: StubResolver(result: .unknown))

        let destination = try await router.destination(for: try WITTQRCodeURL(token: token).url)

        guard case .attach(let routedToken) = destination else {
            return XCTFail("Expected the unknown QR attachment destination")
        }
        XCTAssertEqual(routedToken, token)
    }

    func testScannerRouterPreservesKnownArbitraryPayloadDestination() async throws {
        let token = try XCTUnwrap(QRToken(rawValue: "vendor inventory #42"))
        let containerID = QRTargetID(rawValue: UUID())
        let router = QRDeepLinkRouter(resolver: StubResolver(result: .knownContainer(containerID)))

        let destination = try await router.destination(for: token)

        guard case .addThing(.container(let routedID)) = destination else {
            return XCTFail("Expected the known Container destination")
        }
        XCTAssertEqual(routedID, containerID.rawValue)
    }

    func testScannerRouterPreservesUnknownArbitraryPayloadForAttachment() async throws {
        let token = try XCTUnwrap(QRToken(rawValue: "https://example.com/items/42?variant=A+B"))
        let router = QRDeepLinkRouter(resolver: StubResolver(result: .unknown))

        let destination = try await router.destination(for: token)

        guard case .attach(let routedToken) = destination else {
            return XCTFail("Expected the unknown QR attachment destination")
        }
        XCTAssertEqual(routedToken.rawValue, token.rawValue)
    }

    func testDeepLinkRouterPreservesRepairTokenAndDetails() async throws {
        let token = try XCTUnwrap(QRToken(rawValue: "repair payload"))
        let repair = QRCodeRepair(reason: .missingTarget, bindingID: UUID())
        let router = QRDeepLinkRouter(resolver: StubResolver(result: .needsRepair(repair)))

        let destination = try await router.destination(for: token)

        guard case .repair(let route) = destination else {
            return XCTFail("Expected the Repair QR destination")
        }
        XCTAssertEqual(route, QRCodeRepairRoute(token: token, issue: .unavailable(repair)))
    }

    func testDeepLinkRouterPreservesConflictTokenAndTargets() async throws {
        let token = try XCTUnwrap(QRToken(rawValue: "conflict payload"))
        let conflict = QRCodeConflict(
            firstTarget: .area(QRTargetID(rawValue: UUID())),
            secondTarget: .container(QRTargetID(rawValue: UUID()))
        )
        let router = QRDeepLinkRouter(resolver: StubResolver(result: .conflict(conflict)))

        let destination = try await router.destination(for: token)

        guard case .repair(let route) = destination else {
            return XCTFail("Expected the Repair QR destination")
        }
        XCTAssertEqual(route, QRCodeRepairRoute(token: token, issue: .conflict(conflict)))
    }
}

private struct StubResolver: QRCodeResolving {
    let result: QRCodeResolution

    func resolve(_ token: QRToken) async throws -> QRCodeResolution {
        result
    }
}
