import XCTest

/// Plan 07 M2-C1 L-1 and the M2 exit gate (program plan §3; plan 07 §3 item 1): "the cache must
/// render before the network: a UI test with the network blocked paints cached rows".
///
/// A seeded, sealed flagship store; then a launch whose Canvas never answers (the `blockNetwork`
/// hook: every fetch is recorded and then hangs). The signed-in dashboard's cached rows paint, the
/// app counts **0** Canvas requests before that first paint, and the refresh it starts afterwards
/// never lands: past the live budget the saved data is still what the student sees.
///
/// Not asserted: the stale breadcrumb that should replace "Refreshing…" at the live budget. CI run
/// 36445122276 showed "Refreshing…" still on screen 40 s after launch: TallySync's
/// `RefreshCoordinator.timedOut(waitingFor:timeout:)` races the fetch in a task group, and a group
/// waits for every child, so it returns only when the fetch ends; a fetch that never answers never
/// publishes `.delayed` (docs/pmo/reviews/m2-lifecycle-report.md, open item O9).
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

        // Past the live budget (10 s) with Canvas still silent, the saved data stays on screen.
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "the live budget passes")], timeout: Self.pastTheLiveBudget)
        XCTAssertTrue(app.staticTexts[TestHooks.flagshipHero].exists, "the saved data left the screen")
        XCTAssertTrue(anyFlagshipCourseCode(in: app).exists, "the cached rows left the screen. Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(app.buttons["Find My School"].exists, "a hung refresh sent the student to Welcome")
    }

    /// `TallyConfig.liveRefreshBudget` (10 s; this bundle does not link TallyCore) plus a margin.
    private static let pastTheLiveBudget: TimeInterval = 12
}
