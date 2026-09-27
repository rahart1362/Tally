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

    static func live() -> AppEnvironment {
        AppEnvironment(logger: OSLogPlatformLogger())
    }
}
