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
/// E04: `appModel` is the one `AppModel` the whole app shares. Its
/// `refreshCoordinator` starts `nil` — pure construction can't stand up a
/// real per-account `RefreshCoordinator` without knowing whether an account
/// exists, and reading that (Keychain, the store) is I/O this initializer is
/// forbidden from doing. Onboarding/sign-in (a separate, concurrently
/// developed work package) is what will eventually call `appModel.attach(_:)`
/// once a real account and its coordinator exist.
@MainActor
struct AppEnvironment {
    let logger: any TallyPlatformLogger
    let appModel: AppModel

    static func live() -> AppEnvironment {
        AppEnvironment(logger: OSLogPlatformLogger(), appModel: AppModel())
    }
}
