import Foundation

/// The port `SignInHandoffViewModel` needs to present a web-based sign-in
/// and get back the callback URL Canvas (or the system) redirects to
/// (security.md §3.2 item 4; ADR 0001's launch sequence step 5).
///
/// Declared here, in `TallyFeatures`, not `TallyPlatform`: "Features never
/// import TallyPlatform; the app's composition root injects adapters
/// through protocols" (architecture.md §3.1). The concrete
/// `ASWebAuthenticationSession`-backed conformance — this work package's
/// only new `TallyPlatform` file — imports `TallyFeatures` to see this
/// protocol, which is the direction the architecture note permits.
///
/// `@MainActor`: presenting a system UI sheet must happen on the main
/// thread/actor; requiring it on the protocol means every conformance and
/// every caller is checked at compile time, not just the one shipping
/// adapter.
public protocol WebAuthPresenting: Sendable {
    /// - Parameters:
    ///   - url: the authorization URL (`AuthorizationRequest.url`).
    ///   - callbackHost: the associated-domain host `ASWebAuthenticationSession
    ///     .Callback.https(host:path:)` matches on (the `TallyOrgDomain` value).
    ///   - callbackPath: the callback's path component (`/oauth/callback`).
    ///   - ephemeral: `prefersEphemeralWebBrowserSession` — the "Private
    ///     sign-in" setting (security.md §3.2 item 4; default `false`).
    /// - Returns: the full callback URL.
    /// - Throws: `WebAuthError`.
    @MainActor
    func authenticate(url: URL, callbackHost: String, callbackPath: String, ephemeral: Bool) async throws -> URL
}

/// "Cancel is not an error" (ADR 0001 step 6) is still modeled as a thrown
/// case, not a special return value, because it's genuinely exceptional
/// control flow from `ASWebAuthenticationSession`'s own completion handler
/// — the view model is what turns `.cancelled` into a calm, non-alert status.
public enum WebAuthError: Error, Sendable, Equatable {
    /// `ASWebAuthenticationSessionError.canceledLogin`, or the SwiftUI
    /// `WebAuthenticationSession` throwing the equivalent — the student
    /// dismissed the sheet before completing (or declining) sign-in.
    case cancelled
    /// `session.start()` returned `false` (security.md: "treat `start()==false`
    /// as an error").
    case failedToStart
    /// Any other `ASWebAuthenticationSession` failure.
    case other
    /// No live presenter is wired in (see `UnavailableWebAuthPresenter`).
    case notConfigured
}

/// `RootView`'s default until the composition root supplies the real
/// `WebAuthPresenter` (`TallyPlatform`). Fails honestly rather than
/// fabricating a callback — the same seam pattern as `UnavailableInstitutionSearch`
/// (UX-WP-08) and `UnavailableTokenExchange`.
public struct UnavailableWebAuthPresenter: WebAuthPresenting {
    public init() {}
    @MainActor
    public func authenticate(url: URL, callbackHost: String, callbackPath: String, ephemeral: Bool) async throws -> URL {
        throw WebAuthError.notConfigured
    }
}
