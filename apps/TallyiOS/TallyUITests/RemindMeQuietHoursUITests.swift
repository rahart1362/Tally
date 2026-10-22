import XCTest

/// FEAT-3 (ideas 4 and 5): one smoke test, by identifiers, for both of this package's new
/// surfaces on the seeded flagship account — To-Do's "Remind me" swipe action and Settings'
/// Quiet Hours pair of time pickers. Neither surface offers anything for sample data (ASC-14:
/// nothing is scheduled for it), which `RemindersUITests` already covers; this test only needs
/// the signed-in account.
///
/// **No system permission alert.** Scheduling and quiet-hours writes never ask for notification
/// permission themselves (`RemindersModel.reconcileNow()` only reads the permission already
/// held, it never requests one), so this test needs no `-TallyTestHooks.notifications` hook.
final class RemindMeQuietHoursUITests: TallyUITestCase {
    override func tearDownWithError() throws {
        MainActor.assumeIsolated { LifecycleUITest.resetAppState() }
    }

    @MainActor
    func testRemindMeSwipeActionAndQuietHoursPickersExist() throws {
        let app = launchApp(arguments: TestHooks.seedFlagship + TestHooks.replayAccounts)
        XCTAssertTrue(app.staticTexts[TestHooks.flagshipHero].waitForExistence(timeout: 30),
                      "the seeded launch never painted the dashboard. Hierarchy: \(app.debugDescription)")

        // Idea 4: the swipe action is there, by identifier, on a dated row, and a tap does not
        // crash or remove the row (the pipeline pass it kicks off is covered at the unit level,
        // `ReminderPlannerTests`; this is the smoke test that the control is reachable and safe).
        openTab("To-Do", in: app)
        let rows = elementsWithPrefix("todo.row", in: app)
        XCTAssertTrue(eventually(timeout: 15) { rows.count > 0 }, "Hierarchy: \(app.debugDescription)")
        let first = rows.element(boundBy: 0)
        XCTAssertTrue(scrollUntilHittable(first, in: app), "Hierarchy: \(app.debugDescription)")
        first.swipeLeft()
        let remindMe = element("todo.swipe.remindMe", in: app)
        XCTAssertTrue(remindMe.waitForExistence(timeout: 5), "no Remind Me swipe action. Hierarchy: \(app.debugDescription)")
        remindMe.tap()
        XCTAssertTrue(eventually { first.exists }, "the row disappeared after Remind Me. Hierarchy: \(app.debugDescription)")

        // Idea 5: the Quiet Hours pair, by identifier, in Settings' Reminders section.
        openSettings(app)
        let start = element("settings.reminders.quietHours.start", in: app)
        XCTAssertTrue(scrollUntilHittable(start, in: app), "no Quiet Hours start picker. Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(element("settings.reminders.quietHours.end", in: app).exists,
                      "no Quiet Hours end picker. Hierarchy: \(app.debugDescription)")
    }
}
