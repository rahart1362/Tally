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

    /// `https://<host>/login/oauth2/auth?...` for `ASWebAuthenticationSession`.
    public var url: URL {
        var c = URLComponents()
        c.scheme = "https"; c.host = host; c.path = "/login/oauth2/auth"
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirectURI.absoluteString),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ] + (forceLogin ? [.init(name: "force_login", value: "1")] : [])
          + (canvasLogin ? [.init(name: "canvas_login", value: "1")] : [])
        return c.url!
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
        guard value("state") == request.state else { throw .stateMismatch }
        guard now.timeIntervalSince(request.createdAt) < ttl.timeInterval else { throw .expired }
        if let error = value("error") { throw error == "access_denied" ? .accessDenied : .providerError }
        guard let code = value("code"), !code.isEmpty else { throw .missingCode }
        return code
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
