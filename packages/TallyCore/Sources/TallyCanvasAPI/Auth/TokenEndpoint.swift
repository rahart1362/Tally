import Foundation

public enum TokenGrant: Sendable, Equatable {
    case authorizationCode(code: String, verifier: String, redirectURI: URL)
    case refresh(refreshToken: String)
}

public enum TokenEndpointError: Error, Sendable, Equatable {
    /// Refresh or code no longer valid (2-hour window lapsed, revoked, rotated elsewhere): re-sign-in.
    case invalidGrant
    case rejected(status: Int)
    case malformed
    /// The token belongs to a different Canvas user than the stored account.
    case userMismatch
}

/// `POST /login/oauth2/token` for a public (PKCE) client: never a client secret,
/// never `replace_tokens` (security.md WP-SEC-02). `DELETE` revokes on sign-out.
public struct TokenEndpoint: Sendable {
    public let host: String
    public let clientID: String
    public init(host: String, clientID: String) { self.host = host; self.clientID = clientID }

    private var url: URL {
        URL(string: "https://\(host)/login/oauth2/token")! // swiftlint:disable:this force_unwrapping — https scheme + a validated host is always a well-formed URL
    }

    public func request(for grant: TokenGrant) -> HTTPRequest {
        var fields = [("client_id", clientID)]
        switch grant {
        case let .authorizationCode(code, verifier, redirectURI):
            fields += [("grant_type", "authorization_code"), ("code", code),
                       ("code_verifier", verifier), ("redirect_uri", redirectURI.absoluteString)]
        case let .refresh(refreshToken):
            fields += [("grant_type", "refresh_token"), ("refresh_token", refreshToken)]
        }
        let body = fields.map { "\(Self.formEncode($0.0))=\(Self.formEncode($0.1))" }.joined(separator: "&")
        return HTTPRequest(method: .post, url: url,
                           headers: HTTPHeaders(["Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"]),
                           body: Data(body.utf8))
    }

    public func revokeRequest(for credential: CanvasCredential) -> HTTPRequest {
        HTTPRequest(method: .delete, url: url, headers: HTTPHeaders(["Authorization": "Bearer \(credential.accessToken)"]))
    }

    /// Turns a token response into a credential. A rotated refresh token replaces the old one;
    /// if Canvas returns none (confidential behaviour), the existing one is kept.
    public func credential(from response: HTTPResponse, previous: CanvasCredential?, now: Date) throws(TokenEndpointError) -> CanvasCredential {
        guard (200..<300).contains(response.status) else {
            let error = try? JSONDecoder().decode(OAuthErrorBody.self, from: response.body)
            if error?.error == "invalid_grant" { throw .invalidGrant }
            throw .rejected(status: response.status)
        }
        guard let body = try? JSONDecoder().decode(TokenBody.self, from: response.body),
              let refresh = body.refreshToken ?? previous?.refreshToken else { throw .malformed }
        let userID = body.user.id.value
        if let previous, previous.userID != userID { throw .userMismatch }
        return CanvasCredential(host: host, userID: userID, accessToken: body.accessToken, refreshToken: refresh,
                                accessTokenExpiresAt: now.addingTimeInterval(TimeInterval(body.expiresIn ?? 3600)))
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private struct OAuthErrorBody: Decodable { let error: String }

private struct TokenBody: Decodable {
    struct User: Decodable { let id: FlexibleID }
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in", user
    }
}

/// Canvas returns `user.id` as a number here (string with canvas-string-ids elsewhere).
struct FlexibleID: Decodable {
    let value: String
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s } else { value = String(try c.decode(Int64.self)) }
    }
}
