import XCTest

/// perf-app-runtime.md §7 step 7 and the M2 exit criterion: "a 12-s slow replay shows the
/// breadcrumb, which self-heals" (program plan M2; ux-ui.md A11Y-05).
///
/// The DEBUG launch argument `-TallyDebugSampleRefreshLatency <s>` delays every sample refresh after
/// the first load by `<s>` seconds. Freshness then goes `.refreshing`, then `.delayed` once
/// `liveRefreshBudget` (10 s) passes (the stale breadcrumb shows), then `.fresh` when the refresh
/// lands (the breadcrumb goes away with no interaction and the footer reads "Updated just now").
///
/// **Where the clock starts.** Every XCUITest action returns only once the app is idle ("Wait for
/// … to idle"). A pull-to-refresh keeps the refresh control's spinner animating until
/// `.refreshable` returns, at the 10 s budget, so the drag call itself blocks until then: in run
/// 36378109668 it blocked for 11.4 s, and a clock started after it measured 0.148 s to a
/// breadcrumb that the run's screen recording shows appearing about 10 s after the pull. So:
/// - the breadcrumb's timing is measured from a tap on the hero's Refresh button, which starts the
///   same model-owned manual refresh with no spinner: the tap returns at once and the test watches
///   the whole slow refresh;
/// - the pull-to-refresh test measures how long the pull blocked, which is when the spinner
///   stopped, and uses a refresh slower than the budget by a wide margin, so "stopped at the
///   budget" and "stopped when the refresh landed" are far apart.
final class SlowRefreshUITests: TallyUITestCase {
    private static let breadcrumbPrefix = "Live refresh is taking longer than expected"
    /// `TallyConfig.liveRefreshBudget` (this bundle does not link TallyCore).
    private static let liveRefreshBudget: TimeInterval = 10

    /// The M2 exit criterion itself: a 12 s slow refresh. The breadcrumb appears once the live
    /// budget has passed, never before, while the refresh is still running, then clears by itself.
    @MainActor
    func testSlowRefreshShowsTheBreadcrumbThenSelfHeals() throws {
        let app = launchSampleDashboard(refreshLatency: 12)
        let breadcrumb = Self.breadcrumb(in: app)
        XCTAssertFalse(breadcrumb.exists, "a breadcrumb before any slow refresh. Hierarchy: \(app.debugDescription)")

        let refresh = app.buttons["Refresh"]
        waitUntilHittable(refresh, in: app)
        // Read before the tap, so the time measured below is never shorter than the refresh's own.
        let tapped = Date()
        refresh.tap()

        // Within the budget the footer says "Refreshing…" and there is no breadcrumb.
        let refreshing = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Refreshing")).firstMatch
        XCTAssertTrue(refreshing.waitForExistence(timeout: 5), "no Refreshing… footer. Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(breadcrumb.exists, "the breadcrumb showed within the live budget. Hierarchy: \(app.debugDescription)")

        // The breadcrumb appears once the budget has passed, and before the 12 s refresh lands.
        XCTAssertTrue(sample(breadcrumb, until: true, timeout: 20),
                      "the breadcrumb never appeared. Hierarchy: \(app.debugDescription)")
        let shownAfter = Date().timeIntervalSince(tapped)
        XCTAssertGreaterThanOrEqual(shownAfter, Self.liveRefreshBudget - 1,
                                    "the breadcrumb appeared \(shownAfter) s after the tap, before the live budget passed")

        // Self-heal: the refresh lands and the breadcrumb goes away without any interaction.
        XCTAssertTrue(sample(breadcrumb, until: false, timeout: 20),
                      "the breadcrumb never cleared. Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["Updated just now"].waitForExistence(timeout: 10),
                      "Hierarchy: \(app.debugDescription)")
    }

    /// Pull-to-refresh (`.refreshable { await model.refreshUntilSettledOrDelayed() }`): the spinner
    /// stops at the live budget while the slow refresh keeps running in the task `HomeModel` owns,
    /// the breadcrumb takes over, and the screen self-heals when the refresh lands. The refresh
    /// takes 25 s: a spinner that waited for it would hold the drag for 25 s or more, where one
    /// that stops at the budget releases it after about 10 s plus the gesture and the idle wait.
    @MainActor
    func testPullToRefreshStopsAtTheBudgetWhileTheRefreshRuns() throws {
        let latency: TimeInterval = 25
        let app = launchSampleDashboard(refreshLatency: Int(latency))
        let breadcrumb = Self.breadcrumb(in: app)

        let scroll = app.scrollViews.firstMatch
        let top = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let pulled = Date()
        // Returns once the app is idle: once the refresh control's spinner has stopped.
        top.press(forDuration: 0.1, thenDragTo: top.withOffset(CGVector(dx: 0, dy: 400)))
        let spinnerStoppedWithin = Date().timeIntervalSince(pulled)

        XCTAssertGreaterThanOrEqual(spinnerStoppedWithin, Self.liveRefreshBudget - 1,
                                    "the spinner stopped \(spinnerStoppedWithin) s after the pull, before the live budget")
        XCTAssertLessThan(spinnerStoppedWithin, latency,
                          "the spinner ran until the \(latency) s refresh landed, not until the live budget")
        // The refresh is still running: the footer does not say "Updated just now" yet, and the
        // breadcrumb is up.
        XCTAssertFalse(app.staticTexts["Updated just now"].exists,
                       "the slow refresh had already landed when the spinner stopped. Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(sample(breadcrumb, until: true, timeout: 5),
                      "no breadcrumb after the spinner stopped. Hierarchy: \(app.debugDescription)")

        // Self-heal, with no interaction.
        XCTAssertTrue(sample(breadcrumb, until: false, timeout: latency + 10),
                      "the breadcrumb never cleared. Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["Updated just now"].waitForExistence(timeout: 10),
                      "Hierarchy: \(app.debugDescription)")
    }

    /// Launches with every refresh after the first load delayed by `seconds`, enters sample mode
    /// and waits for the first load's Dashboard.
    @MainActor
    private func launchSampleDashboard(refreshLatency seconds: Int) -> XCUIApplication {
        let app = launchApp(arguments: ["-TallyDebugSampleRefreshLatency", "\(seconds)"])
        // The SAMPLE DATA banner is the sample root's first frame (O9: re-tap once if it is not).
        tap(app.buttons["Explore with Sample Data"], expecting: app.staticTexts["SAMPLE DATA"], in: app)
        XCTAssertTrue(app.staticTexts["Average of 5 courses"].waitForExistence(timeout: 30),
                      "Hierarchy: \(app.debugDescription)")
        return app
    }

    @MainActor
    private static func breadcrumb(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", breadcrumbPrefix)).firstMatch
    }

    /// Samples `element.exists` as often as XCUITest allows, until it equals `expected` or
    /// `timeout` passes. With a 12 s refresh the breadcrumb is on screen for about 2 s (10 s to
    /// 12 s), which a coarser wait on a slow CI simulator could miss.
    @MainActor
    private func sample(_ element: XCUIElement, until expected: Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return element.exists == expected
    }
}
