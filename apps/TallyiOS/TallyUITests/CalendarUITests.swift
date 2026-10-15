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

    /// MVP-2b gate-2 round 3 (verdict item 1): the selected day's heading must rest fully below
    /// `calendar.pinnedHeader`, and its first row must be hittable, on open, after tapping the first
    /// day and after tapping a mid-week day, at std and AX5 (D18: AX5 scrolls the strip).
    ///
    /// MVP-2c: the heading checked is the selected day's own, matched by its day of the month
    /// (`A11yScene.dayNumber(in:)`), never the topmost one: the previous day's heading stays in the
    /// hierarchy while it sits under the bars, and round 3 measured that one (run 38623450627: "Tue,
    /// Oct 13" at y = 98.3 while the selected "Today · Wed, Oct 14" rested at 237.3, below the strip's
    /// 233.3). Each check keeps a screenshot and the hierarchy, the before/after evidence.
    @MainActor
    func testSelectedDayHeadingClearsThePinnedStripOnOpenAndAfterTapping() throws {
        let sizes: [(name: String, arguments: [String])] = [("std", []), ("AX5", TallyUITestCase.a11yAccessibilityXXXL)]
        for size in sizes {
            let app = launchSample(arguments: size.arguments)
            openTab("Calendar", in: app)
            let header = element("calendar.pinnedHeader", in: app)
            XCTAssertTrue(header.waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
            let days = app.buttons.matching(identifier: "calendar.day")
            XCTAssertTrue(days.firstMatch.waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
            let dayCount = days.count

            assertSelectedDayHeadingClearsThePinnedStrip(app, header: header, after: "open, \(size.name)")
            tapDay(at: 0, of: days, strip: header, in: app)
            assertSelectedDayHeadingClearsThePinnedStrip(app, header: header, after: "the first day, \(size.name)")
            tapDay(at: dayCount / 2, of: days, strip: header, in: app)
            assertSelectedDayHeadingClearsThePinnedStrip(app, header: header, after: "a mid-week day, \(size.name)")

            app.terminate()
        }
    }

    /// Swipes the week strip (AX5 scrolls it, D18; below that it is disabled and every day is
    /// already hittable, so this is a no-op) until day `index` can be reached, then taps it. Which
    /// direction reveals it depends on where today falls in the week relative to `index`, so this
    /// tries right (the direction that reaches an earlier day; the existing reach helpers' own
    /// precedent) before trying left.
    @MainActor
    private func tapDay(at index: Int, of days: XCUIElementQuery, strip: XCUIElement, in app: XCUIApplication) {
        let day = days.element(boundBy: index)
        let swipes: [() -> Void] = [{ strip.swipeRight() }, { strip.swipeLeft() }]
        for swipe in swipes {
            var count = 0
            while !day.isHittable, count < 6 {
                swipe()
                count += 1
            }
        }
        tapWhenHittable(day, in: app)
    }

    /// The strip's selected day's day of the month, from its label ("Sunday, October 11, 3 items").
    @MainActor
    private func selectedDayNumber(_ app: XCUIApplication) -> Int? {
        let days = app.buttons.matching(identifier: "calendar.day")
        for index in 0..<days.count {
            let day = days.element(boundBy: index)
            let isSelected = day.isSelected
            if isSelected { return A11yScene.dayNumber(in: day.label) }
        }
        return nil
    }

    /// The frame of the selected day's own `calendar.dayHeading` (the one with day `number`), if it
    /// is in the hierarchy.
    @MainActor
    private func headingFrame(forDay number: Int, in app: XCUIApplication) -> CGRect? {
        let headings = elements("calendar.dayHeading", in: app)
        for index in 0..<headings.count {
            let candidate = headings.element(boundBy: index)
            guard candidate.exists else { continue }
            let label = candidate.label
            let frame = candidate.frame
            if A11yScene.dayNumber(in: label) == number, frame.width > 0, frame.height > 0 { return frame }
        }
        return nil
    }

    /// The topmost agenda row (an item, or "Nothing scheduled") that starts below `heading`: the
    /// heading's own first row.
    @MainActor
    private func firstRow(below heading: CGRect, in app: XCUIApplication) -> XCUIElement? {
        let rows = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ OR identifier == %@", "calendar.item", "calendar.nothingScheduled"
        ))
        var first: (element: XCUIElement, minY: CGFloat)?
        for index in 0..<rows.count {
            let row = rows.element(boundBy: index)
            let minY = row.frame.minY
            if minY >= heading.maxY - 0.5, minY < (first?.minY ?? .greatestFiniteMagnitude) {
                first = (element: row, minY: minY)
            }
        }
        return first?.element
    }

    /// Asserts the selected day's heading rests at or below `header`'s bottom edge and that its first
    /// row is hittable. A tap's scroll is animated, so this waits for it to land (nothing in the app
    /// re-scrolls afterwards: one `scrollTo`, no timers, `CalendarScreen.swift`).
    @MainActor
    private func assertSelectedDayHeadingClearsThePinnedStrip(_ app: XCUIApplication, header: XCUIElement, after: String) {
        let pinnedMaxY = header.frame.maxY
        guard let day = selectedDayNumber(app) else {
            XCTFail("no selected day in the strip after \(after). Hierarchy: \(app.debugDescription)")
            return
        }
        _ = eventually(timeout: 3) {
            guard let heading = self.headingFrame(forDay: day, in: app) else { return false }
            return heading.minY >= pinnedMaxY - 0.5
        }
        keepEvidence(app, name: "Calendar, selected heading after \(after)")
        guard let heading = headingFrame(forDay: day, in: app) else {
            XCTFail("the selected day's heading (day \(day)) is not on screen after \(after). Hierarchy: \(app.debugDescription)")
            return
        }
        XCTAssertGreaterThanOrEqual(heading.minY, pinnedMaxY - 0.5,
            "the selected day's heading (day \(day)) rested under the pinned strip after \(after): heading.minY=\(heading.minY), " +
            "pinnedHeader.maxY=\(pinnedMaxY). Hierarchy: \(app.debugDescription)")
        let row = firstRow(below: heading, in: app)
        XCTAssertTrue(row?.isHittable == true,
                      "the heading's first row was not hittable after \(after). Hierarchy: \(app.debugDescription)")
    }

    /// A screenshot and the element hierarchy, kept even when the test passes (MVP-2c: the before/after
    /// evidence for the heading's position, readable from CI without Xcode).
    @MainActor
    private func keepEvidence(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + " (hierarchy)"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
