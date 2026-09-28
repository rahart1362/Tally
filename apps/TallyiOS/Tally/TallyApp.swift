import SwiftUI
import TallyDomain
import TallyFeatures
import TallyIntents
import TallyPlatform
import TallySync

/// Composition root (architecture.md §3.1). This target holds nothing but
/// this file and `AppEnvironment`: no views, no business logic. The scene's
/// `.backgroundTask(.appRefresh(_:))` registers the background-refresh
/// handler exactly once, replacing the old `BackgroundSyncManager.shared
/// .registerTask()` call from inside a view's `init` (ARC-02: Apple kills an
/// app that registers the same task identifier twice).
@main
struct TallyApp: App {
    @State private var environment = AppEnvironment.live()

    init() {
        #if DEBUG
        // perf-app-runtime.md §5.1: DEBUG-only main-thread hang detection, armed before the
        // first frame. UI tests run it in `fatal:250` mode (`TallyUITestCase`).
        MainThreadWatchdog.arm()
        #endif
    }

    var body: some Scene {
        // `.backgroundTask(_:action:)`'s closure does not inherit this
        // (MainActor) context — its whole point is to be able to run
        // without the UI active — so it cannot read the MainActor-isolated
        // `environment` property directly. Reading `environment.logger`
        // (and, as of E04, its `appModel.refreshCoordinator`) here, while
        // still on MainActor, and capturing the results as plain locals lets
        // both closures use them safely across the isolation boundary
        // (`RefreshCoordinator` is an actor, so the reference itself is
        // `Sendable`).
        let logger = environment.logger
        let appModel = environment.appModel
        let webAuthPresenter = environment.webAuthPresenter
        let coordinator = environment.appModel.refreshCoordinator
        // "Refresh Tally"'s `RefreshIntentBridge` is set and cleared by
        // `AppModel.attach(_:)`/`detach()` (perf-app-runtime.md §7 step 1),
        // never here: `body` stays free of side effects.
        return WindowGroup {
            RootView(appModel: appModel, webAuthPresenter: webAuthPresenter)
                .task {
                    logger.log(.appLaunch)
                    #if DEBUG
                    // The first root view's `.task`: launch is over, so the watchdog drops from
                    // `launchHangThreshold` to `mainThreadHangThreshold`.
                    MainThreadWatchdog.endLaunchGrace()
                    #endif
                }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.taskIdentifier)) {
            logger.log(.backgroundRefreshInvoked)
            // Real call-through to whatever `RefreshCoordinator` the app has
            // today (`nil` until sign-in attaches an account — see
            // `AppEnvironment`'s doc comment): an honest no-op, not a
            // hardcoded stub, and it starts doing real work the moment a
            // coordinator exists with no further change at this call site.
            await coordinator?.run(trigger: .background)
        }
    }
}
