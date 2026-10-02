import XCTest

/// perf-app-runtime.md §5.2 and plan 07 §3 item 1: the warm launch of a signed-in account, to the
/// painted glance. `make ios-perf` runs this in Release (with the `TALLY_TEST_HOOKS` condition, so
/// the seed hook exists in that test build only) and `scripts/ci/check_perf_budgets.py` compares
/// the medians with `perf/budgets.json`:
/// - `Launch.GlancePaint` (`XCTOSSignpostMetric`): from `TallyApp.init` to the first frame with
///   cached content; budget 300 ms (`TallyConfig.warmStartBudget`). Its three phases
///   (`Launch.ToTask`, `Launch.Resolve`, `Launch.HomeRender`) are reported, not gated;
/// - `XCTApplicationLaunchMetric`: process launch to the first responsive frame; recorded, not
///   gated (§5.2: "report only" until a device baseline exists).
/// - PERF-L: `Launch.ToTask`'s steps (`Launch.Environment`, `Launch.Scene`, `Launch.FirstFrame`),
///   reported, and the same phase for an empty scene (`testEmptySceneToTask`): its floor on this
///   simulator with no app content, so the app's own share of the phase can be told apart.
///
/// **Only in `make ios-perf`** (its `TEST_RUNNER_TALLY_PERF_RUN=1` reaches this runner as
/// `TALLY_PERF_RUN`). Elsewhere the class skips: a Debug or sanitizer launch measures nothing the
/// budgets use, and there `XCTApplicationLaunchMetric` failed to record an iteration ("Received
/// unexpected number of metrics: 0", CI run 36454268485, ios-build and ios-asan), which failed a
/// required job. The seeded launch itself stays covered there by `LaunchFromCacheUITests` and
/// `AppLockUITests`.
///
/// Each test seeds once (not measured), so every measured iteration is a launch from the same
/// sealed store. The account's Canvas is the bundled replay, so no measured launch touches the
/// network.
final class TallyPerfUITests: TallyUITestCase {
    private static let subsystem = "dev.tally-app.tally"
    /// `LaunchSignpost`'s interval, its three phases and the first phase's three steps (this bundle
    /// does not link TallyFeatures).
    private static let launchIntervals = ["Launch.GlancePaint", "Launch.ToTask", "Launch.Resolve", "Launch.HomeRender",
                                          "Launch.Environment", "Launch.Scene", "Launch.FirstFrame"]
    /// What an empty scene records: the first phase and its steps.
    private static let toTaskIntervals = ["Launch.ToTask", "Launch.Environment", "Launch.Scene", "Launch.FirstFrame"]
    /// `LaunchTestHooks.Key.emptyScene`.
    private static let emptyScene = ["-TallyTestHooks.emptyScene", "YES"]

    /// Set once the skip check passes: XCTest still runs `tearDown` after a skip thrown in `setUp`,
    /// and a skipped test has nothing to reset.
    private var measures = false

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TALLY_PERF_RUN"] == "1",
                          "Launch measurements run in make ios-perf only (Release, TALLY_PERF_RUN=1)")
        measures = true
    }

    override func tearDownWithError() throws {
        guard measures else { return }
        // XCTest runs a synchronous tearDown on the main thread.
        MainActor.assumeIsolated { LifecycleUITest.resetAppState() }
    }

    @MainActor
    private func measuredApp() -> XCUIApplication {
        let app = XCUIApplication()
        // M3-B2: entitled, as every UI-test launch is, so the measured launch refreshes as before.
        app.launchArguments += Self.pinnedLocaleArguments + TestHooks.entitled + TestHooks.replayAccounts
        app.launchEnvironment.merge(Self.watchdogEnvironment) { _, armed in armed }
        return app
    }

    @MainActor
    private static func launchMetrics(_ intervals: [String] = launchIntervals) -> [any XCTMetric] {
        intervals.map { XCTOSSignpostMetric(subsystem: subsystem, category: "perf", name: $0) as any XCTMetric }
    }

    @MainActor
    private static func options() -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        return options
    }

    /// The budgeted measurement: the launch, then XCUITest waits for the glance.
    @MainActor
    func testWarmLaunchGlancePaint() throws {
        seedFlagshipAccount()
        let app = measuredApp()
        measure(metrics: Self.launchMetrics(), options: Self.options()) {
            app.launch()
            XCTAssertTrue(app.staticTexts[TestHooks.flagshipHero].waitForExistence(timeout: 20),
                          "the glance never painted. Hierarchy: \(app.debugDescription)")
        }
        app.terminate()
    }

    /// The same launch with no element query until well after the glance: XCUITest's queries
    /// snapshot the app's accessibility tree on its main thread, which can stretch the measured
    /// interval. Reported, not gated; the difference from the test above is that overhead.
    @MainActor
    func testUnobservedWarmLaunchGlancePaint() throws {
        seedFlagshipAccount()
        let app = measuredApp()
        measure(metrics: Self.launchMetrics(), options: Self.options()) {
            app.launch()
            Thread.sleep(forTimeInterval: Self.unobservedWindow)
            XCTAssertTrue(app.staticTexts[TestHooks.flagshipHero].waitForExistence(timeout: 20),
                          "the glance never painted. Hierarchy: \(app.debugDescription)")
        }
        app.terminate()
    }

    /// Longer than the slowest measured glance paint on the CI simulator so far (5.8 s, the first
    /// iteration of run 36454268485).
    private static let unobservedWindow: TimeInterval = 8

    /// PERF-L: `Launch.ToTask` with no app content (the `emptyScene` hook: the window shows an empty
    /// view whose task ends the phase; nothing is read). Reported, not gated. The real launch's
    /// `Launch.ToTask` minus this is what `RootView`'s first frame adds on top of the process, the
    /// scene and `AppEnvironment.live()` (both launches build the environment).
    @MainActor
    func testEmptySceneToTask() throws {
        let app = XCUIApplication()
        app.launchArguments += Self.pinnedLocaleArguments + Self.emptyScene
        app.launchEnvironment.merge(Self.watchdogEnvironment) { _, armed in armed }
        measure(metrics: Self.launchMetrics(Self.toTaskIntervals), options: Self.options()) {
            app.launch()
            // There is nothing to wait for on screen; the phase ends in the empty view's first task.
            Thread.sleep(forTimeInterval: Self.emptySceneSettle)
        }
        app.terminate()
    }

    /// Longer than the empty scene needs to run its first task after `launch()` returns.
    private static let emptySceneSettle: TimeInterval = 1

    @MainActor
    func testWarmApplicationLaunch() throws {
        seedFlagshipAccount()
        let app = measuredApp()
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: Self.options()) {
            app.launch()
        }
        app.terminate()
    }
}
