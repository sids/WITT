import Foundation

public struct WITTQRCodeURL: Hashable, Sendable, Codable {
    public static let scheme = "witt"
    public static let host = "qr"
    public static let version = "v1"

    public let token: QRToken

    public init(token: QRToken) throws {
        guard QRToken.isCanonicalGeneratedToken(token.rawValue) else {
            throw WITTQRCodeURLError.invalidToken
        }
        self.token = token
    }

    public init(_ string: String) throws {
        guard let components = URLComponents(string: string) else {
            throw WITTQRCodeURLError.invalidFormat
        }

        guard components.scheme == Self.scheme else {
            throw WITTQRCodeURLError.invalidScheme
        }

        guard components.host == Self.host,
              components.user == nil,
              components.password == nil,
              components.port == nil else {
            throw WITTQRCodeURLError.invalidHost
        }

        guard components.query == nil else {
            throw WITTQRCodeURLError.queryNotAllowed
        }

        guard components.fragment == nil else {
            throw WITTQRCodeURLError.fragmentNotAllowed
        }

        let pathComponents = components.percentEncodedPath
            .split(separator: "/", omittingEmptySubsequences: false)
        guard pathComponents.count == 3,
              pathComponents[0].isEmpty else {
            throw WITTQRCodeURLError.invalidPath
        }

        guard pathComponents[1] == Self.version else {
            throw WITTQRCodeURLError.invalidVersion
        }

        let tokenString = String(pathComponents[2])

        guard QRToken.isCanonicalGeneratedToken(tokenString),
              let parsedToken = QRToken(rawValue: tokenString) else {
            throw WITTQRCodeURLError.invalidToken
        }
        token = parsedToken

        guard string == absoluteString else {
            throw WITTQRCodeURLError.invalidFormat
        }
    }

    public init(url: URL) throws {
        try self.init(url.absoluteString)
    }

    private enum CodingKeys: String, CodingKey {
        case token
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedToken = try container.decode(QRToken.self, forKey: .token)
        do {
            try self.init(token: decodedToken)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .token,
                in: container,
                debugDescription: "Expected a canonical generated WITT QR token."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(token, forKey: .token)
    }

    public var absoluteString: String {
        "\(Self.scheme)://\(Self.host)/\(Self.version)/\(token.rawValue)"
    }

    public var url: URL {
        // Every WITTQRCodeURL initializer enforces a canonical generated token.
        URL(string: absoluteString)!
    }
}

public enum WITTQRCodeURLError: Error, Equatable, Sendable {
    case invalidFormat
    case invalidScheme
    case invalidHost
    case invalidVersion
    case invalidPath
    case invalidToken
    case queryNotAllowed
    case fragmentNotAllowed
}

extension WITTQRCodeURL: CustomStringConvertible {
    public var description: String { absoluteString }
}
