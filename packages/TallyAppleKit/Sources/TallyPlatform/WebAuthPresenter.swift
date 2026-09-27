import AuthenticationServices
import TallyFeatures
import UIKit

/// The one new `TallyPlatform` file this work package adds (implementation
/// brief scope note): an `ASWebAuthenticationSession`-backed conformance to
/// `TallyFeatures`' `WebAuthPresenting` port. `TallyPlatform` importing
/// `TallyFeatures` — not the other way round — is the direction
/// architecture.md §3.1 permits ("Features never import TallyPlatform; the
/// app's composition root injects adapters through protocols").
///
/// Security posture (security.md §3.2 item 4, ADR 0001 step 5):
/// - The `.https(host:path:)` callback (iOS 17.4+), never a custom scheme:
///   "A malicious app can't claim Tally's associated domain, so this stops
///   public-client impersonation."
/// - `prefersEphemeralWebBrowserSession` defaults to `false` so the session
///   reuses the student's existing school SSO session in Safari; the caller
///   (`SignInHandoffViewModel`) threads through the "Private sign-in" value.
/// - The session is retained strongly for its whole lifetime (`currentSession`)
///   and driven from the main actor, and `start() == false` is treated as an
///   error rather than silently doing nothing.
@MainActor
public final class WebAuthPresenter: NSObject, WebAuthPresenting {
    private var currentSession: ASWebAuthenticationSession?

    public override init() {
        super.init()
    }

    public func authenticate(url: URL, callbackHost: String, callbackPath: String, ephemeral: Bool) async throws -> URL {
        // Dropping any previous session's retain happens here, directly on the main
        // actor, rather than inside the completion handler below — that closure's own
        // isolation is the system's to define, and `continuation.resume` is safe to
        // call from it regardless (that is exactly what `CheckedContinuation` is for).
        currentSession = nil
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .https(host: callbackHost, path: callbackPath)
            ) { callbackURL, error in
                if let error {
                    if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin {
                        continuation.resume(throwing: WebAuthError.cancelled)
                    } else {
                        continuation.resume(throwing: WebAuthError.other)
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: WebAuthError.other)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = ephemeral
            // Retained until the next call to `authenticate` (security.md: "Retain
            // the session strongly, run it on the main actor").
            currentSession = session
            guard session.start() else {
                currentSession = nil
                continuation.resume(throwing: WebAuthError.failedToStart)
                return
            }
        }
    }
}

extension WebAuthPresenter: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene,
               let window = windowScene.windows.first(where: \.isKeyWindow) {
                return window
            }
        }
        return ASPresentationAnchor()
    }
}
