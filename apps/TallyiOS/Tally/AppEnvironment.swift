import TallyFeatures
import TallyPlatform

/// The composition root's object graph (architecture.md §3.1). `live()`
/// performs pure construction only — no I/O, no file reads, no network —
/// so it is safe to call synchronously from `@State` in `TallyApp.body`.
/// Adapters are injected as protocols; `TallyFeatures` never imports
/// `TallyPlatform` directly (architecture.md §3.1: "Features never import
/// TallyPlatform; the app's composition root injects adapters through
/// protocols").
struct AppEnvironment {
    let logger: any TallyPlatformLogger
    /// UX-WP-09: the real `ASWebAuthenticationSession` adapter for the
    /// `WebAuthPresenting` port `SignInHandoffViewModel` (`TallyFeatures`) depends on.
    let webAuthPresenter: any WebAuthPresenting

    /// `@MainActor`: `WebAuthPresenter` is main-actor isolated (it drives
    /// `ASWebAuthenticationSession`, which must run on the main thread).
    /// `TallyApp` conforms to `App`, itself a main-actor protocol, so calling
    /// this from `@State private var environment = AppEnvironment.live()` is
    /// already on the right actor.
    @MainActor
    static func live() -> AppEnvironment {
        AppEnvironment(logger: OSLogPlatformLogger(), webAuthPresenter: WebAuthPresenter())
    }
}
