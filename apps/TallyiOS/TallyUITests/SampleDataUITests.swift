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

        // Tap, then confirm the app actually navigated (the banner appearing). Two earlier CI
        // runs (36340295516 et al.) proved via the .xcresult's own accessibility-hierarchy
        // attachment that a plain `.tap()` sometimes never reaches the button's action at all —
        // no crash, the app simply stays on Welcome — so this also tries a coordinate tap (which
        // bypasses whatever is wrong with the accessibility-driven hit path) before giving up.
        // Every behaviour past this point (the sample gateway, the model, the Dashboard/tab
        // shell) already has direct unit coverage (SampleDataGatewayTests,
        // SampleDataNoNetworkTests, DashboardBuilderTests); this test's job is only to prove the
        // screens are wired together.
        let banner = app.staticTexts["SAMPLE DATA"]
        for attempt in 1...3 {
            if exploreButton.exists {
                if attempt.isMultiple(of: 2) {
                    exploreButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                } else {
                    exploreButton.tap()
                }
            }
            if banner.waitForExistence(timeout: 5) { break }
            if attempt == 3 {
                XCTFail("Explore with Sample Data never led to the sample-data screen after 3 taps. " +
                        "Hierarchy: \(app.debugDescription)")
            }
        }
        XCTAssertTrue(banner.exists)

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
