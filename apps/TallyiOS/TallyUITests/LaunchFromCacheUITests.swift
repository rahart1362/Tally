import XCTest

/// Plan 07 M2-C1 L-1 and the M2 exit gate (program plan §3; plan 07 §3 item 1): "the cache must
/// render before the network: a UI test with the network blocked paints cached rows".
///
/// A seeded, sealed flagship store; then a launch whose Canvas never answers (the `blockNetwork`
/// hook: every fetch is recorded and then hangs). The signed-in dashboard's cached rows paint, the
/// app counts **0** Canvas requests before that first paint, and the refresh it starts afterwards
/// never lands: the footer stays "Refreshing…" until the live budget, then the stale breadcrumb
/// takes over over the same saved data.
final class LaunchFromCacheUITests: TallyUITestCase {
    override func tearDownWithError() throws {
        MainActor.assumeIsolated { resetAppState() }
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

        // The launch refresh did start, afterwards, and never landed: still saved data only.
        let requested = NSPredicate(format: "label ENDSWITH %@", "· 1 requests")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: requested, object: probe)], timeout: 15),
                       .completed, "the launch refresh never asked Canvas: \(probe.label)")
        let refreshing = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Refreshing")).firstMatch
        XCTAssertTrue(refreshing.waitForExistence(timeout: 5), "Hierarchy: \(app.debugDescription)")
        let breadcrumb = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Live refresh is taking longer than expected")).firstMatch
        XCTAssertTrue(breadcrumb.waitForExistence(timeout: 20),
                      "no stale breadcrumb once the live budget passed. Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(app.staticTexts[TestHooks.flagshipHero].exists, "the saved data left the screen")
    }
}
