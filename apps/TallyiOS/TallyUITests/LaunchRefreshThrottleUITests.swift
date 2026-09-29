import XCTest

extension TestHooks {
    /// `LaunchTestHooks.Key.lastRefreshAttempt` (O5): the account's last refresh was attempted an
    /// hour ago, or a minute ago.
    static let lastRefreshStale = ["-TallyTestHooks.lastRefreshAttempt", "stale"]
    static let lastRefreshRecent = ["-TallyTestHooks.lastRefreshAttempt", "recent"]
}

/// O5 (PERF-L), end to end: a launch whose account attempted a refresh a minute ago paints its
/// cached rows and does not refresh (`FreshnessRules.shouldStart`, `minAutoRefreshInterval`), and
/// the hero's Refresh button still refreshes at once (a manual refresh always runs). The network is
/// blocked, and the app counts every Canvas request (`LaunchProbe`). The other side, a launch after
/// a stale attempt that does refresh, is `LaunchFromCacheUITests`.
final class LaunchRefreshThrottleUITests: TallyUITestCase {
    override func tearDownWithError() throws {
        // XCTest runs a synchronous tearDown on the main thread.
        MainActor.assumeIsolated { LifecycleUITest.resetAppState() }
    }

    /// How long the test watches for a launch refresh that must not come. `LaunchFromCacheUITests`
    /// sees the launch refresh's request within its 15 s window; in the passing runs it came within
    /// a few seconds of the cached paint.
    private static let quietWindow: TimeInterval = 8

    @MainActor
    func testARecentAttemptSkipsTheLaunchRefreshButAManualRefreshRuns() throws {
        seedFlagshipAccount()

        let app = launchApp(arguments: TestHooks.blockNetwork + TestHooks.lastRefreshRecent)
        XCTAssertTrue(app.staticTexts[TestHooks.flagshipHero].waitForExistence(timeout: 15),
                      "the cached dashboard never painted. Hierarchy: \(app.debugDescription)")
        let probe = app.staticTexts["testHook.networkProbe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 5), "Hierarchy: \(app.debugDescription)")

        // No launch refresh: the last attempt was a minute ago.
        let anyRequest = NSPredicate(format: "NOT (label ENDSWITH %@)", "· 0 requests")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: anyRequest, object: probe)],
                                        timeout: Self.quietWindow),
                       .timedOut, "the launch refreshed although the last attempt was a minute ago: \(probe.label)")

        // A manual refresh always runs.
        tapWhenHittable(app.buttons["Refresh"], in: app)
        let requested = NSPredicate(format: "label ENDSWITH %@", "· 1 requests")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: requested, object: probe)], timeout: 15),
                       .completed, "the manual refresh never asked Canvas: \(probe.label)")
    }
}
