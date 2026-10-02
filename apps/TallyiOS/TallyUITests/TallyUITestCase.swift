import MachO
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
/// - `tap(_:expecting:)` is for a tap that must lead to another screen: it re-taps once if the
///   screen did not change (app-core report O9).
/// - Under a sanitizer every wait in these helpers is `sanitizerWaitScale` times longer (O9).
class TallyUITestCase: XCTestCase {
    /// `MainThreadWatchdog.Mode.environmentKey` and its mode (this bundle does not link TallyCore).
    static let watchdogEnvironment = ["TALLY_MAIN_THREAD_WATCHDOG": "report:250"]

    /// Plan 08 §3.9 (L10N-01): every UI test runs the app in English with US formatting, whatever
    /// the simulator's language and region, so the tests' English assertions ("Average of 5
    /// courses", "Find My School", "Updated just now") and formatted values stay deterministic
    /// once Tally ships more than one language. Every launch applies it: `launchApp(arguments:)`
    /// here, and the suites that build their own `XCUIApplication` add it themselves.
    static let pinnedLocaleArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]

    /// The per-test hang limit for UI tests (`-test-timeouts-enabled`; the command line's
    /// maximum is 300 s). The 120 s default was too tight for this environment: in run
    /// 36370850272 `testSchoolNotEnabledToSampleData` spent 80 s in "Open app" (the app process
    /// started 76 s after the test began) and 20.7 s in its first search-field tap (first keyboard
    /// presentation), then hit 120 s. A real hang still fails within 4 minutes.
    static let executionAllowance: TimeInterval = 240

    /// How much longer the helpers below wait when this test process runs under a sanitizer. The
    /// instrumented simulator is several times slower: on PR #2 (run 36434300284) the UI tests under
    /// AddressSanitizer failed on waits sized for a normal run (a search field "exists but is not
    /// hittable" after `waitUntilHittable`'s 10 s, the test at 93 s), with 0 ASan reports. The
    /// scale covers every wait these helpers make; a test's own `waitForExistence` calls can use
    /// `scaled(_:)`.
    static let sanitizerWaitScale: TimeInterval = 3
    /// `sanitizerWaitScale` when an ASan or TSan runtime is loaded in this process (an instrumented
    /// test bundle loads it), otherwise 1.
    static let waitScale: TimeInterval = sanitizerRuntimeIsLoaded ? sanitizerWaitScale : 1

    private static var sanitizerRuntimeIsLoaded: Bool {
        (0..<_dyld_image_count()).contains { index in
            guard let name = _dyld_get_image_name(index) else { return false }
            let path = String(cString: name)
            return path.contains("libclang_rt.asan") || path.contains("libclang_rt.tsan")
        }
    }

    /// `seconds`, scaled for a sanitizer run (`waitScale`).
    func scaled(_ seconds: TimeInterval) -> TimeInterval { seconds * Self.waitScale }

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = Self.executionAllowance
    }

    /// M3-B2: with enforcement on, every launch is entitled unless the test says otherwise
    /// (`TestHooks.entitlement`, passed after this default: the last one wins).
    @MainActor
    @discardableResult
    func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += Self.pinnedLocaleArguments + TestHooks.entitled + arguments
        app.launchEnvironment.merge(Self.watchdogEnvironment) { _, armed in armed }
        app.launch()
        return app
    }

    /// Waits up to `timeout` (scaled for a sanitizer run) for `element` to exist and become
    /// hittable, asserts it did, then taps.
    @MainActor
    func tapWhenHittable(
        _ element: XCUIElement, in app: XCUIApplication, timeout: TimeInterval = 10,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        waitUntilHittable(element, in: app, timeout: timeout, file: file, line: line)
        element.tap()
    }

    /// Taps `element` once it is hittable, then waits up to `timeout` for `expected`, the first
    /// element of the screen the tap leads to. If `expected` has not appeared and `element` is
    /// still there and hittable, so the screen did not change, it taps once more and waits again;
    /// then it asserts `expected` appeared, with the hierarchy.
    ///
    /// App-core report O9: on a starved CI simulator (mutation run 36403288465: a 28 s launch, a
    /// 12 s query) a tap on a hittable "Explore with Sample Data" did not take, and Welcome was
    /// still showing 30 s later. The second tap happens only while the tapped control is still
    /// hittable, that is, on the same screen, so it can never land on whatever the first tap
    /// opened. It is recorded as an activity ("Re-tap once: …"), so a run's log shows how often
    /// it was needed.
    @MainActor
    func tap(
        _ element: XCUIElement, expecting expected: XCUIElement, in app: XCUIApplication, timeout: TimeInterval = 15,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        tapWhenHittable(element, in: app, file: file, line: line)
        if expected.waitForExistence(timeout: scaled(timeout)) { return }
        if element.exists, element.isHittable {
            XCTContext.runActivity(named: "Re-tap once: \(expected) did not follow the tap on \(element)") { _ in
                element.tap()
            }
        }
        XCTAssertTrue(expected.waitForExistence(timeout: scaled(timeout)),
                      "\(expected) never appeared after tapping \(element). Hierarchy: \(app.debugDescription)",
                      file: file, line: line)
    }

    /// Waits up to `timeout` (scaled for a sanitizer run) for `element` to exist and become
    /// hittable, and asserts it did. A test that times what a tap starts calls this first, then
    /// reads the clock, then taps.
    @MainActor
    func waitUntilHittable(
        _ element: XCUIElement, in app: XCUIApplication, timeout: TimeInterval = 10,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: scaled(timeout)),
                      "\(element) never appeared. Hierarchy: \(app.debugDescription)", file: file, line: line)
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: scaled(timeout)), .completed,
                       "\(element) exists but is not hittable. Hierarchy: \(app.debugDescription)",
                       file: file, line: line)
    }
}
