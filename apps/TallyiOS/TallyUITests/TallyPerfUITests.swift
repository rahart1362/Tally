import XCTest

/// perf-app-runtime.md §5.2 and plan 07 §3 item 1: the warm launch of a signed-in account, to the
/// painted glance. `make ios-perf` runs this in Release (with the `TALLY_TEST_HOOKS` condition, so
/// the seed hook exists in that test build only) and `scripts/ci/check_perf_budgets.py` compares
/// the medians with `perf/budgets.json`:
/// - `Launch.GlancePaint` (`XCTOSSignpostMetric`): from `TallyApp.init` to the first frame with
///   cached content; budget 300 ms (`TallyConfig.warmStartBudget`);
/// - `XCTApplicationLaunchMetric`: process launch to the first responsive frame; recorded, not
///   gated (§5.2: "report only" until a device baseline exists).
///
/// Each suite seeds once (not measured), so every measured iteration is a launch from the same
/// sealed store. The account's Canvas is the bundled replay, so no measured launch touches the
/// network.
final class TallyPerfUITests: TallyUITestCase {
    private static let subsystem = "dev.tally-app.tally"

    override func tearDownWithError() throws {
        // XCTest runs a synchronous tearDown on the main thread.
        MainActor.assumeIsolated { LifecycleUITest.resetAppState() }
    }

    @MainActor
    private func measuredApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += TestHooks.replayAccounts
        app.launchEnvironment.merge(Self.watchdogEnvironment) { _, armed in armed }
        return app
    }

    @MainActor
    func testWarmLaunchGlancePaint() throws {
        seedFlagshipAccount()
        let app = measuredApp()
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        let glancePaint = XCTOSSignpostMetric(subsystem: Self.subsystem, category: "perf", name: "Launch.GlancePaint")
        measure(metrics: [glancePaint], options: options) {
            app.launch()
            XCTAssertTrue(app.staticTexts[TestHooks.flagshipHero].waitForExistence(timeout: 20),
                          "the glance never painted. Hierarchy: \(app.debugDescription)")
        }
        app.terminate()
    }

    @MainActor
    func testWarmApplicationLaunch() throws {
        seedFlagshipAccount()
        let app = measuredApp()
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            app.launch()
        }
        app.terminate()
    }
}
