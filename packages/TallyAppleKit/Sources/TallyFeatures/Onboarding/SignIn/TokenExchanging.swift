import Foundation
import TallyCanvasAPI
import TallyDomain

/// Turns an authorization code into a `CanvasCredential` (security.md §3.2
/// item 6: `POST /login/oauth2/token`, no client secret, no
/// `replace_tokens`). Behind a protocol, per the implementation brief, so
/// `SignInHandoffViewModel` can be tested with a stub instead of the network
/// — this work package explicitly can't complete a real exchange until the
/// site and Team ID exist (GL-02).
public protocol TokenExchanging: Sendable {
    func exchange(code: String, verifier: String, redirectURI: URL) async throws -> CanvasCredential
}

/// Composes `TallyCanvasAPI`'s existing, Linux-tested `TokenEndpoint` (request
/// building + response parsing) with `any HTTPTransport` to actually perform
/// the exchange. Like `CanvasAccountSearch` (UX-WP-08), this depends only on
/// the transport protocol, never a concrete `URLSession` type — the
/// ephemeral, no-cache-or-cookies transport (SEC-08) is the
/// platform-adapters team's work package.
public struct CanvasTokenExchange: TokenExchanging {
    private let endpoint: TokenEndpoint
    private let transport: any HTTPTransport
    private let clock: any DateProviding

    public init(endpoint: TokenEndpoint, transport: any HTTPTransport, clock: any DateProviding = SystemDateProvider()) {
        self.endpoint = endpoint
        self.transport = transport
        self.clock = clock
    }

    public func exchange(code: String, verifier: String, redirectURI: URL) async throws -> CanvasCredential {
        let request = endpoint.request(for: .authorizationCode(code: code, verifier: verifier, redirectURI: redirectURI))
        let response = try await transport.send(request)
        // `previous: nil` — onboarding is always a first sign-in for this account, so the
        // `userMismatch` check (which only fires when re-authenticating an existing account)
        // never applies here.
        return try endpoint.credential(from: response, previous: nil, now: clock.now())
    }
}

/// The default until the composition root can supply a real `HTTPTransport`
/// (see `CanvasAccountSearch`'s identical seam in UX-WP-08). Fails honestly
/// instead of fabricating a token — the implementation brief's "never write
/// mock data into shipping code paths" applies doubly to credentials.
public struct UnavailableTokenExchange: TokenExchanging {
    public init() {}
    public func exchange(code: String, verifier: String, redirectURI: URL) async throws -> CanvasCredential {
        throw TokenExchangeError.transportNotConfigured
    }
}

public enum TokenExchangeError: Error, Sendable, Equatable {
    case transportNotConfigured
}
