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

    /// ux-fp2 D18 (S2): at AX XXXL the week strip scrolls sideways, and it used to open at Sunday,
    /// with today (the selected day) cut at the right edge or off screen (audit run 37649050231).
    /// It now opens on the selected day, wholly on screen. A screenshot is kept as the snapshot.
    @MainActor
    func testWeekStripOpensOnTheSelectedDayAtAccessibilityXXXL() throws {
        let app = launchSample(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openTab("Calendar", in: app)
        let days = app.buttons.matching(identifier: "calendar.day")
        XCTAssertTrue(days.firstMatch.waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(elements("calendar.item", in: app).firstMatch.waitForExistence(timeout: 10),
                      "an empty agenda. Hierarchy: \(app.debugDescription)")
        var selectedFrame: CGRect?
        for index in 0..<days.count {
            let day = days.element(boundBy: index)
            let isSelected = day.isSelected
            if isSelected { selectedFrame = day.frame }
        }
        let frame = try XCTUnwrap(selectedFrame, "no selected day in the strip. Hierarchy: \(app.debugDescription)")
        let screen = app.frame
        XCTAssertGreaterThanOrEqual(frame.minX, screen.minX, "the selected day starts off the left edge: \(frame)")
        XCTAssertLessThanOrEqual(frame.maxX, screen.maxX, "the selected day runs off the right edge: \(frame)")
        let snapshot = XCTAttachment(screenshot: app.screenshot())
        snapshot.name = "Calendar week strip at AX5 (ux-fp2 D18)"
        snapshot.lifetime = .keepAlways
        add(snapshot)
    }
}
