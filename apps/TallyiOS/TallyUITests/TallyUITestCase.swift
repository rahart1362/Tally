import XCTest

/// The base class for every Tally UI test (perf-app-runtime.md §7 steps 3 and 4).
///
/// - `launchApp(arguments:)` is the one way a test starts the app, so launch configuration lives
///   in one place. It arms the DEBUG main-thread watchdog in `report:250` mode: every main-thread
///   stall past 250 ms is logged with its length and phase, and CI prints those lines
///   (`make ios-watchdog-log`). Not `fatal:250` (perf-app-runtime.md §5.1's calibration step):
///   on the Debug CI simulator, one-time framework work (first renders, collection-view reloads,
///   toolbars) and XCUITest's own accessibility snapshots stall the main thread past 250 ms after
///   launch (runs 36368473854, 36369654517). The fatal threshold for UI tests is set from the
///   logged stall lengths.
/// - `tapWhenHittable(_:)` taps a control only once it is actually hittable. A control that exists
///   but is covered or off screen fails the test at the call site, with the hierarchy, instead of
///   XCUITest tapping whatever lies on top of it.
class TallyUITestCase: XCTestCase {
    /// `MainThreadWatchdog.Mode.environmentKey` and its mode (this bundle does not link TallyCore).
    static let watchdogEnvironment = ["TALLY_MAIN_THREAD_WATCHDOG": "report:250"]

    /// The per-test hang limit for UI tests (`-test-timeouts-enabled`; the command line's
    /// maximum is 300 s). The 120 s default was too tight for this environment: in run
    /// 36370850272 `testSchoolNotEnabledToSampleData` spent 80 s in "Open app" (the app process
    /// started 76 s after the test began) and 20.7 s in its first search-field tap (first keyboard
    /// presentation), then hit 120 s. A real hang still fails within 4 minutes.
    static let executionAllowance: TimeInterval = 240

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = Self.executionAllowance
    }

    @MainActor
    @discardableResult
    func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += arguments
        app.launchEnvironment.merge(Self.watchdogEnvironment) { _, armed in armed }
        app.launch()
        return app
    }

    /// Waits up to `timeout` for `element` to exist and become hittable, asserts it did, then taps.
    @MainActor
    func tapWhenHittable(
        _ element: XCUIElement, in app: XCUIApplication, timeout: TimeInterval = 10,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "\(element) never appeared. Hierarchy: \(app.debugDescription)", file: file, line: line)
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: timeout), .completed,
                       "\(element) exists but is not hittable. Hierarchy: \(app.debugDescription)",
                       file: file, line: line)
        element.tap()
    }
}
