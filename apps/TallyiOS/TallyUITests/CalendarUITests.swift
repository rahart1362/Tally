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
    /// `calendar.pinnedHeader`, not merely mostly clear of it — round 2's own fix did not hold
    /// (gate-2 review, section 3: the heading rested under the strip at every variant checked, on
    /// open and after a tap). `CalendarScreen.scrollBelowPinnedStrip`'s own doc comment has the
    /// two bugs this fixes: the scroll target is now the heading's own row (a `List` Section's
    /// `header:` content never registered as a `scrollTo` anchor at all), and a couple of
    /// deferred, re-corrective calls land it once the List's layout has actually settled. Checked
    /// on open, after tapping the first day and after tapping a mid-week day, at std and AX5
    /// (D18: AX5 scrolls the strip).
    @MainActor
    func testSelectedDayHeadingClearsThePinnedStripOnOpenAndAfterTapping() throws {
        let extras: [[String]] = [[], TallyUITestCase.a11yAccessibilityXXXL]
        for extra in extras {
            let app = launchSample(arguments: extra)
            openTab("Calendar", in: app)
            let header = element("calendar.pinnedHeader", in: app)
            XCTAssertTrue(header.waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
            let days = app.buttons.matching(identifier: "calendar.day")
            XCTAssertTrue(days.firstMatch.waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
            let dayCount = days.count

            assertSelectedDayHeadingClearsThePinnedStrip(app, header: header, after: "open (\(extra))")
            tapDay(at: 0, of: days, strip: header, in: app)
            assertSelectedDayHeadingClearsThePinnedStrip(app, header: header, after: "the first day (\(extra))")
            tapDay(at: dayCount / 2, of: days, strip: header, in: app)
            assertSelectedDayHeadingClearsThePinnedStrip(app, header: header, after: "a mid-week day (\(extra))")

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

    /// The topmost on-screen `calendar.dayHeading` — the one `scrollTo` just placed — or `nil`.
    @MainActor
    private func topmostDayHeading(_ app: XCUIApplication) -> CGRect? {
        let headings = elements("calendar.dayHeading", in: app)
        var topmost: CGRect?
        for index in 0..<headings.count {
            let candidate = headings.element(boundBy: index)
            guard candidate.exists else { continue }
            let frame = candidate.frame
            guard frame.width > 0, frame.height > 0 else { continue }
            if topmost == nil || frame.minY < topmost!.minY { topmost = frame }
        }
        return topmost
    }

    /// Asserts the topmost on-screen `calendar.dayHeading` rests at or below `header`'s own bottom
    /// edge, and that its first row (an agenda item, or "Nothing scheduled") is hittable.
    /// `scrollBelowPinnedStrip` re-corrects the scroll position across a couple of deferred
    /// run-loop turns, so this polls (`eventually` runs the run loop while it waits, letting those
    /// deferred calls actually fire) rather than checking once, immediately.
    @MainActor
    private func assertSelectedDayHeadingClearsThePinnedStrip(_ app: XCUIApplication, header: XCUIElement, after: String) {
        let pinnedMaxY = header.frame.maxY
        _ = eventually(timeout: 3) {
            guard let heading = self.topmostDayHeading(app) else { return false }
            return heading.minY >= pinnedMaxY - 0.5
        }
        guard let heading = topmostDayHeading(app) else {
            XCTFail("no calendar.dayHeading on screen after \(after). Hierarchy: \(app.debugDescription)")
            return
        }
        XCTAssertGreaterThanOrEqual(heading.minY, pinnedMaxY - 0.5,
            "the heading rested under the pinned strip after \(after): heading.minY=\(heading.minY), " +
            "pinnedHeader.maxY=\(pinnedMaxY). Hierarchy: \(app.debugDescription)")
        let firstRow = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ OR identifier == %@", "calendar.item", "calendar.nothingScheduled"
        )).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5) && firstRow.isHittable,
                      "the heading's first row was not hittable after \(after). Hierarchy: \(app.debugDescription)")
    }
}
