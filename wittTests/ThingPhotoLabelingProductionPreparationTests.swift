import Foundation
import XCTest
@testable import witt

final class RelayThingPhotoLabelingServiceTests: XCTestCase {
    private let endpoint = URL(string: "https://ai.witt.example/v1/thing-labels")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let requestID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])

    override func tearDown() {
        RelayStubURLProtocol.handler = nil
        super.tearDown()
    }

    func testRequestUsesProviderNeutralZeroRetentionContract() throws {
        let request = try makeService().makeRequest(
            for: photo(),
            credential: credential(),
            requestID: requestID
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer short-lived-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "WITT-Relay-Version"), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), requestID.uuidString.lowercased())
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertFalse(request.httpShouldHandleCookies)

        let body = try XCTUnwrap(request.httpBody).relayJSONObject
        XCTAssertEqual(body["contract_version"] as? String, "1")
        XCTAssertEqual(body["request_id"] as? String, requestID.uuidString.lowercased())
        XCTAssertEqual(body["purpose"] as? String, "thing_photo_labeling")
        XCTAssertNil(body["model"])
        XCTAssertNil(body["prompt"])

        let privacy = try XCTUnwrap(body["privacy"] as? [String: Any])
        XCTAssertEqual(privacy["relay_retention_seconds"] as? Int, 0)
        XCTAssertEqual(privacy["allow_provider_storage"] as? Bool, false)
        XCTAssertEqual(privacy["allow_training"] as? Bool, false)

        let encodedPhoto = try XCTUnwrap(body["photo"] as? [String: Any])
        XCTAssertEqual(encodedPhoto["content_type"] as? String, "image/jpeg")
        XCTAssertEqual(encodedPhoto["data_base64"] as? String, jpeg.base64EncodedString())
        XCTAssertEqual(encodedPhoto["width"] as? Int, 1)
        XCTAssertEqual(encodedPhoto["height"] as? Int, 1)
    }

    func testCredentialMustBeShortLivedUnexpiredAndHeaderSafe() async {
        for rejected in [
            credential(issuedAt: now.addingTimeInterval(-700), expiresAt: now.addingTimeInterval(30)),
            credential(expiresAt: now.addingTimeInterval(29)),
            credential(token: "token\nInjected: true"),
            credential(token: "token with spaces")
        ] {
            await assertError(.unauthorized) {
                try await self.makeService(credential: rejected).suggestLabel(for: self.photo())
            }
        }
    }

    func testDPoPRequiresProofAndSetsProofHeader() throws {
        XCTAssertThrowsError(
            try makeService().makeRequest(
                for: photo(),
                credential: credential(scheme: .dpop),
                requestID: requestID
            )
        ) { error in
            XCTAssertEqual(error as? ThingPhotoLabelingError, .unauthorized)
        }

        let request = try makeService().makeRequest(
            for: photo(),
            credential: credential(scheme: .dpop, proof: "signed-proof"),
            requestID: requestID
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "DPoP short-lived-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "DPoP"), "signed-proof")
    }

    func testSuccessfulRelayResponseIsCorrelatedAndNormalized() async throws {
        RelayStubURLProtocol.handler = { _ in
            return Self.response(body: Self.relayBody(
                requestID: self.requestID.uuidString.lowercased(),
                outcome: "suggestion",
                suggestion: [
                    "proposed_name": "  USB-C   Charger ",
                    "keywords": [" charger ", "CHARGER", "power adapter"],
                    "detail": "  White   65 W ",
                    "confidence": 0.86
                ]
            ))
        }

        let suggestion = try await makeService().suggestLabel(for: photo())

        XCTAssertEqual(suggestion.proposedName, "USB-C Charger")
        XCTAssertEqual(suggestion.keywords, ["charger", "power adapter"])
        XCTAssertEqual(suggestion.detail, "White 65 W")
        XCTAssertEqual(suggestion.confidence, 0.86)
    }

    func testRefusalAndMismatchedRequestIDFailClosed() async {
        RelayStubURLProtocol.handler = { _ in
            Self.response(body: Self.relayBody(
                requestID: self.requestID.uuidString.lowercased(),
                outcome: "refusal",
                suggestion: nil
            ))
        }
        await assertError(.refused) {
            try await self.makeService().suggestLabel(for: self.photo())
        }

        RelayStubURLProtocol.handler = { _ in
            Self.response(body: Self.relayBody(
                requestID: UUID().uuidString.lowercased(),
                outcome: "suggestion",
                suggestion: [
                    "proposed_name": "Flashlight",
                    "keywords": [],
                    "detail": NSNull(),
                    "confidence": NSNull()
                ]
            ))
        }
        await assertError(.malformedResponse) {
            try await self.makeService().suggestLabel(for: self.photo())
        }
    }

    func testRelayResponseMustBeBoundedJSONFromTheConfiguredEndpoint() async {
        let body = Self.relayBody(
            requestID: requestID.uuidString.lowercased(),
            outcome: "suggestion",
            suggestion: [
                "proposed_name": "Flashlight",
                "keywords": [],
                "detail": NSNull(),
                "confidence": NSNull()
            ]
        )

        RelayStubURLProtocol.handler = { _ in
            Self.response(contentType: "text/plain", body: body)
        }
        await assertError(.invalidResponse) {
            try await self.makeService().suggestLabel(for: self.photo())
        }

        RelayStubURLProtocol.handler = { _ in Self.response(status: 201, body: body) }
        await assertError(.unexpectedStatusCode(201)) {
            try await self.makeService().suggestLabel(for: self.photo())
        }

        RelayStubURLProtocol.handler = { _ in
            Self.response(url: URL(string: "https://redirected.witt.example/v1/thing-labels")!, body: body)
        }
        await assertError(.invalidResponse) {
            try await self.makeService().suggestLabel(for: self.photo())
        }

        RelayStubURLProtocol.handler = { _ in Self.response(body: body) }
        let sizeLimited = RelayThingPhotoLabelingService(
            configuration: .init(endpointURL: endpoint, maxResponseSize: body.count - 1),
            credentialProvider: { self.credential() },
            session: stubSession(),
            now: { self.now },
            requestIDProvider: { self.requestID }
        )
        await assertError(.invalidResponse) {
            try await sizeLimited.suggestLabel(for: self.photo())
        }
    }

    func testRelayResponseRejectsUnboundedSuggestionFields() async {
        RelayStubURLProtocol.handler = { _ in
            Self.response(body: Self.relayBody(
                requestID: self.requestID.uuidString.lowercased(),
                outcome: "suggestion",
                suggestion: [
                    "proposed_name": String(repeating: "a", count: 121),
                    "keywords": [],
                    "detail": NSNull(),
                    "confidence": NSNull()
                ]
            ))
        }
        await assertError(.malformedStructuredOutput) {
            try await self.makeService().suggestLabel(for: self.photo())
        }

        RelayStubURLProtocol.handler = { _ in
            Self.response(body: Self.relayBody(
                requestID: self.requestID.uuidString.lowercased(),
                outcome: "suggestion",
                suggestion: [
                    "proposed_name": "Cable",
                    "keywords": (0...12).map { "keyword-\($0)" },
                    "detail": NSNull(),
                    "confidence": NSNull()
                ]
            ))
        }
        await assertError(.malformedStructuredOutput) {
            try await self.makeService().suggestLabel(for: self.photo())
        }
    }

    func testHTTPSIsRequiredAndRemoteRelayIsNotRuntimeWired() async {
        let insecure = RelayThingPhotoLabelingService(
            configuration: .init(endpointURL: URL(string: "http://127.0.0.1:8080/label")!),
            credentialProvider: { self.credential() },
            session: stubSession(),
            now: { self.now }
        )
        await assertError(.serviceUnavailable) {
            try await insecure.suggestLabel(for: self.photo())
        }

        let queryEndpoint = RelayThingPhotoLabelingService(
            configuration: .init(endpointURL: URL(string: "https://ai.witt.example/v1/thing-labels?model=client-choice")!),
            credentialProvider: { self.credential() },
            session: stubSession(),
            now: { self.now }
        )
        await assertError(.serviceUnavailable) {
            try await queryEndpoint.suggestLabel(for: self.photo())
        }

        let runtimeDefault = ThingPhotoLabelingServices.appDefault(environment: [:])
        XCTAssertFalse(runtimeDefault is RelayThingPhotoLabelingService)
    }

    private func makeService(
        credential: ThingPhotoLabelingRelayCredential? = nil
    ) -> RelayThingPhotoLabelingService {
        let suppliedCredential = credential ?? self.credential()
        return RelayThingPhotoLabelingService(
            configuration: .init(endpointURL: endpoint),
            credentialProvider: { suppliedCredential },
            session: stubSession(),
            now: { self.now },
            requestIDProvider: { self.requestID }
        )
    }

    private func credential(
        scheme: ThingPhotoLabelingRelayCredential.Scheme = .bearer,
        token: String = "short-lived-token",
        issuedAt: Date? = nil,
        expiresAt: Date? = nil,
        proof: String? = nil
    ) -> ThingPhotoLabelingRelayCredential {
        .init(
            scheme: scheme,
            accessToken: token,
            issuedAt: issuedAt ?? now.addingTimeInterval(-30),
            expiresAt: expiresAt ?? now.addingTimeInterval(5 * 60),
            proof: proof
        )
    }

    private func photo() -> PhotoInput {
        .init(data: jpeg, contentType: "image/jpeg", dimensions: .init(width: 1, height: 1))
    }

    private func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RelayStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func assertError(
        _ expected: ThingPhotoLabelingError,
        operation: () async throws -> ThingLabelSuggestion
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(error as? ThingPhotoLabelingError, expected)
        }
    }

    private static func relayBody(
        requestID: String,
        outcome: String,
        suggestion: [String: Any]?
    ) -> Data {
        var body: [String: Any] = [
            "contract_version": "1",
            "request_id": requestID,
            "outcome": outcome
        ]
        body["suggestion"] = suggestion ?? NSNull()
        return try! JSONSerialization.data(withJSONObject: body)
    }

    private static func response(
        status: Int = 200,
        url: URL = URL(string: "https://ai.witt.example/v1/thing-labels")!,
        contentType: String = "application/json",
        body: Data
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": contentType]
            )!,
            body
        )
    }
}

final class ThingPhotoLabelingEvaluationTests: XCTestCase {
    func testRepresentativeFixturesExerciseEveryScoringDimension() throws {
        let fixture = try JSONDecoder().decode(
            EvaluationFixture.self,
            from: Data(contentsOf: fixtureURL)
        )
        XCTAssertEqual(fixture.schemaVersion, 1)
        XCTAssertGreaterThanOrEqual(fixture.cases.count, 9)

        var dimensions = Set<ThingPhotoLabelingEvaluationScore.Dimension>()
        for item in fixture.cases {
            let score = ThingPhotoLabelingEvaluator.score(
                item.observed.observation,
                latencyMilliseconds: item.observed.latencyMilliseconds,
                against: item.expected.evaluationCase(id: item.id)
            )
            dimensions.formUnion(score.values.keys)
            XCTAssertEqual(score.passed, item.expectedPass, item.id)
        }

        XCTAssertEqual(dimensions, Set(ThingPhotoLabelingEvaluationScore.Dimension.allCases))
    }

    func testNameAndKeywordScoringProvidesPartialCredit() {
        let evaluationCase = ThingPhotoLabelingEvaluationCase(
            id: "partial",
            expectedOutcome: .suggestion,
            acceptedNames: ["USB-C power adapter"],
            expectedKeywords: ["charger", "electronics"],
            maximumLatencyMilliseconds: 3_000
        )
        let score = ThingPhotoLabelingEvaluator.score(
            .suggestion(.init(proposedName: "Power adapter", keywords: ["charger"])),
            latencyMilliseconds: 1_000,
            against: evaluationCase
        )

        XCTAssertEqual(try XCTUnwrap(score.values[.naming]), 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(score.values[.keywords]), 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertFalse(score.passed)
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("AIFixtures/representative-evaluation.json")
    }
}

private struct EvaluationFixture: Decodable {
    let schemaVersion: Int
    let cases: [Case]

    struct Case: Decodable {
        let id: String
        let imageID: String?
        let scenario: String
        let expected: Expected
        let observed: Observed
        let expectedPass: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case imageID = "image_id"
            case scenario
            case expected
            case observed
            case expectedPass = "expected_pass"
        }
    }

    struct Expected: Decodable {
        let outcome: String
        let acceptedNames: [String]?
        let keywords: [String]?
        let detailTerms: [String]?
        let prohibitedTerms: [String]?
        let fallbackError: String?
        let maximumLatencyMilliseconds: Int

        func evaluationCase(id: String) -> ThingPhotoLabelingEvaluationCase {
            .init(
                id: id,
                expectedOutcome: .init(rawValue: outcome)!,
                acceptedNames: acceptedNames ?? [],
                expectedKeywords: keywords ?? [],
                expectedDetailTerms: detailTerms ?? [],
                prohibitedTerms: prohibitedTerms ?? [],
                expectedFallbackError: fallbackError.flatMap(ThingPhotoLabelingEvaluationFallback.init(rawValue:)),
                maximumLatencyMilliseconds: maximumLatencyMilliseconds
            )
        }

        enum CodingKeys: String, CodingKey {
            case outcome
            case acceptedNames = "accepted_names"
            case keywords
            case detailTerms = "detail_terms"
            case prohibitedTerms = "prohibited_terms"
            case fallbackError = "fallback_error"
            case maximumLatencyMilliseconds = "maximum_latency_ms"
        }
    }

    struct Observed: Decodable {
        let outcome: String
        let proposedName: String?
        let keywords: [String]?
        let detail: String?
        let confidence: Double?
        let fallbackError: String?
        let latencyMilliseconds: Int

        var observation: ThingPhotoLabelingEvaluationObservation {
            switch outcome {
            case "suggestion":
                return .suggestion(.init(
                    proposedName: proposedName ?? "",
                    keywords: keywords ?? [],
                    detail: detail,
                    confidence: confidence
                ))
            case "refusal":
                return .refusal
            default:
                return .manualFallback(fallbackErrorValue)
            }
        }

        private var fallbackErrorValue: ThingPhotoLabelingError {
            switch fallbackError {
            case "offline": .connectionUnavailable
            case "rateLimited": .rateLimited
            case "timedOut": .timedOut
            default: .serviceUnavailable
            }
        }

        enum CodingKeys: String, CodingKey {
            case outcome
            case proposedName = "proposed_name"
            case keywords
            case detail
            case confidence
            case fallbackError = "fallback_error"
            case latencyMilliseconds = "latency_ms"
        }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case cases
    }
}

private final class RelayStubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension Data {
    var relayJSONObject: [String: Any] {
        get throws {
            try XCTUnwrap(JSONSerialization.jsonObject(with: self) as? [String: Any])
        }
    }
}
