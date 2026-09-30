import XCTest

/// Launch arguments for the app's `LaunchTestHooks` (TallyFeatures; this bundle does not link it,
/// so the names are repeated here). DEBUG builds, and the `TALLY_TEST_HOOKS` Release test build
/// (`make ios-perf`), honour them; a shipping Release build compiles none of it.
enum TestHooks {
    static let seedFlagship = ["-TallyTestHooks.seed", "flagship"]
    static let reset = ["-TallyTestHooks.reset", "YES"]
    /// The account's Canvas is the bundled flagship replay: no network in any test.
    static let replayAccounts = ["-TallyTestHooks.replayAccounts", "YES"]
    static let blockNetwork = ["-TallyTestHooks.blockNetwork", "YES"]
    static let demoSignIn = ["-TallyTestHooks.demoSignIn", "YES"]
    static let signOutButton = ["-TallyTestHooks.signOutButton", "YES"]
    static let appLockOn = ["-TallyTestHooks.appLock", "on"]

    static func appLockGrace(_ period: String) -> [String] { ["-TallyTestHooks.appLockGrace", period] }
    /// `success`, `cancel`, `lockout`, `passcodeNotSet`, `biometryUnavailable`, or a comma-separated
    /// sequence of them.
    static func deviceAuth(_ results: String) -> [String] { ["-TallyTestHooks.deviceAuth", results] }

    /// The flagship persona's course codes (fixtures/canvas/personas/flagship/courses.json).
    static let flagshipCourseCodes = ["BIO 101", "MATH 122", "ENG 101", "PSY 101", "HIST 210"]
    /// The signed-in hero for the flagship's 5 courses (the glance paints it, then the projection).
    static let flagshipHero = "Average of 5 courses"
}

/// The lifecycle suites' shared set-up and tear-down steps. Static, so a nonisolated `tearDown`
/// can run them on the main actor without sending the test case across isolation.
enum LifecycleUITest {
    /// How long a lifecycle test waits for a control to become hittable before tapping it. Longer
    /// than `tapWhenHittable`'s 10 s default: under AddressSanitizer a search field took longer
    /// than 10 s to become hittable (M2-C2, run 36434300284). A passing run never waits it out.
    static let tapTimeout: TimeInterval = 30

    /// Erases every account, key, credential and the app-lock setting (the reset hook), so the next
    /// test launches to Welcome whatever this one left behind. Every lifecycle suite runs it in
    /// `tearDown`: the simulator keeps the app's container and Keychain between UI tests, and the
    /// other suites expect Welcome at launch.
    @MainActor
    static func resetAppState(file: StaticString = #filePath, line: UInt = #line) {
        let app = XCUIApplication()
        app.launchArguments += TallyUITestCase.pinnedLocaleArguments + TestHooks.reset
        app.launchEnvironment.merge(TallyUITestCase.watchdogEnvironment) { _, armed in armed }
        app.launch()
        XCTAssertTrue(app.buttons["Find My School"].waitForExistence(timeout: 30),
                      "the reset launch did not reach Welcome. Hierarchy: \(app.debugDescription)", file: file, line: line)
        app.terminate()
    }
}

extension TallyUITestCase {
    @MainActor
    func resetAppState(file: StaticString = #filePath, line: UInt = #line) {
        LifecycleUITest.resetAppState(file: file, line: line)
    }

    /// Writes a sealed, signed-in flagship store (the seed hook), checks that the launch paints its
    /// dashboard, then terminates, so the next launch is a launch from that store.
    @MainActor
    func seedFlagshipAccount(extra: [String] = [], file: StaticString = #filePath, line: UInt = #line) {
        let app = launchApp(arguments: TestHooks.seedFlagship + TestHooks.replayAccounts + extra)
        XCTAssertTrue(app.staticTexts[TestHooks.flagshipHero].waitForExistence(timeout: 30),
                      "the seeded launch never painted the dashboard. Hierarchy: \(app.debugDescription)",
                      file: file, line: line)
        app.terminate()
    }

    /// Any of the flagship's course codes on screen (the due-soon rows carry them).
    @MainActor
    func anyFlagshipCourseCode(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label IN %@", TestHooks.flagshipCourseCodes)).firstMatch
    }
}
