import XCTest

/// ASC-14's required UI test: "Welcome → Explore with Sample Data → Dashboard shows the
/// flagship's 5 courses and the Average-of-courses hero."
final class SampleDataUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWelcomeToSampleDataDashboard() throws {
        let app = XCUIApplication()
        app.launch()

        let exploreButton = app.buttons["Explore with Sample Data"]
        XCTAssertTrue(exploreButton.waitForExistence(timeout: 10))
        exploreButton.tap()

        // The persistent SAMPLE DATA banner (ASC-14) is visible immediately.
        let banner = app.staticTexts["SAMPLE DATA"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)")

        // The Dashboard tab is selected by default; its hero states the flagship's course count
        // (5) — this is both "the Average-of-courses hero" and evidence the flagship's 5 courses
        // reached the Dashboard, since a wrong or missing course count would read differently.
        XCTAssertTrue(app.staticTexts["Average of 5 courses"].waitForExistence(timeout: 15))

        // The tab bar itself: five real tabs, "Insights" (never "More").
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].exists)
        XCTAssertTrue(app.tabBars.buttons["Courses"].exists)
        XCTAssertTrue(app.tabBars.buttons["Calendar"].exists)
        XCTAssertTrue(app.tabBars.buttons["To-Do"].exists)
        XCTAssertTrue(app.tabBars.buttons["Insights"].exists)
        XCTAssertFalse(app.tabBars.buttons["More"].exists)

        // Exit returns to Welcome.
        app.buttons["Exit"].tap()
        XCTAssertTrue(app.buttons["Explore with Sample Data"].waitForExistence(timeout: 10))
    }
}
