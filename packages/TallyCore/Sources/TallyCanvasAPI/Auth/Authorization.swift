import Foundation
import TallyDomain

/// One pending Canvas sign-in (security.md §3.1): PKCE + a single-use `state`.
public struct AuthorizationRequest: Sendable, Equatable, Codable {
    public let host: String
    public let clientID: String
    public let redirectURI: URL
    public let state: String
    public let pkce: PKCEPair
    public let createdAt: Date
    public let forceLogin: Bool
    /// Sends the parent to Canvas's own login page rather than the school's student SSO
    /// (family-linking.md §4.3: `canvas_login=1`, forwarded by
    /// `oauth2_provider_controller.rb:108-117`; undocumented, hosted UNVERIFIED pending
    /// FAM-01). Only ever set on the parent sign-in path — always paired with
    /// `forceLogin: true` there, since a shared family device must never let a child's
    /// Safari session silently authorize the parent (family-linking.md §6.7).
    public let canvasLogin: Bool

    public static func begin(host: String, clientID: String, redirectURI: URL, now: Date,
                             forceLogin: Bool = false, canvasLogin: Bool = false,
                             using rng: inout some RandomNumberGenerator) -> AuthorizationRequest {
        AuthorizationRequest(host: host, clientID: clientID, redirectURI: redirectURI,
                             state: Base64URL.randomToken(byteCount: 32, using: &rng),
                             pkce: .make(using: &rng), createdAt: now, forceLogin: forceLogin, canvasLogin: canvasLogin)
    }

    /// LIVE-2 finding (`docs/pmo/reviews/live1-report.md`, "Least privilege"): a `require_scopes`
    /// developer key rejects an authorize request with no `scope` parameter (`invalid_scope`).
    /// `CanvasScopes.tally` is the one list this and `CanvasEndpointCatalogue` both read, so the
    /// request and the catalogue can never drift apart.
    public static let scope = CanvasScopes.tally.joined(separator: " ")

    /// `https://<host>/login/oauth2/auth?...` for `ASWebAuthenticationSession`.
    ///
    /// LIVE-FIX-1 (F3's sibling finding, `docs/pmo/reviews/live1-report.md`): `host` is expected
    /// to already be a bare, normalized hostname (`InstitutionHost.normalize`), but nothing here
    /// enforces that -- a caller that folds a port or any other invalid character into it makes
    /// `URLComponents.url` return `nil`. This used to force-unwrap that result and trap; it now
    /// throws `InstitutionHostError.invalid` instead, the same "a malformed host" vocabulary
    /// `InstitutionHost.normalize` already uses, so a programmer error here fails safely.
    public var url: URL {
        get throws(InstitutionHostError) {
            var c = URLComponents()
            c.scheme = "https"; c.host = host; c.path = "/login/oauth2/auth"
            c.queryItems = [
                .init(name: "client_id", value: clientID),
                .init(name: "response_type", value: "code"),
                .init(name: "redirect_uri", value: redirectURI.absoluteString),
                .init(name: "state", value: state),
                .init(name: "code_challenge", value: pkce.challenge),
                .init(name: "code_challenge_method", value: "S256"),
                .init(name: "scope", value: Self.scope),
            ] + (forceLogin ? [.init(name: "force_login", value: "1")] : [])
              + (canvasLogin ? [.init(name: "canvas_login", value: "1")] : [])
            guard let url = c.url else { throw .invalid }
            return url
        }
    }
}

public enum OAuthCallbackError: Error, Sendable, Equatable {
    case wrongRedirect, stateMismatch, expired, accessDenied, missingCode, providerError
}

public enum OAuthCallback {
    public static let requestTTL: Duration = .seconds(600) // Canvas caches the PKCE challenge for 10 min

    /// Validates the redirect Canvas sent back and returns the authorization code.
    public static func code(from callback: URL, for request: AuthorizationRequest, now: Date,
                            ttl: Duration = requestTTL) throws(OAuthCallbackError) -> String {
        guard let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == request.redirectURI.scheme?.lowercased(),
              parts.host?.lowercased() == request.redirectURI.host?.lowercased(),
              parts.path == request.redirectURI.path else { throw .wrongRedirect }
        let items = parts.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let state = value("state"), Self.constantTimeEquals(state, request.state) else { throw .stateMismatch }
        guard now.timeIntervalSince(request.createdAt) < ttl.timeInterval else { throw .expired }
        if let error = value("error") { throw error == "access_denied" ? .accessDenied : .providerError }
        guard let code = value("code"), !code.isEmpty else { throw .missingCode }
        return code
    }

    /// SEC1-07 / security.md §3.2 item 5 ("Compare `state` in constant time and consume it"): a
    /// bare `==` short-circuits at the first differing byte, which can leak how much of a guessed
    /// `state` matched through timing. `state` arrives on the callback URL, so in principle an
    /// attacker racing the redirect controls one side of this comparison; comparing every byte,
    /// unconditionally, removes that signal. Mismatched lengths are rejected without comparing
    /// bytes — the lengths themselves (both fixed, 43-character base64url tokens in practice) are
    /// not secret.
    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for i in 0..<a.count { difference |= a[i] ^ b[i] }
        return difference == 0
    }
}

/// Holds pending sign-ins so each `state` can be used exactly once.
public actor PendingAuthorizations {
    private var byState: [String: AuthorizationRequest] = [:]
    public init() {}
    public func insert(_ request: AuthorizationRequest) { byState[request.state] = request }
    /// Returns and removes the request for `state`; a second call returns nil.
    public func consume(state: String) -> AuthorizationRequest? { byState.removeValue(forKey: state) }
}
