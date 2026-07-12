import XCTest
@testable import witt

final class QRCodeTests: XCTestCase {
    private let canonicalToken = "AAAAAAAAAAAAAAAAAAAAAA"

    func testGeneratedTokensAreCanonicalAndDistinct() throws {
        let first = try QRToken.generate()
        let second = try QRToken.generate()

        XCTAssertEqual(first.rawValue.utf8.count, QRToken.encodedCharacterCount)
        XCTAssertEqual(QRToken(rawValue: first.rawValue), first)
        XCTAssertNotEqual(first, second)
    }

    func testTokenAcceptsAnyNonEmptyPayloadAndPreservesExactIdentity() throws {
        let payload = "  https://vendor.example/item?id=A+B#part  "

        XCTAssertEqual(try XCTUnwrap(QRToken(rawValue: payload)).rawValue, payload)
        XCTAssertNil(QRToken(rawValue: ""))
    }

    func testQRCodeURLRoundTripsExactly() throws {
        let token = try XCTUnwrap(QRToken(rawValue: canonicalToken))
        let value = try WITTQRCodeURL(token: token)

        XCTAssertEqual(value.absoluteString, "witt://qr/v1/AAAAAAAAAAAAAAAAAAAAAA")
        XCTAssertEqual(try WITTQRCodeURL(value.absoluteString), value)
        XCTAssertEqual(try WITTQRCodeURL(url: value.url), value)
    }

    func testScannedGeneratedURLMapsToLegacyRawToken() throws {
        let token = try XCTUnwrap(QRToken(rawValue: canonicalToken))

        XCTAssertEqual(
            QRToken(scannedPayload: try WITTQRCodeURL(token: token).absoluteString),
            token
        )
    }

    func testQRCodeURLConstructionRejectsArbitraryPayloadWithoutTrapping() throws {
        let arbitrary = try XCTUnwrap(QRToken(rawValue: "vendor inventory #42"))

        XCTAssertThrowsError(try WITTQRCodeURL(token: arbitrary)) { error in
            XCTAssertEqual(error as? WITTQRCodeURLError, .invalidToken)
        }
    }

    func testQRCodeURLDecodingCannotBypassGeneratedTokenValidation() {
        let encoded = Data(#"{"token":"vendor inventory #42"}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(WITTQRCodeURL.self, from: encoded)) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("Expected data-corrupted decoding error, got \(error)")
            }
        }
    }

    func testQRCodeURLRejectsMalformedComponents() {
        assertURL("https://qr/v1/\(canonicalToken)", throws: .invalidScheme)
        assertURL("witt://other/v1/\(canonicalToken)", throws: .invalidHost)
        assertURL("witt://qr/v2/\(canonicalToken)", throws: .invalidVersion)
        assertURL("witt://qr/v1/not-a-token", throws: .invalidToken)
        assertURL("witt://qr/v1/\(canonicalToken)/extra", throws: .invalidPath)
        assertURL("witt://qr/v1/\(canonicalToken)?source=test", throws: .queryNotAllowed)
        assertURL("witt://qr/v1/\(canonicalToken)#fragment", throws: .fragmentNotAllowed)
    }

    private func assertURL(
        _ string: String,
        throws expectedError: WITTQRCodeURLError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try WITTQRCodeURL(string), file: file, line: line) { error in
            XCTAssertEqual(error as? WITTQRCodeURLError, expectedError, file: file, line: line)
        }
    }
}
