import TallyFeatures
import TallyPlatform

/// The composition root's object graph (architecture.md §3.1). `live()`
/// performs pure construction only — no I/O, no file reads, no network —
/// so it is safe to call synchronously from `@State` in `TallyApp.body`.
/// Adapters are injected as protocols; `TallyFeatures` never imports
/// `TallyPlatform` directly (architecture.md §3.1: "Features never import
/// TallyPlatform; the app's composition root injects adapters through
/// protocols").
///
/// E04: `appModel` is the one `AppModel` the whole app shares.
/// `accountRuntime` (perf-app-runtime.md §7 step 7) owns the signed-in
/// account's one `RefreshCoordinator`, shared by the Home (through
/// `appModel`) and `.backgroundTask`. It starts with none — pure construction
/// can't stand up a real per-account `RefreshCoordinator` without knowing
/// whether an account exists, and reading that (Keychain, the store) is I/O
/// this initializer is forbidden from doing. The runtime resolves the account
/// lazily; sign-in installs one through `appModel.attach(_:)`.
func mutationA6Probe() -> Never { fatalError("MUTATION MA6") }

struct AppEnvironment {
    let logger: any TallyPlatformLogger
    /// UX-WP-09: the real `ASWebAuthenticationSession` adapter for the
    /// `WebAuthPresenting` port `SignInHandoffViewModel` (`TallyFeatures`) depends on.
    let webAuthPresenter: any WebAuthPresenting
    let accountRuntime: AccountRuntime
    let appModel: AppModel

    /// `@MainActor`: `WebAuthPresenter` is main-actor isolated (it drives
    /// `ASWebAuthenticationSession`, which must run on the main thread), and
    /// `AppModel` is `@MainActor @Observable`. `TallyApp` conforms to `App`,
    /// itself a main-actor protocol, so calling this from
    /// `@State private var environment = AppEnvironment.live()` is already on
    /// the right actor.
    @MainActor
    static func live() -> AppEnvironment {
        // One `os.Logger` adapter for the platform's own events and for TallyCore's logging port
        // (plan 06 A8: `OSLogPlatformLogger` conforms to both).
        let logger = OSLogPlatformLogger()
        let accountRuntime = AccountRuntime()
        return AppEnvironment(logger: logger, webAuthPresenter: WebAuthPresenter(), accountRuntime: accountRuntime,
                              appModel: AppModel(accountRuntime: accountRuntime, logger: logger))
    }
}
