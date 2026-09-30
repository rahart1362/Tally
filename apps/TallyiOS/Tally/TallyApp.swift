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
///
/// The launch (perf-app-runtime.md §2.4): L1 is this `init` (the `Launch.GlancePaint` signpost
/// begins before anything else, then the pure `AppEnvironment.live()`); L2 is `RootView`'s first
/// frame, the launch colour; `AppModel.launch()` does the rest off the main actor. The
/// `Launch.ToTask` phase's steps (`LaunchSignpost`): `Launch.Environment` is `live()`,
/// `Launch.Scene` runs to the window's root content, `Launch.FirstFrame` from there to the launch task.
@main
struct TallyApp: App {
    @State private var environment: AppEnvironment

    init() {
        LaunchSignpost.begin()
        #if DEBUG
        // perf-app-runtime.md §5.1: DEBUG-only main-thread hang detection, armed before the
        // first frame. UI tests run it in `report:250` mode (`TallyUITestCase`; step 4's CI
        // calibration showed a fatal UI-test threshold cannot be both meaningful and green).
        MainThreadWatchdog.arm()
        #endif
        _environment = State(initialValue: AppEnvironment.live())
        LaunchSignpost.enterStep(LaunchSignpost.scene)
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
        let signIn = environment.signIn
        let accountRuntime = environment.accountRuntime
        // "Refresh Tally"'s `RefreshIntentBridge` is set and cleared by
        // `AppModel.attach(_:)`/`detach()` (perf-app-runtime.md §7 step 1),
        // never here: `body` stays free of side effects.
        return WindowGroup {
            let _ = LaunchSignpost.rootContentBuilt()
            #if DEBUG || TALLY_TEST_HOOKS
            // `TallyPerfUITests`' floor measurement only: no app content at all.
            if appModel.testHooks?.emptyScene == true {
                EmptyLaunchSceneView()
            } else {
                Self.root(appModel: appModel, signIn: signIn, logger: logger)
            }
            #else
            Self.root(appModel: appModel, signIn: signIn, logger: logger)
            #endif
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.taskIdentifier)) {
            logger.log(.backgroundRefreshInvoked)
            // perf-app-runtime.md §7 step 7: one run through the account's one coordinator
            // (single-flight with the foreground), resolved lazily by the runtime from
            // `accounts.json` and the cached snapshot (B2). With no account it is an honest no-op.
            await accountRuntime.backgroundRefresh()
        }
    }

    private static func root(appModel: AppModel, signIn: SignInServices, logger: any TallyPlatformLogger) -> some View {
        RootView(appModel: appModel, signIn: signIn)
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
}
