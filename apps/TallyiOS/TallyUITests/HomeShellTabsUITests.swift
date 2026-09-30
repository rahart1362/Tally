import XCTest

/// PERF-L (`Launch.HomeRender`): the Home shell builds each tab the first time it is selected, and a
/// built tab keeps its state. Through the tab bar on the flagship sample: every tab shows its
/// screen on its first selection, and a Course Detail pushed on the Courses tab is still there after
/// a round trip through the Dashboard (a tab rebuilt on selection would be back at its list).
/// `HomeShellTabTests` (hosted) checks that the unselected tabs are not built at launch.
final class HomeShellTabsUITests: TallyUITestCase {
    @MainActor
    func testEachTabBuildsOnFirstSelectionAndKeepsItsState() throws {
        let app = launchSample()

        // Each tab's screen appears on its first selection: To-Do and Insights by their navigation
        // titles, Calendar (titled with the month) by its day cells.
        for (tab, screen) in [("To-Do", app.navigationBars["To-Do"]), ("Insights", app.navigationBars["Insights"]),
                              ("Calendar", element("calendar.day", in: app))] {
            openTab(tab, in: app)
            XCTAssertTrue(screen.waitForExistence(timeout: 15),
                          "the \(tab) tab showed no screen on its first selection. Hierarchy: \(app.debugDescription)")
        }

        // A Course Detail pushed on the Courses tab survives a round trip through the Dashboard.
        openTab("Courses", in: app)
        let cards = elements("course.card", in: app)
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
        tapWhenHittable(cards.firstMatch, in: app, timeout: 15)
        let detail = element("courseDetail.hero", in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 10), "Course Detail never opened. Hierarchy: \(app.debugDescription)")

        openTab("Dashboard", in: app)
        XCTAssertTrue(app.staticTexts["Average of 5 courses"].waitForExistence(timeout: 10),
                      "the Dashboard lost its projection. Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(detail.exists, "the Course Detail showed on the Dashboard tab")

        openTab("Courses", in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 10),
                      "the Courses tab lost its pushed Course Detail (rebuilt on selection). Hierarchy: \(app.debugDescription)")
    }
}
