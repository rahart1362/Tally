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
    /// Every seam the composition root wires an `HTTPTransport` into traps instead of sending
    /// (`ReviewPathUITests`' proof of O6, which needs no signed-in account unlike `blockNetwork`).
    static let trapAllNetwork = ["-TallyTestHooks.trapAllNetwork", "YES"]
    static let demoSignIn = ["-TallyTestHooks.demoSignIn", "YES"]
    /// AGE-1 (EB-01(h)): scripts a minor whose significant-change consent is denied, so
    /// `AgeRestrictedView` shows over the signed-in Home (`AgeAssuranceTestHooks`).
    static let ageRestricted = ["-TallyTestHooks.ageAssurance", "restricted"]
    static let signOutButton = ["-TallyTestHooks.signOutButton", "YES"]
    static let appLockOn = ["-TallyTestHooks.appLock", "on"]

    static func appLockGrace(_ period: String) -> [String] { ["-TallyTestHooks.appLockGrace", period] }
    /// M3-B2 (`SubscriptionTestHooks`): a test-only entitlement and App Store, `entitled`, `none` or
    /// `lapsed`; the last one given wins. Enforcement is on, so every `launchApp` passes `entitled`
    /// first (signed-in flows keep their refresh, tabs and reminders), and the paywall's tests pass
    /// `none` or `lapsed` after it.
    static func entitlement(_ state: String) -> [String] { ["-TallyTestHooks.entitlement", state] }
    static let entitled = entitlement("entitled")
    /// `success`, `cancel`, `lockout`, `passcodeNotSet`, `biometryUnavailable`, or a comma-separated
    /// sequence of them.
    static func deviceAuth(_ results: String) -> [String] { ["-TallyTestHooks.deviceAuth", results] }
    /// MVP-2i: an ISO-8601 instant that pins "now" for Sample Data and every projection built from
    /// it (the Calendar layout foremost) — the sample fixtures' dates are relative to today, so an
    /// audit run against the real clock never repeats. `fixedNowWednesday` is the a11y suite's own
    /// default (`TallyUITestCase.defaultTestHookArguments`): a Wednesday, mid-week, chosen for
    /// representativeness, never to make a check pass.
    static func fixedNow(_ iso8601: String) -> [String] { ["-TallyTestHooks.fixedNow", iso8601] }
    static let fixedNowWednesday = fixedNow("2026-10-14T12:00:00Z")

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
        // L10N-04: was app.staticTexts[TestHooks.flagshipHero] (the English text "Average of 5
        // courses", which Spanish changes — this helper's `launchApp` honours
        // `currentLocaleArguments`, so a caller that overrides it, like `AuditTourUITests`, now
        // launches this seed in that language too). The identifier match is equally valid for
        // every other, English-only caller of this shared helper.
        XCTAssertTrue(element("dashboard.hero.averageOfCourses", in: app).waitForExistence(timeout: 30),
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
