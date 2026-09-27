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
        WindowGroup {
            RootView()
                .task { environment.logger.log(.appLaunch) }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.taskIdentifier)) {
            // TallySync.RefreshCoordinator (architecture.md §3.4) is not
            // implemented yet — that lands in a later, separate work
            // package. This handler intentionally does nothing rather than
            // simulate a refresh result: the implementation brief forbids
            // fabricating data in shipping code paths. Registering the
            // handler here (instead of inside a view) is itself the fix for
            // ARC-02.
            environment.logger.log(.backgroundRefreshInvoked)
        }
    }
}
