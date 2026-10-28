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
    /// PAY-10 (M3-B2): Canvas rejected the client itself (`invalid_client`, RFC 6749 §5.2): the
    /// school turned off or deleted Tally's developer key. Not the student's sign-in.
    case invalidClient
    /// SEC1-07 / security.md §3.2 item 6 ("Check `token_type == Bearer`"): Canvas named a
    /// `token_type` other than `Bearer`. Tally always sends the token as a bearer credential
    /// (`revokeRequest`, `CanvasClient`'s `Authorization` header), so a different type means the
    /// token can't be used the way this client assumes.
    case unsupportedTokenType
}

/// `POST /login/oauth2/token` for a public (PKCE) client: never a client secret,
/// never `replace_tokens` (security.md WP-SEC-02). `DELETE` revokes on sign-out.
public struct TokenEndpoint: Sendable {
    public let host: String
    public let clientID: String
    public init(host: String, clientID: String) { self.host = host; self.clientID = clientID }

    /// LIVE-FIX-1 (F3's sibling finding, `docs/pmo/reviews/live1-report.md`): `host` is expected
    /// to already be a bare, normalized hostname (`InstitutionHost.normalize`), but nothing here
    /// enforced that -- a host with a character `URL(string:)` can't place in an authority (a
    /// space, say) made this force-unwrap trap. It now throws `InstitutionHostError.invalid`
    /// instead, the same vocabulary `AuthorizationRequest.url` uses for the identical situation.
    private var url: URL {
        get throws(InstitutionHostError) {
            guard let url = URL(string: "https://\(host)/login/oauth2/token") else { throw .invalid }
            return url
        }
    }

    public func request(for grant: TokenGrant) throws(InstitutionHostError) -> HTTPRequest {
        var fields = [("client_id", clientID)]
        switch grant {
        case let .authorizationCode(code, verifier, redirectURI):
            fields += [("grant_type", "authorization_code"), ("code", code),
                       ("code_verifier", verifier), ("redirect_uri", redirectURI.absoluteString)]
        case let .refresh(refreshToken):
            fields += [("grant_type", "refresh_token"), ("refresh_token", refreshToken)]
        }
        let body = fields.map { "\(Self.formEncode($0.0))=\(Self.formEncode($0.1))" }.joined(separator: "&")
        return HTTPRequest(method: .post, url: try url,
                           headers: HTTPHeaders(["Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"]),
                           body: Data(body.utf8))
    }

    public func revokeRequest(for credential: CanvasCredential) throws(InstitutionHostError) -> HTTPRequest {
        HTTPRequest(method: .delete, url: try url, headers: HTTPHeaders(["Authorization": "Bearer \(credential.accessToken)"]))
    }

    /// Turns a token response into a credential. A rotated refresh token replaces the old one;
    /// if Canvas returns none (confidential behaviour), the existing one is kept.
    public func credential(from response: HTTPResponse, previous: CanvasCredential?, now: Date) throws(TokenEndpointError) -> CanvasCredential {
        guard (200..<300).contains(response.status) else {
            let error = try? JSONDecoder().decode(OAuthErrorBody.self, from: response.body)
            if error?.error == "invalid_grant" { throw .invalidGrant }
            if error?.error == "invalid_client" { throw .invalidClient }
            throw .rejected(status: response.status)
        }
        guard let body = try? JSONDecoder().decode(TokenBody.self, from: response.body) else { throw .malformed }
        // SEC2-11: `previous` only has a say here when it is THIS SAME Canvas host's own earlier
        // credential. A stale credential left over from another school (for example a SEC1-01
        // delete-failure residual) must never borrow its refresh token into a different host's
        // sign-in, and must never block it with `.userMismatch` either.
        let continuity = previous?.host == host ? previous : nil
        guard let refresh = body.refreshToken ?? continuity?.refreshToken else { throw .malformed }
        // SEC1-07: Canvas's fixtures and some live responses omit `token_type` entirely, so only
        // a type Canvas actually names, and that isn't Bearer, is rejected.
        if let tokenType = body.tokenType, tokenType.caseInsensitiveCompare("bearer") != .orderedSame {
            throw .unsupportedTokenType
        }
        let userID = body.user.id.value
        if let continuity, continuity.userID != userID { throw .userMismatch }
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
    let tokenType: String?
    let refreshToken: String?
    let expiresIn: Int?
    let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", tokenType = "token_type",
             refreshToken = "refresh_token", expiresIn = "expires_in", user
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
