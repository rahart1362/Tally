import XCTest

/// M3-C (UX-WP-12, A11Y-11): the reminders permission is asked in context, and Settings says where
/// it stands. One smoke test: sample data shows no tip and says reminders aren't scheduled for it; a
/// signed-in account with work due shows the Dashboard tip, its "Turn On Reminders" asks, and once
/// the answer is no, the tip is gone and Settings offers Open Settings.
///
/// **No system permission alert.** The permission is scripted (`-TallyTestHooks.notifications`,
/// `ReminderTestHooks` in TallyFeatures): the tap's request answers "denied" without reaching
/// `UNUserNotificationCenter`, and Open Settings is never tapped (it leaves the app). The rules
/// behind each state are hosted tests (`RemindersTests.swift`).
final class RemindersUITests: TallyUITestCase {
    /// `ReminderTestHooks.key`: the permission at launch, then what a request answers.
    private static let notDeterminedThenDenied = ["-TallyTestHooks.notifications", "notDetermined:denied"]

    override func tearDownWithError() throws {
        // The seeded account must not outlive this test: the other suites expect Welcome at launch.
        MainActor.assumeIsolated { LifecycleUITest.resetAppState() }
    }

    @MainActor
    func testTipAsksInContextAndSettingsShowsTheReminderState() throws {
        // Sample data: nothing is scheduled for it, so no tip, and Settings explains instead of asking.
        let sample = launchSample(arguments: Self.notDeterminedThenDenied)
        XCTAssertFalse(sample.buttons["tip.enableReminders"].exists,
                       "sample data offered to turn on reminders. Hierarchy: \(sample.debugDescription)")
        openSettings(sample)
        XCTAssertTrue(element("settings.reminders.sample", in: sample).waitForExistence(timeout: 10),
                      "Settings did not say reminders aren't scheduled for sample data. Hierarchy: \(sample.debugDescription)")
        XCTAssertFalse(sample.buttons["settings.reminders.turnOn"].exists)
        sample.terminate()

        // A signed-in account (the seed hook's sealed flagship store; the bundled replay for its Canvas).
        let app = launchApp(arguments: TestHooks.seedFlagship + TestHooks.replayAccounts + Self.notDeterminedThenDenied)
        XCTAssertTrue(app.staticTexts[TestHooks.flagshipHero].waitForExistence(timeout: 30),
                      "the seeded launch never painted the dashboard. Hierarchy: \(app.debugDescription)")
        let turnOn = app.buttons["tip.enableReminders"]
        XCTAssertTrue(scrollUntilHittable(turnOn, in: app),
                      "no reminders tip on a dashboard with work due. Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["Get reminded before work is due"].exists)
        XCTAssertTrue(app.buttons["tip.dismissReminders"].exists, "the tip cannot be dismissed")

        tapWhenHittable(turnOn, in: app, timeout: LifecycleUITest.tapTimeout)
        XCTAssertTrue(eventually { !app.buttons["tip.enableReminders"].exists },
                      "the tip stayed after the permission was answered. Hierarchy: \(app.debugDescription)")

        openSettings(app)
        let openSettingsButton = app.buttons["settings.reminders.openSettings"]
        XCTAssertTrue(scrollUntilHittable(openSettingsButton, in: app),
                      "denied: no Open Settings in Settings' Reminders. Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(element("settings.reminders.denied", in: app).exists, "denied: no \"Notifications are off for Tally\"")
        XCTAssertFalse(app.buttons["settings.reminders.turnOn"].exists, "denied: Settings still offers to ask")
        let hideNames = app.switches["settings.reminders.hideNames"]
        XCTAssertTrue(scrollUntilHittable(hideNames, in: app), "no Hide Course Names. Hierarchy: \(app.debugDescription)")
        XCTAssertEqual(hideNames.value as? String, "0", "course names are hidden by default")
    }
}
