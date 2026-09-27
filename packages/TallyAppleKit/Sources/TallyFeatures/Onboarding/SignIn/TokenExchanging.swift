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
    /// Conformances must throw only `TokenExchangeError` — never a raw
    /// `TallyCanvasAPI` error (`TransportError`/`TokenEndpointError`) — so
    /// `SignInHandoffViewModel` classifies failures by dynamically casting to
    /// a type this same module (`TallyFeatures`) declares, not one crossing in
    /// from a different module through an `async` protocol-existential call.
    /// CI (run 36336610429) showed a `TransportError` thrown that way landing
    /// in the generic bucket instead of `.networkFailure` on the Xcode 26.6/27
    /// toolchains (not reproducible in an equivalent multi-module Linux Swift
    /// 6.4 harness); owning the error vocabulary at the protocol boundary
    /// removes the question entirely. (Left as a plain `async throws`, not
    /// typed throws: this codebase has no existing precedent for typed
    /// throws on a *protocol requirement* called through an existential, and
    /// this toolchain has already shown one unrelated compiler rough edge —
    /// not the moment to add a second, less-trodden feature combination.)
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
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            // Every `TransportError` case (offline, timedOut, cancelled, other) means
            // the request never reached Canvas: ux-ui.md §3.2.2's "Network failure" row.
            throw TokenExchangeError.networkFailure
        }
        do {
            // `previous: nil` — onboarding is always a first sign-in for this account, so
            // the `userMismatch` check (which only fires when re-authenticating an existing
            // account) never applies here.
            return try endpoint.credential(from: response, previous: nil, now: clock.now())
        } catch {
            throw TokenExchangeError.rejected
        }
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
    /// No live `HTTPTransport` is wired in yet (`UnavailableTokenExchange`).
    case transportNotConfigured
    /// The request never reached Canvas (any `TransportError` case).
    case networkFailure
    /// Canvas responded, but the response was rejected or malformed
    /// (any `TokenEndpointError` case).
    case rejected
}
