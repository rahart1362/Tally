import XCTest

/// UX-WP-17 (S-5) smoke test on the flagship persona: the week strip (seven days, today marked in
/// words), the agenda, and R6's "Subscribe to Canvas Calendar…", which sample data explains
/// instead of handing a fictional feed to Calendar. "Add to Calendar" opens a system sheet, so it
/// is tested through the event it opens with (`ScreenPresenterTests`), and the timeline rule for
/// the accessibility sizes by a hosted test, not here.
final class CalendarUITests: TallyUITestCase {
    @MainActor
    func testWeekStripAgendaAndSubscribe() throws {
        let app = launchSample()
        openTab("Calendar", in: app)
        let days = app.buttons.matching(identifier: "calendar.day")
        XCTAssertTrue(days.firstMatch.waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
        XCTAssertEqual(days.count, 7, "Hierarchy: \(app.debugDescription)")
        XCTAssertEqual(days.matching(NSPredicate(format: "label CONTAINS 'today'")).count, 1,
                       "today is not marked in words. Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(elements("calendar.item", in: app).firstMatch.waitForExistence(timeout: 10),
                      "an empty agenda. Hierarchy: \(app.debugDescription)")
        assertEveryButtonHasALabel(app, screen: "Calendar")

        tapWhenHittable(app.buttons["calendar.options"], in: app)
        let subscribe = app.buttons["Subscribe to Canvas Calendar…"]
        XCTAssertTrue(subscribe.waitForExistence(timeout: 5), "Hierarchy: \(app.debugDescription)")
        subscribe.tap()
        let note = app.alerts["Subscribing needs your school's Canvas"]
        XCTAssertTrue(note.waitForExistence(timeout: 5), "Hierarchy: \(app.debugDescription)")
        note.buttons["OK"].tap()
    }
}
