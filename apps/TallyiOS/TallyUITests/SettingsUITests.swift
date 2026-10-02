import XCTest

/// UX-WP-20 (S-7): Settings as a `Form` sheet in sample mode. Every section, the version as a row
/// that is not a button (no chevron), no Microsoft 365, Google or Outlook row in any section, "Exit
/// Sample Data" instead of "Sign Out & Erase", and the "What changed" threshold: All or points,
/// globally and per course.
final class SettingsUITests: TallyUITestCase {
    static let sections = ["Account", "What changed", "Data & Refresh", "Calendar", "Privacy & Security", "About"]

    @MainActor
    func testFormRowsAndTheWhatChangedThreshold() throws {
        let app = launchSample()
        openSettings(app)

        // Sample mode: nothing to sign out of, and it says so; leaving sample mode is offered instead.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Everything here is fictional'")).firstMatch
            .waitForExistence(timeout: 5), "Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(app.buttons["settings.signOut"].exists)
        XCTAssertTrue(app.buttons["settings.exitSample"].waitForExistence(timeout: 5),
                      "no Exit Sample Data: the AppModel did not reach Settings. Hierarchy: \(app.debugDescription)")
        // Microsoft 365 and Google are absent (SEC-D6, ASC-D6), here and after every scroll below.
        assertNoThirdPartyRows(app, at: "the top")

        // "What changed": the default is a point value; "every change" hides the points.
        let everyChange = app.switches["settings.everyChange"]
        XCTAssertTrue(everyChange.waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)")
        XCTAssertEqual(everyChange.value as? String, "0")
        XCTAssertTrue(element("settings.points", in: app).exists)
        flip(everyChange, in: app)
        XCTAssertTrue(eventually { everyChange.value as? String == "1" },
                      "the toggle did not turn on: \(String(describing: everyChange.value)). Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(eventually { !self.element("settings.points", in: app).exists },
                      "every change still shows the points. Hierarchy: \(app.debugDescription)")
        flip(everyChange, in: app)
        XCTAssertTrue(eventually { everyChange.value as? String == "0" && self.element("settings.points", in: app).exists },
                      "the points did not come back. Hierarchy: \(app.debugDescription)")

        // Per course: a navigating row, then one menu per course.
        tapWhenHittable(app.buttons["settings.perCourse"], in: app)
        XCTAssertTrue(app.navigationBars["Per Course"].waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)")
        let pickers = app.buttons.matching(identifier: "settings.courseThreshold")
        XCTAssertEqual(pickers.count, 5, "Hierarchy: \(app.debugDescription)")
        tapWhenHittable(pickers.element(boundBy: 0), in: app)
        tapWhenHittable(app.buttons["Every change"], in: app)
        XCTAssertTrue(eventually { pickers.element(boundBy: 0).label.contains("Every change") || pickers.element(boundBy: 0).value as? String == "Every change" },
                      "the course threshold did not change. Hierarchy: \(app.debugDescription)")
        app.navigationBars["Per Course"].buttons.element(boundBy: 0).tap()
        let perCourse = app.buttons["settings.perCourse"]
        XCTAssertTrue(eventually { perCourse.label.contains("1 course") || perCourse.value as? String == "1 course" },
                      "per-course summary: '\(perCourse.label)' / \(String(describing: perCourse.value))")

        // Rows that do not navigate are not buttons (no chevron): the version is a plain row. A Form
        // builds only the rows on screen, so the third-party check runs again after each scroll,
        // down to the disclaimer, the Form's last element.
        for section in Self.sections {
            XCTAssertTrue(scrollUntilHittable(text(section, in: app), in: app), "no \(section) section")
            assertNoThirdPartyRows(app, at: section)
            if section == "Data & Refresh" {
                XCTAssertTrue(app.staticTexts["Last refreshed"].exists
                              || app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Last refreshed'")).count > 0)
            }
        }
        let version = element("settings.version", in: app)
        XCTAssertTrue(scrollUntilHittable(version, in: app))
        XCTAssertNotEqual(version.elementType, .button)
        assertNoThirdPartyRows(app, at: "the version")
        let disclaimer = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'not affiliated with'")).firstMatch
        for _ in 0..<3 where !disclaimer.exists {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(disclaimer.exists, "no non-affiliation disclaimer")
        app.swipeUp(velocity: .slow) // the Form's end
        assertNoThirdPartyRows(app, at: "the end of the Form")
        assertEveryButtonHasALabel(app, screen: "Settings")

        tapWhenHittable(app.buttons["Done"], in: app)
        XCTAssertTrue(eventually { !app.navigationBars["Settings"].exists })
    }
}

/// UX-WP-20 (S-7) on a signed-in account: the seed hook's sealed flagship store, the bundled replay
/// for its Canvas and a scripted device authenticator (no network, no system sheet). The account's
/// rows are there and the sample rows are not; App Lock and "Show Grades in Widgets" are off and
/// usable (their rules are hosted tests: `AppLockSettingsTests`, `WidgetGradesSettingTests`); and
/// "Sign Out & Erase" asks first, with the spec's copy, then signs out to Welcome.
final class SettingsSignedInUITests: TallyUITestCase {
    override func tearDownWithError() throws {
        // The account must not outlive this test: the other suites expect Welcome at launch.
        MainActor.assumeIsolated { LifecycleUITest.resetAppState() }
    }

    @MainActor
    func testAccountRowsThenSignOutAndErase() throws {
        let app = launchApp(arguments: TestHooks.seedFlagship + TestHooks.replayAccounts + TestHooks.deviceAuth("success"))
        XCTAssertTrue(app.staticTexts[TestHooks.flagshipHero].waitForExistence(timeout: 30),
                      "the seeded launch never painted the dashboard. Hierarchy: \(app.debugDescription)")
        openSettings(app)

        XCTAssertTrue(app.buttons["settings.signOut"].waitForExistence(timeout: 10),
                      "no Sign Out & Erase on a signed-in account. Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(app.buttons["settings.exitSample"].exists)
        let lock = app.switches["settings.appLock"]
        XCTAssertTrue(scrollUntilHittable(lock, in: app), "no App Lock toggle. Hierarchy: \(app.debugDescription)")
        XCTAssertEqual(lock.value as? String, "0")
        XCTAssertTrue(lock.isEnabled, "App Lock is disabled although the (scripted) device has a passcode")
        let widgetGrades = app.switches["settings.widgetGrades"]
        XCTAssertTrue(scrollUntilHittable(widgetGrades, in: app), "no Show Grades in Widgets. Hierarchy: \(app.debugDescription)")
        XCTAssertEqual(widgetGrades.value as? String, "0", "grades in widgets must be opt-in (PMO R10)")

        // Reopen at the top (a swipe down at the top of a sheet would dismiss it).
        tapWhenHittable(app.buttons["Done"], in: app)
        XCTAssertTrue(eventually { !app.navigationBars["Settings"].exists })
        openSettings(app)
        tapWhenHittable(app.buttons["settings.signOut"], in: app, timeout: LifecycleUITest.tapTimeout)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Tally will delete your saved courses and grades'"))
            .firstMatch.waitForExistence(timeout: 10), "no confirmation with the spec's copy. Hierarchy: \(app.debugDescription)")
        // PAY-11 (M3-B2): erasing does not cancel the subscription, says so, and links to Manage Subscription.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS \"This doesn't cancel your Tally subscription\""))
            .firstMatch.exists, "the confirmation does not say the subscription stays. Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(app.buttons["Manage Subscription"].exists, "no Manage Subscription in the confirmation. Hierarchy: \(app.debugDescription)")
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Sign Out & Erase' AND identifier != 'settings.signOut'")).firstMatch
        tapWhenHittable(confirm, in: app, timeout: LifecycleUITest.tapTimeout)
        XCTAssertTrue(app.buttons["Find My School"].waitForExistence(timeout: 15),
                      "Sign Out & Erase did not return to Welcome. Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(app.staticTexts[TestHooks.flagshipHero].exists)
    }
}

extension TallyUITestCase {
    @MainActor
    func openSettings(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        tapWhenHittable(app.buttons["Settings"], in: app, file: file, line: line)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)",
                      file: file, line: line)
    }

    /// SEC-D6, ASC-D6: no Microsoft 365, Google or Outlook row among the rows on screen.
    @MainActor
    func assertNoThirdPartyRows(_ app: XCUIApplication, at place: String, file: StaticString = #filePath, line: UInt = #line) {
        let thirdParty = NSPredicate(format: "label CONTAINS[c] 'Microsoft' OR label CONTAINS[c] 'Google' OR label CONTAINS[c] 'Outlook'")
        let found = app.descendants(matching: .any).matching(thirdParty)
        XCTAssertEqual(found.count, 0, "a third-party row at \(place): \(found.allElementsBoundByIndex.map { $0.label })",
                       file: file, line: line)
    }
}
