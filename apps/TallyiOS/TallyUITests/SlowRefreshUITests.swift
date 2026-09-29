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
///   budget" and "stopped when the refresh landed" are far apart. It also checks that the
///   breadcrumb is already up when the pull returns (app-core report O8).
final class SlowRefreshUITests: TallyUITestCase {
    private static let breadcrumbPrefix = "Live refresh is taking longer than expected"
    /// `TallyConfig.liveRefreshBudget` (this bundle does not link TallyCore).
    private static let liveRefreshBudget: TimeInterval = 10
    /// How long the breadcrumb test's refresh takes: the budget plus a 10 s window for the breadcrumb.
    private static let slowRefreshSeconds = 20
    /// O8: how soon after the pull returns the breadcrumb must be up. In every correct run it was
    /// already up at the first check (run 36390172728), because the spinner and the breadcrumb
    /// both wait for the live budget; one second allows for a slow accessibility query.
    private static let breadcrumbAfterPullWindow: TimeInterval = 1

    /// The M2 exit criterion itself: a refresh slower than the live budget. The breadcrumb appears
    /// once the budget has passed, never before, while the refresh is still running, then clears by
    /// itself. The plan's example is 12 s, but that leaves the breadcrumb on screen for only 2 s
    /// (10 s to 12 s), and on a loaded simulator the tap below plus XCUITest's idle wait took long
    /// enough that the 12 s refresh had already landed by the first check (run 36511691943: the
    /// footer read "Updated just now"); the same window was missed on Xcode 27 (M2-C2 OI11). So the
    /// refresh takes `slowRefreshSeconds`, which gives the breadcrumb a 10 s window.
    @MainActor
    func testSlowRefreshShowsTheBreadcrumbThenSelfHeals() throws {
        let app = launchSampleDashboard(refreshLatency: Self.slowRefreshSeconds)
        let breadcrumb = Self.breadcrumb(in: app)
        XCTAssertFalse(breadcrumb.exists, "a breadcrumb before any slow refresh. Hierarchy: \(app.debugDescription)")

        let refresh = app.buttons["Refresh"]
        waitUntilHittable(refresh, in: app)
        // Read before the tap, so the time measured below is never shorter than the refresh's own
        // (a re-tap only makes the real refresh start later than this).
        let tapped = Date()

        // Within the budget the footer says "Refreshing…" and there is no breadcrumb. O9: the
        // Xcode 27 run of PR #2 (36434300284) found the footer still "Updated just now" after this
        // tap, the tap not taken; `tap(_:expecting:)` re-taps once in that case.
        let refreshing = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Refreshing")).firstMatch
        tap(refresh, expecting: refreshing, in: app, timeout: 5)
        // Meaningful only while the budget has not passed: the check can run later than that when
        // the tap and its idle wait are slow, and then a breadcrumb is correct. The appearance time
        // below catches an early breadcrumb whenever the tap returned in time.
        let breadcrumbShowing = breadcrumb.exists
        let checkedAfter = Date().timeIntervalSince(tapped)
        if checkedAfter < Self.liveRefreshBudget - 1 {
            XCTAssertFalse(breadcrumbShowing, "the breadcrumb showed \(checkedAfter) s after the tap, within the live budget. Hierarchy: \(app.debugDescription)")
        } else {
            XCTContext.runActivity(named: "Within-budget check skipped: the tap returned \(checkedAfter) s after it started") { _ in }
        }

        // The breadcrumb appears once the budget has passed, and before the slow refresh lands.
        XCTAssertTrue(sample(breadcrumb, until: true, timeout: 20),
                      "the breadcrumb never appeared. Hierarchy: \(app.debugDescription)")
        let shownAfter = Date().timeIntervalSince(tapped)
        XCTAssertGreaterThanOrEqual(shownAfter, Self.liveRefreshBudget - 1,
                                    "the breadcrumb appeared \(shownAfter) s after the tap, before the live budget passed")

        // Self-heal: the refresh lands and the breadcrumb goes away without any interaction. It is
        // up for about 10 s first; the timeout keeps the old 20 s margin on top of that.
        XCTAssertTrue(sample(breadcrumb, until: false, timeout: 30),
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
        let pullReturned = Date()
        let spinnerStoppedWithin = pullReturned.timeIntervalSince(pulled)

        // Two independent signals that the spinner waited for the live budget; both are recorded
        // in one run. (1), checked first because it is the time-critical one: the breadcrumb is
        // already up when the pull returns (O8). A spinner that stops at once (mutation MS3)
        // returns about 10 s before the breadcrumb exists, so this does not depend on how long
        // the gesture itself took; it could only miss MS3 if XCUITest's idle wait after a stopped
        // spinner took about 9 s. (2) The pull blocked for at least the budget: MS3 was caught by
        // this alone with 0.28 s to spare on a slow runner (run 36403288465, 8.72 s).
        let breadcrumbUp = sample(breadcrumb, until: true, timeout: Self.breadcrumbAfterPullWindow)
        let checkedFor = Date().timeIntervalSince(pullReturned)
        continueAfterFailure = true
        XCTAssertTrue(breadcrumbUp, "the breadcrumb was not up within \(Self.breadcrumbAfterPullWindow) s of the pull "
                      + "returning (checked for \(checkedFor) s; the pull blocked \(spinnerStoppedWithin) s): the spinner "
                      + "stopped before the live budget. Hierarchy: \(app.debugDescription)")
        XCTAssertGreaterThanOrEqual(spinnerStoppedWithin, Self.liveRefreshBudget - 1,
                                    "the spinner stopped \(spinnerStoppedWithin) s after the pull, before the live budget")
        continueAfterFailure = false
        XCTAssertLessThan(spinnerStoppedWithin, latency,
                          "the spinner ran until the \(latency) s refresh landed, not until the live budget")
        // The refresh is still running: the footer does not say "Updated just now" yet.
        XCTAssertFalse(app.staticTexts["Updated just now"].exists,
                       "the slow refresh had already landed when the spinner stopped. Hierarchy: \(app.debugDescription)")

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
    /// `timeout` passes, so a short-lived state is not missed between coarser waits on a slow CI
    /// simulator.
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
