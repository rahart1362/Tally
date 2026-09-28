import XCTest

/// perf-app-runtime.md §7 step 7, the M2 exit criterion: "a 12-s injected replay latency → the
/// spinner ends by about 10.5 s, the breadcrumb shows, then self-heals".
///
/// The DEBUG launch argument `-TallyDebugSampleRefreshLatency 12` delays every sample refresh after
/// the first load by 12 s. A pull-to-refresh then returns at `liveRefreshBudget` (10 s; the unit
/// test `HomeModelTests.pullToRefreshReturnsAtTheBudget` covers the spinner), the session publishes
/// `.delayed` from its one timer and the stale breadcrumb appears; when the refresh lands the
/// breadcrumb goes away with no interaction and the footer reads "Updated just now".
final class SlowRefreshUITests: TallyUITestCase {
    private static let breadcrumbPrefix = "Live refresh is taking longer than expected"

    /// Samples `element.exists` as often as XCUITest allows, until it equals `expected` or
    /// `timeout` passes. The breadcrumb is on screen for about 2 s (10 s to 12 s), which a
    /// coarser wait on a slow CI simulator could miss.
    @MainActor
    private func sample(_ element: XCUIElement, until expected: Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return element.exists == expected
    }

    @MainActor
    func testSlowRefreshShowsTheBreadcrumbThenSelfHeals() throws {
        let app = launchApp(arguments: ["-TallyDebugSampleRefreshLatency", "12"])
        tapWhenHittable(app.buttons["Explore with Sample Data"], in: app)
        XCTAssertTrue(app.staticTexts["Average of 5 courses"].waitForExistence(timeout: 30),
                      "Hierarchy: \(app.debugDescription)")

        // Pull to refresh on the Dashboard's scroll view.
        let scroll = app.scrollViews.firstMatch
        let top = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        top.press(forDuration: 0.1, thenDragTo: top.withOffset(CGVector(dx: 0, dy: 400)))
        let released = Date()

        // The breadcrumb appears once the 10 s live budget passes, not before, and before the 12 s
        // refresh lands.
        let breadcrumb = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", Self.breadcrumbPrefix)).firstMatch
        XCTAssertTrue(sample(breadcrumb, until: true, timeout: 20),
                      "the breadcrumb never appeared. Hierarchy: \(app.debugDescription)")
        let shownAfter = Date().timeIntervalSince(released)
        XCTAssertGreaterThanOrEqual(shownAfter, 9.0, "the breadcrumb appeared before the live-refresh budget passed")

        // Self-heal: the refresh lands and the breadcrumb goes away without any interaction.
        XCTAssertTrue(sample(breadcrumb, until: false, timeout: 20),
                      "the breadcrumb never cleared. Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["Updated just now"].waitForExistence(timeout: 10),
                      "Hierarchy: \(app.debugDescription)")
    }
}
