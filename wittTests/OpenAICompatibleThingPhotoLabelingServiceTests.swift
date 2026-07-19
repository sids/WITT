import Foundation
import XCTest
@testable import witt

final class OpenAICompatibleThingPhotoLabelingServiceTests: XCTestCase {
    private let endpoint = URL(string: "https://relay.example.test/v1/responses")!
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testRequestUsesResponsesContractAndBearerToken() async throws {
        let request = try makeService().makeRequest(for: photo(), bearerToken: "secret-token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")

        let body = try XCTUnwrap(request.httpBody).jsonObject
        XCTAssertEqual(body["model"] as? String, "vision-model")
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertNotNil(body["max_output_tokens"] as? Int)

        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.map { $0["role"] as? String }, ["system", "user"])
        let userContent = try XCTUnwrap(input[1]["content"] as? [[String: Any]])
        XCTAssertNotNil(userContent.first { $0["type"] as? String == "input_text" })
        let imageURL = try XCTUnwrap(
            userContent.first { $0["type"] as? String == "input_image" }?["image_url"] as? String
        )
        XCTAssertTrue(imageURL.hasPrefix("data:image/jpeg;base64,"))

        let text = try XCTUnwrap(body["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["strict"] as? Bool, true)
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertEqual(Set(properties.keys), ["proposed_name", "keywords", "detail", "confidence"])
    }

    func testSuccessfulResponseIsNormalized() async throws {
        StubURLProtocol.handler = { _ in
            Self.successResponse(
                proposedName: "  USB-C   Power Adapter ",
                keywords: ["  charger ", "CHARGER", " power   adapter ", ""],
                detail: "  White   65 W  ",
                confidence: 0.82
            )
        }

        let suggestion = try await makeService().suggestLabel(for: photo())

        XCTAssertEqual(suggestion.proposedName, "USB-C Power Adapter")
        XCTAssertEqual(suggestion.keywords, ["charger", "power adapter"])
        XCTAssertEqual(suggestion.detail, "White 65 W")
        XCTAssertEqual(suggestion.confidence, 0.82)
    }

    func testRequestOmitsAuthorizationWhenTokenIsAbsent() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return Self.successResponse()
        }

        _ = try await makeService(token: nil).suggestLabel(for: photo())
    }

    func testRequestRejectsControlCharactersInBearerToken() async {
        await assertError(.serviceUnavailable) {
            try await self.makeService(token: "secret\nInjected: value").suggestLabel(
                for: self.photo()
            )
        }
    }

    func testRejectsUnsupportedContentTypeWithoutNetworkRequest() async {
        await assertError(.unsupportedContentType) {
            try await self.makeService().suggestLabel(
                for: PhotoInput(data: self.jpeg, contentType: "image/png")
            )
        }
    }

    func testRejectsInvalidJPEGAndDimensionsWithoutNetworkRequest() async {
        await assertError(.invalidPhoto) {
            try await self.makeService().suggestLabel(
                for: PhotoInput(data: Data([0x01]), contentType: "image/jpeg")
            )
        }
        await assertError(.invalidPhoto) {
            try await self.makeService().suggestLabel(
                for: self.photo(dimensions: .init(width: 0, height: 100))
            )
        }
    }

    func testRejectsPhotoOverConfiguredLimit() async {
        await assertError(.photoTooLarge) {
            try await self.makeService(maxPhotoSize: 3).suggestLabel(for: self.photo())
        }
    }

    func testMapsAuthenticationRateLimitAndServerStatuses() async {
        for (status, expected) in [
            (401, ThingPhotoLabelingError.unauthorized),
            (403, .forbidden),
            (429, .rateLimited),
            (503, .serverError)
        ] {
            StubURLProtocol.handler = { _ in Self.response(status: status, body: Data("private body".utf8)) }
            await assertError(expected) {
                try await self.makeService().suggestLabel(for: self.photo())
            }
        }
    }

    func testMapsRequestTimeout() async {
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }

        await assertError(.timedOut) {
            try await self.makeService().suggestLabel(for: self.photo())
        }
    }

    func testRejectsMalformedOuterAndStructuredJSON() async {
        StubURLProtocol.handler = { _ in Self.response(body: Data("not-json".utf8)) }
        await assertError(.malformedResponse) {
            try await self.makeService().suggestLabel(for: self.photo())
        }

        StubURLProtocol.handler = { _ in Self.response(body: Self.envelope(outputText: "not-json")) }
        await assertError(.malformedStructuredOutput) {
            try await self.makeService().suggestLabel(for: self.photo())
        }
    }

    func testRejectsIncompleteRefusalAndMissingOutput() async {
        StubURLProtocol.handler = { _ in
            Self.response(body: try JSONSerialization.data(withJSONObject: ["status": "incomplete", "output": []]))
        }
        await assertError(.incompleteResponse) {
            try await self.makeService().suggestLabel(for: self.photo())
        }

        StubURLProtocol.handler = { _ in
            let body: [String: Any] = [
                "status": "completed",
                "output": [["type": "message", "content": [["type": "refusal", "refusal": "No"]]]]
            ]
            return Self.response(body: try JSONSerialization.data(withJSONObject: body))
        }
        await assertError(.refused) {
            try await self.makeService().suggestLabel(for: self.photo())
        }

        StubURLProtocol.handler = { _ in Self.response(body: Data(#"{"status":"completed","output":[]}"#.utf8)) }
        await assertError(.missingOutput) {
            try await self.makeService().suggestLabel(for: self.photo())
        }
    }

    func testRejectsFailedAndUnknownResponseStates() async {
        StubURLProtocol.handler = { _ in
            Self.response(body: Data(#"{"status":"failed","output":[]}"#.utf8))
        }
        await assertError(.serviceUnavailable) {
            try await self.makeService().suggestLabel(for: self.photo())
        }

        StubURLProtocol.handler = { _ in
            Self.response(body: Data(#"{"status":"mystery","output":[]}"#.utf8))
        }
        await assertError(.malformedResponse) {
            try await self.makeService().suggestLabel(for: self.photo())
        }
    }

    func testRejectsEmptyNameAndOutOfRangeConfidence() async {
        StubURLProtocol.handler = { _ in Self.successResponse(proposedName: " \n ") }
        await assertError(.emptyName) {
            try await self.makeService().suggestLabel(for: self.photo())
        }

        StubURLProtocol.handler = { _ in Self.successResponse(confidence: 1.1) }
        await assertError(.invalidConfidence) {
            try await self.makeService().suggestLabel(for: self.photo())
        }
    }

    func testCancellationFromTokenProviderIsPreserved() async {
        let configuration = OpenAICompatibleThingPhotoLabelingConfiguration(
            endpointURL: endpoint,
            model: "vision-model"
        )
        let service = OpenAICompatibleThingPhotoLabelingService(
            configuration: configuration,
            bearerTokenProvider: {
                try await Task.sleep(for: .seconds(30))
                return nil
            },
            session: stubSession()
        )
        let task = Task { try await service.suggestLabel(for: photo()) }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testFactoryBuildsRemoteServiceForHTTPSAndLoopbackHTTP() {
        let https = ThingPhotoLabelingServices.appDefault(environment: [
            "WITT_AI_RESPONSES_URL": endpoint.absoluteString,
            "WITT_AI_MODEL": "vision-model",
            "WITT_AI_BEARER_TOKEN": "token"
        ])
        let loopback = ThingPhotoLabelingServices.appDefault(environment: [
            "WITT_AI_RESPONSES_URL": "http://127.0.0.1:8080/responses",
            "WITT_AI_MODEL": "local-model"
        ])

        XCTAssertTrue(https is OpenAICompatibleThingPhotoLabelingService)
        XCTAssertTrue(loopback is OpenAICompatibleThingPhotoLabelingService)
    }

    func testFactoryUsesDebugFallbackOnlyWhenConfigurationIsAbsent() {
        let missing = ThingPhotoLabelingServices.appDefault(environment: [:])
        let insecure = ThingPhotoLabelingServices.appDefault(environment: [
            "WITT_AI_RESPONSES_URL": "http://example.com/responses",
            "WITT_AI_MODEL": "vision-model"
        ])

        #if DEBUG
        XCTAssertTrue(missing is DebugThingPhotoLabelingService)
        #else
        XCTAssertTrue(missing is UnavailableThingPhotoLabelingService)
        #endif
        XCTAssertTrue(insecure is UnavailableThingPhotoLabelingService)
    }

    func testUnavailableServiceReturnsHonestFailure() async {
        await assertError(.serviceUnavailable) {
            try await UnavailableThingPhotoLabelingService().suggestLabel(for: self.photo())
        }
    }

    private func makeService(
        token: String? = nil,
        maxPhotoSize: Int = 1_024
    ) -> OpenAICompatibleThingPhotoLabelingService {
        OpenAICompatibleThingPhotoLabelingService(
            configuration: .init(
                endpointURL: endpoint,
                model: "vision-model",
                timeout: 2,
                maxPhotoSize: maxPhotoSize
            ),
            bearerTokenProvider: { token },
            session: stubSession()
        )
    }

    private func photo(dimensions: PhotoInput.Dimensions? = .init(width: 1, height: 1)) -> PhotoInput {
        PhotoInput(data: jpeg, contentType: "image/jpeg", dimensions: dimensions)
    }

    private func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
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

    private static func successResponse(
        proposedName: String = "Flashlight",
        keywords: [String] = ["light"],
        detail: String? = nil,
        confidence: Double? = nil
    ) -> (HTTPURLResponse, Data) {
        var suggestion: [String: Any] = [
            "proposed_name": proposedName,
            "keywords": keywords,
            "detail": detail ?? NSNull(),
            "confidence": confidence ?? NSNull()
        ]
        if detail == nil { suggestion["detail"] = NSNull() }
        if confidence == nil { suggestion["confidence"] = NSNull() }
        let structured = try! JSONSerialization.data(withJSONObject: suggestion)
        return response(body: envelope(outputText: String(decoding: structured, as: UTF8.self)))
    }

    private static func envelope(outputText: String) -> Data {
        let body: [String: Any] = [
            "status": "completed",
            "output": [[
                "type": "message",
                "content": [["type": "output_text", "text": outputText]]
            ]]
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    private static func response(status: Int = 200, body: Data) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: URL(string: "https://relay.example.test/v1/responses")!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            body
        )
    }
}

private final class StubURLProtocol: URLProtocol {
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
    var jsonObject: [String: Any] {
        get throws {
            try XCTUnwrap(JSONSerialization.jsonObject(with: self) as? [String: Any])
        }
    }
}
