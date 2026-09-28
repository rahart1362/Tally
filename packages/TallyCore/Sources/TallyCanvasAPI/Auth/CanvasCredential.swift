import Foundation

/// Tokens for one Canvas account. Stored only in the Keychain
/// (`AfterFirstUnlockThisDeviceOnly`, ADR 0001). Never printed: see `description`.
public struct CanvasCredential: Codable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let host: String
    public let userID: String
    public var accessToken: String
    public var refreshToken: String
    public var accessTokenExpiresAt: Date

    public init(host: String, userID: String, accessToken: String, refreshToken: String, accessTokenExpiresAt: Date) {
        self.host = host; self.userID = userID; self.accessToken = accessToken
        self.refreshToken = refreshToken; self.accessTokenExpiresAt = accessTokenExpiresAt
    }

    /// True while the access token has at least `leeway` of life left.
    public func isAccessTokenUsable(now: Date, leeway: Duration = .seconds(60)) -> Bool {
        accessTokenExpiresAt.timeIntervalSince(now) > leeway.timeInterval
    }

    public var description: String { "CanvasCredential(host: \(host), user: \(userID), tokens: <redacted>)" }
    public var debugDescription: String { description }
}
