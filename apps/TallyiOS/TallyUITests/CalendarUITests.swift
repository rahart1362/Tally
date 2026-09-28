import XCTest

/// UX-WP-17 (S-5): Calendar on the flagship persona. The week strip (today marked in words), the
/// agenda, R6's "Subscribe to Canvas Calendar…" and per-item "Add to Calendar" with no permission
/// prompt, and no timeline option at the accessibility sizes.
final class CalendarUITests: TallyUITestCase {
    @MainActor
    private func springboardAlerts() -> XCUIElementQuery {
        XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts
    }

    @MainActor
    func testWeekStripAgendaSubscribeAndAddToCalendar() throws {
        let app = launchSample()
        openTab("Calendar", in: app)
        let days = app.buttons.matching(identifier: "calendar.day")
        XCTAssertTrue(days.firstMatch.waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.matching(NSPredicate(format: "label CONTAINS 'today'")).count, 1,
                       "today is not marked in words. Hierarchy: \(app.debugDescription)")
        let items = elements("calendar.item", in: app)
        XCTAssertTrue(items.firstMatch.waitForExistence(timeout: 10), "an empty agenda. Hierarchy: \(app.debugDescription)")
        assertEveryButtonHasALabel(app, screen: "Calendar")

        // The options: subscribing (R6) and, at this size, the day timeline.
        tapWhenHittable(app.buttons["calendar.options"], in: app)
        let subscribe = app.buttons["Subscribe to Canvas Calendar…"]
        XCTAssertTrue(subscribe.waitForExistence(timeout: 5), "Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(app.buttons["Day"].exists, "no timeline option at the default size")
        subscribe.tap()
        // Sample data's feed is fictional, so it is explained, never handed to Calendar.
        let note = app.alerts["Subscribing needs your school's Canvas"]
        XCTAssertTrue(note.waitForExistence(timeout: 5), "Hierarchy: \(app.debugDescription)")
        note.buttons["OK"].tap()

        // Add to Calendar: the system editor, with no calendar permission prompt (R6).
        let add = app.buttons.matching(identifier: "calendar.add").firstMatch
        tapWhenHittable(add, in: app)
        let editor = app.navigationBars["New Event"]
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(eventually(timeout: 15) { editor.exists || cancel.exists },
                      "the event editor did not open. Hierarchy: \(app.debugDescription)")
        XCTAssertEqual(springboardAlerts().count, 0, "a system alert appeared: \(springboardAlerts().debugDescription)")
        XCTAssertEqual(app.alerts.count, 0)
        if cancel.exists { cancel.tap() }
        XCTAssertTrue(eventually(timeout: 10) { add.isHittable }, "the editor did not close")
    }

    /// A11Y-02 and UX-WP-17: at the largest text size the timeline option is gone, and the
    /// agenda still reads.
    @MainActor
    func testTimelineIsHiddenAtAccessibilityXXXL() throws {
        let app = launchSample(arguments: Self.largestTextArguments)
        openTab("Calendar", in: app)
        let item = elements("calendar.item", in: app).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
        tapWhenHittable(app.buttons["calendar.options"], in: app)
        XCTAssertTrue(app.buttons["Subscribe to Canvas Calendar…"].waitForExistence(timeout: 5),
                      "Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(app.buttons["Day"].exists, "the timeline option is offered at an accessibility size")
        XCTAssertFalse(app.buttons["Agenda"].exists)
        // Close the menu.
        app.tap()
        XCTAssertTrue(scrollUntilHittable(item, in: app))
        XCTAssertGreaterThan(item.frame.height, 150, "the row did not grow with Dynamic Type: \(item.frame)")
        assertEveryButtonHasALabel(app, screen: "Calendar AX XXXL")
        assertAccessibilityAudit(app, screen: "Calendar AX XXXL")
    }
}
