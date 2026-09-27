import SwiftUI
import TallyFeatures
import TallyPlatform

/// Composition root (architecture.md §3.1). This target holds nothing but
/// this file and `AppEnvironment`: no views, no business logic. The scene's
/// `.backgroundTask(.appRefresh(_:))` registers the background-refresh
/// handler exactly once, replacing the old `BackgroundSyncManager.shared
/// .registerTask()` call from inside a view's `init` (ARC-02: Apple kills an
/// app that registers the same task identifier twice).
@main
struct TallyApp: App {
    @State private var environment = AppEnvironment.live()

    var body: some Scene {
        // `.backgroundTask(_:action:)`'s closure does not inherit this
        // (MainActor) context — its whole point is to be able to run
        // without the UI active — so it cannot read the MainActor-isolated
        // `environment` property directly. Reading `environment.logger`
        // here, while still on MainActor, and capturing the result (a
        // `Sendable` existential per `TallyPlatformLogger: Sendable`) as a
        // plain local lets both closures use it safely.
        let logger = environment.logger
        return WindowGroup {
            RootView()
                .task { logger.log(.appLaunch) }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.taskIdentifier)) {
            // TallySync.RefreshCoordinator (architecture.md §3.4) is not
            // implemented yet — that lands in a later, separate work
            // package. This handler intentionally does nothing rather than
            // simulate a refresh result: the implementation brief forbids
            // fabricating data in shipping code paths. Registering the
            // handler here (instead of inside a view) is itself the fix for
            // ARC-02.
            logger.log(.backgroundRefreshInvoked)
        }
    }
}
