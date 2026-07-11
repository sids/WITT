import Foundation
import Security

public struct QRToken: RawRepresentable, Hashable, Sendable, Codable {
    public static let byteCount = 16
    public static let encodedCharacterCount = 22

    public let rawValue: String

    public init?(rawValue: String) {
        guard Self.isCanonical(rawValue) else {
            return nil
        }

        self.rawValue = rawValue
    }

    public init(validating rawValue: String) throws {
        guard let token = QRToken(rawValue: rawValue) else {
            throw QRTokenError.invalidEncoding
        }

        self = token
    }

    public static func generate() throws -> QRToken {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

        guard status == errSecSuccess else {
            throw QRTokenError.randomGenerationFailed(status: status)
        }

        let encoded = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        guard let token = QRToken(rawValue: encoded) else {
            throw QRTokenError.invalidEncoding
        }

        return token
    }

    private static func isCanonical(_ value: String) -> Bool {
        guard value.utf8.count == encodedCharacterCount else {
            return false
        }

        guard value.utf8.allSatisfy({ byte in
            (byte >= 65 && byte <= 90)
                || (byte >= 97 && byte <= 122)
                || (byte >= 48 && byte <= 57)
                || byte == 45
                || byte == 95
        }) else {
            return false
        }

        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64.append("==")

        guard let decoded = Data(base64Encoded: base64), decoded.count == byteCount else {
            return false
        }

        let canonical = decoded.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return canonical == value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        do {
            try self.init(validating: container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a canonical 128-bit base64url QR token."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum QRTokenError: Error, Equatable, Sendable {
    case invalidEncoding
    case randomGenerationFailed(status: OSStatus)
}

extension QRToken: CustomStringConvertible {
    public var description: String { rawValue }
}
