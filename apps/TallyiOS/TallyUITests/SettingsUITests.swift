import XCTest

/// UX-WP-20 (S-7): Settings as a `Form` sheet in sample mode. No dead rows and no chevron on a row
/// that does not navigate, no Microsoft 365 or Google, and the "What changed" threshold: All or
/// points, globally and per course.
final class SettingsUITests: TallyUITestCase {
    private static let sections = ["Account", "What changed", "Data & Refresh", "Calendar", "Privacy & Security", "About"]

    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        tapWhenHittable(app.buttons["Settings"], in: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)")
    }

    @MainActor
    func testFormRowsAndTheWhatChangedThreshold() throws {
        let app = launchSample()
        openSettings(app)

        // Sample mode: nothing to sign out of, and it says so.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Everything here is fictional'")).firstMatch
            .waitForExistence(timeout: 5), "Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(app.buttons["settings.signOut"].exists)
        // Microsoft 365 and Google are absent (SEC-D6, ASC-D6).
        let thirdParty = NSPredicate(format: "label CONTAINS[c] 'Microsoft' OR label CONTAINS[c] 'Google' OR label CONTAINS[c] 'Outlook'")
        XCTAssertEqual(app.descendants(matching: .any).matching(thirdParty).count, 0)

        // "What changed": the default is a point value; "every change" hides the points.
        let everyChange = app.switches["settings.everyChange"]
        XCTAssertTrue(everyChange.waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)")
        XCTAssertEqual(everyChange.value as? String, "0")
        XCTAssertTrue(element("settings.points", in: app).exists)
        everyChange.tap()
        XCTAssertTrue(eventually { everyChange.value as? String == "1" })
        XCTAssertFalse(element("settings.points", in: app).exists)
        everyChange.tap()
        XCTAssertTrue(eventually { element("settings.points", in: app).exists })

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
        XCTAssertTrue(eventually { perCourse.label.contains("1 course") }, "per-course summary: '\(perCourse.label)'")

        // Rows that do not navigate are not buttons (no chevron): the version is a plain row.
        for section in Self.sections {
            XCTAssertTrue(scrollUntilHittable(text(section, in: app), in: app), "no \(section) section")
        }
        let version = element("settings.version", in: app)
        XCTAssertTrue(scrollUntilHittable(version, in: app))
        XCTAssertNotEqual(version.elementType, .button)
        XCTAssertTrue(app.staticTexts["Last refreshed"].exists || app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Last refreshed'")).count > 0)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'not affiliated with'")).count > 0,
                      "no non-affiliation disclaimer")
        assertEveryButtonHasALabel(app, screen: "Settings")

        tapWhenHittable(app.buttons["Done"], in: app)
        XCTAssertTrue(eventually { !app.navigationBars["Settings"].exists })
    }

    /// A11Y-02 at the largest text size.
    @MainActor
    func testSettingsAtAccessibilityXXXL() throws {
        let app = launchSample(arguments: Self.largestTextArguments)
        openSettings(app)
        let everyChange = app.switches["settings.everyChange"]
        XCTAssertTrue(everyChange.waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(scrollUntilHittable(everyChange, in: app))
        XCTAssertGreaterThan(everyChange.frame.height, 60, "the row did not grow with Dynamic Type: \(everyChange.frame)")
        assertEveryButtonHasALabel(app, screen: "Settings AX XXXL")
        assertAccessibilityAudit(app, screen: "Settings AX XXXL")
    }
}
