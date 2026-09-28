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
        // `environment` property directly. Reading `environment.logger` and
        // `environment.accountRuntime` here, while still on MainActor, and
        // capturing them as plain locals lets both closures use them safely
        // across the isolation boundary (`AccountRuntime` is an actor, so the
        // reference itself is `Sendable`).
        let logger = environment.logger
        let appModel = environment.appModel
        let webAuthPresenter = environment.webAuthPresenter
        let accountRuntime = environment.accountRuntime
        // "Refresh Tally"'s `RefreshIntentBridge` is set and cleared by
        // `AppModel.attach(_:)`/`detach()` (perf-app-runtime.md §7 step 1),
        // never here: `body` stays free of side effects.
        return WindowGroup {
            RootView(appModel: appModel, webAuthPresenter: webAuthPresenter)
                .task {
                    logger.log(.appLaunch)
                    #if DEBUG
                    // The first root view's `.task`: once the main thread then stays responsive
                    // for `launchSettleWindow`, the watchdog moves from `launchHangThreshold` to
                    // `mainThreadHangThreshold`.
                    MainThreadWatchdog.firstRootTaskDidRun()
                    #endif
                }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.taskIdentifier)) {
            logger.log(.backgroundRefreshInvoked)
            // perf-app-runtime.md §7 step 7: one run through the account's
            // one coordinator (single-flight with the foreground), resolved
            // lazily by the runtime. With no account it is an honest no-op,
            // and it does real work the moment sign-in installs one, with no
            // change at this call site.
            await accountRuntime.backgroundRefresh()
        }
    }
}
