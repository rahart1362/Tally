import TallySync

/// Interim wiring for "Refresh Tally" (E04). `AppIntent.perform()` has no initializer parameters
/// and no access to the app's composition root, so it needs *some* way to reach the live
/// `RefreshCoordinator`. Apple's sanctioned mechanism for that is `AppDependencyManager` plus
/// `AppIntentsPackage`/`@Dependency` — but that package-level wiring is explicitly out of this
/// work package's scope ("`AppIntentsPackage` wiring is deferred to E06", per the M2 app-shell
/// merge notes in `build/logs/iteration_journal.md`). This bridge is the honest, minimal stand-in
/// until then: `AppModel.attach(_:)` sets `coordinator` and `detach()` (and so `signOut()`) clears
/// it, and the intent reads it. It is real wiring, not a fabricated result — today it is
/// `nil` (no signed-in account yet), so the intent's `perform()` is a genuine no-op, exactly like
/// `.backgroundTask`'s.
@MainActor
public enum RefreshIntentBridge {
    public static var coordinator: RefreshCoordinator?
}
