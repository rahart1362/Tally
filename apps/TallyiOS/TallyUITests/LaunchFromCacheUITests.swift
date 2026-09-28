import XCTest

/// Plan 07 M2-C1 L-1 and the M2 exit gate (program plan §3; plan 07 §3 item 1): "the cache must
/// render before the network: a UI test with the network blocked paints cached rows".
///
/// A seeded, sealed flagship store; then a launch whose Canvas never answers (the `blockNetwork`
/// hook: every fetch is recorded and then hangs). The signed-in dashboard's cached rows paint, the
/// app counts **0** Canvas requests before that first paint, and the refresh it starts afterwards
/// never lands: the footer stays "Refreshing…" until the live budget, then the stale breadcrumb
/// takes over over the same saved data.
///
/// The breadcrumb check was out while TallySync's `RefreshCoordinator.timedOut` returned only when
/// the fetch ended (CI run 36445122276: "Refreshing…" still up 40 s after launch; m2-lifecycle-report
/// O9, D13). It is back with O9's fix.
final class LaunchFromCacheUITests: TallyUITestCase {
    override func tearDownWithError() throws {
        // XCTest runs a synchronous tearDown on the main thread.
        MainActor.assumeIsolated { LifecycleUITest.resetAppState() }
    }

    @MainActor
    func testSeededLaunchPaintsCachedRowsBeforeAnyNetworkActivity() throws {
        seedFlagshipAccount()

        let app = launchApp(arguments: TestHooks.blockNetwork)
        // A signed-in root: the Home, never Welcome.
        XCTAssertTrue(app.staticTexts[TestHooks.flagshipHero].waitForExistence(timeout: 15),
                      "the cached dashboard never painted. Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(app.buttons["Find My School"].exists, "a signed-in launch showed Welcome")
        XCTAssertTrue(app.staticTexts["Due soon"].exists)
        XCTAssertTrue(anyFlagshipCourseCode(in: app).waitForExistence(timeout: 5),
                      "no cached row with a course code. Hierarchy: \(app.debugDescription)")

        // No Canvas request before the first cached frame.
        let probe = app.staticTexts["testHook.networkProbe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 5), "Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(probe.label.contains("· 0 requests before the first paint"),
                      "the network was used before the cached paint: \(probe.label)")

        // The launch refresh did start, afterwards, and never lands.
        let requested = NSPredicate(format: "label ENDSWITH %@", "· 1 requests")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: requested, object: probe)], timeout: 15),
                       .completed, "the launch refresh never asked Canvas: \(probe.label)")
        let refreshing = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Refreshing")).firstMatch
        XCTAssertTrue(refreshing.waitForExistence(timeout: 5), "Hierarchy: \(app.debugDescription)")

        // At the live budget (10 s) with Canvas still silent, the stale breadcrumb replaces
        // "Refreshing…", and the saved data stays on screen.
        let breadcrumb = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Live refresh is taking longer than expected")).firstMatch
        XCTAssertTrue(breadcrumb.waitForExistence(timeout: Self.breadcrumbTimeout),
                      "no stale breadcrumb once the live budget passed. Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(app.staticTexts[TestHooks.flagshipHero].exists, "the saved data left the screen")
        XCTAssertTrue(anyFlagshipCourseCode(in: app).exists, "the cached rows left the screen. Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(app.buttons["Find My School"].exists, "a hung refresh sent the student to Welcome")
    }

    /// `TallyConfig.liveRefreshBudget` (10 s; this bundle does not link TallyCore) plus a margin for a
    /// loaded simulator; the original check's 20 s.
    private static let breadcrumbTimeout: TimeInterval = 20
}
