import Foundation
import TallyCanvasAPI
import TallyDomain

/// Outcome mapping (ux-ui.md §3.2.2): cancel is never an error; the other
/// failures each get their own message.
public enum SignInFailure: Sendable, Equatable {
    /// `error=access_denied` on the Canvas approval page.
    case accessDenied
    /// A `TokenExchangeError.networkFailure` reaching the school's host
    /// during the token-exchange step.
    case networkFailure
    /// Anything else: a malformed callback, a rejected token exchange, or
    /// `WebAuthError.failedToStart`/`.other`. Real-Canvas validation of the
    /// finer-grained cases (e.g. `invalid_client`) is GL-05/WP-SEC-17,
    /// UNVERIFIED until then.
    case other
}

public enum SignInPhase: Sendable, Equatable {
    case idle
    /// The web sheet is up, or the token exchange that follows a successful
    /// callback is in flight.
    case presenting
    /// "Sign-in cancelled. Nothing was shared." — a transient status, not an alert.
    case cancelledNotice
    case failed(SignInFailure)
}

/// Drives the sign-in hand-off screen (UX-WP-09, F02/SEC-05). The flow is
/// exactly ADR 0001 step 5 / security.md §3.2: `AuthorizationRequest.begin`
/// → present → `OAuthCallback.code(from:)` → `TokenEndpoint` exchange →
/// credential. Every dependency is a protocol (`WebAuthPresenting`,
/// `TokenExchanging`), so this is testable with a stub presenter and a
/// stub token endpoint — real sign-in can't complete until the site and
/// Team ID exist (GL-02), so that is exactly how this ships today.
///
/// A single local `AuthorizationRequest`, not `PendingAuthorizations`: that
/// actor exists for a callback that can arrive on a *fresh* app launch (a
/// custom URL scheme reopening the app). `ASWebAuthenticationSession`'s
/// `.https(host:path:)` callback is delivered straight to this session's own
/// completion handler by the system, never through the app's own URL-open
/// path, so there is only ever one in-flight request for this view model to
/// track — `PendingAuthorizations`'s multi-entry `state` table isn't needed here.
/// Explicitly `@MainActor`, with an explicit `nonisolated deinit` (plan 06 A2): see that deinit.
@MainActor
@Observable
public final class SignInHandoffViewModel {
    /// Explicit and nonisolated (plan 06 A2). In this default-`MainActor` module the compiler makes an
    /// implicit deinit main-actor isolated, `@MainActor` on the class or not, and an isolated deinit
    /// (`swift_task_deinitOnExecutor`) aborts iOS 26.0-26.3 runtimes when it runs nested or in a
    /// task-local scope (swiftlang/swift#88036; the floor abort in CI run 36390172728). CI's `nm`
    /// gate keeps isolated deinits out of every shipping binary.
    nonisolated deinit {}

    public let host: String
    public let schoolDisplayName: String
    public private(set) var phase: SignInPhase = .idle
    /// The "Private sign-in (shared device)" setting (security.md §3.2 item 4).
    /// No Settings UI exists yet to surface this (Settings is a later
    /// milestone); the toggle and the behaviour it drives both ship now.
    public var privateSignIn: Bool

    private let clientID: String
    private let redirectURI: URL
    private let presenter: any WebAuthPresenting
    private let tokenExchange: any TokenExchanging
    private let clock: any DateProviding
    /// Called once, after a real credential is obtained. The composition
    /// root/`RootView` decides what happens next (there is no Dashboard to
    /// route to yet — that is the app-core team's work); this view model
    /// only reports the fact of success.
    private let onSuccess: (CanvasCredential) -> Void

    public init(
        host: String,
        clientID: String,
        schoolDisplayName: String,
        presenter: any WebAuthPresenting,
        tokenExchange: any TokenExchanging,
        redirectURI: URL,
        clock: any DateProviding = SystemDateProvider(),
        privateSignIn: Bool = false,
        onSuccess: @escaping (CanvasCredential) -> Void
    ) {
        self.host = host
        self.clientID = clientID
        self.schoolDisplayName = schoolDisplayName
        self.presenter = presenter
        self.tokenExchange = tokenExchange
        self.redirectURI = redirectURI
        self.clock = clock
        self.privateSignIn = privateSignIn
        self.onSuccess = onSuccess
    }

    /// `https://<TallyOrgDomain>/oauth/callback` — the one https redirect
    /// registered with every institution key (security.md §3.2 item 4: "Register
    /// only this https redirect in every institution key").
    public static var defaultRedirectURI: URL {
        URL(string: "https://\(TallyOrgDomainInfo.current)/oauth/callback")! // swiftlint:disable:this force_unwrapping — https scheme + a fixed, valid domain is always a well-formed URL
    }

    /// "Continue to <School>" (ux-ui.md §3.2 stage 4) / "Try Again" from any failed state.
    public func continueSigningIn() async {
        phase = .presenting
        // A fresh, local, concretely-typed generator each call (matching how
        // `TallyCanvasAPI`'s own tests build one: `var rng = ...; using: &rng`)
        // rather than a stored `any RandomNumberGenerator` property boxed across
        // calls — the latter, combined with `AuthorizationRequest.begin`'s
        // `inout some RandomNumberGenerator` parameter inside this async
        // main-actor method, crashed Xcode 26.6's swift-frontend during IRGen
        // (confirmed via CI: "While emitting IR SIL function
        // ...SignInHandoffViewModelC015continueSigningD0..."). Determinism
        // isn't needed here: `state`/PKCE values are never asserted against a
        // fixed expectation, only round-tripped.
        var rng = SystemRandomNumberGenerator()
        let request = AuthorizationRequest.begin(host: host, clientID: clientID, redirectURI: redirectURI,
                                                 now: clock.now(), using: &rng)
        do {
            let callbackURL = try await presenter.authenticate(
                url: request.url, callbackHost: redirectURI.host ?? host, callbackPath: redirectURI.path,
                ephemeral: privateSignIn
            )
            let code = try OAuthCallback.code(from: callbackURL, for: request, now: clock.now())
            let credential = try await tokenExchange.exchange(
                code: code, verifier: request.pkce.verifier, redirectURI: redirectURI
            )
            phase = .idle
            onSuccess(credential)
        } catch {
            // A single catch-all with an internal switch over the same `any Error`
            // value. `TokenExchanging.exchange` throws only `TokenExchangeError`
            // (see its doc comment: CI run 36336610429 showed a raw `TransportError`
            // failing to match `case is TransportError` here on the Xcode 26.6/27
            // toolchains — not reproducible in an equivalent multi-module Linux
            // Swift 6.4 harness — so that classification now happens inside
            // `CanvasTokenExchange` instead, in the same module as this switch).
            switch error {
            case let webAuthError as WebAuthError:
                // "Cancel is not an error" (ux-ui.md §3.2.2) is specifically about the
                // student dismissing the sign-in sheet, never about a transport-level
                // cancellation — TokenExchangeError.networkFailure covers that case below.
                phase = (webAuthError == .cancelled) ? .cancelledNotice : .failed(.other)
            case let callbackError as OAuthCallbackError:
                phase = (callbackError == .accessDenied) ? .failed(.accessDenied) : .failed(.other)
            case let exchangeError as TokenExchangeError:
                phase = (exchangeError == .networkFailure) ? .failed(.networkFailure) : .failed(.other)
            default:
                phase = .failed(.other)
            }
        }
    }
}
