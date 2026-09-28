import XCTest

/// ASC-14's required UI test ("Welcome → Explore with Sample Data → Dashboard shows the
/// flagship's 5 courses and the Average-of-courses hero"), plus perf-app-runtime.md §7 step 1's
/// root-route acceptance: sample data is a root switch — never a push — from Welcome and from
/// "school not enabled", and it survives repeated entry and exit.
final class SampleDataUITests: XCTestCase {
    private static let exploreLabel = "Explore with Sample Data"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWelcomeToSampleDataDashboard() throws {
        let app = XCUIApplication()
        app.launch()
        enterSampleFromWelcome(app)

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

        exitToWelcome(app)
    }

    /// Welcome → Sample → Exit → Sample → Exit, twice over (perf-app-runtime.md §7 step 1).
    func testSampleEntryAndExitTwice() throws {
        let app = XCUIApplication()
        app.launch()
        for _ in 0..<2 {
            enterSampleFromWelcome(app)
            exitToWelcome(app)
        }
    }

    /// "School not enabled" → "Explore with Sample Data" is the same root switch as Welcome's.
    func testSchoolNotEnabledToSampleData() throws {
        let app = XCUIApplication()
        app.launch()

        let findSchool = app.buttons["Find My School"]
        XCTAssertTrue(findSchool.waitForExistence(timeout: 10))
        findSchool.tap()
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        // A typed Canvas address with no `ClientRegistry` entry (the app ships an empty registry
        // today) resolves to "not enabled" without any network call.
        searchField.typeText("canvas.notenabled.example")
        let useAddress = app.buttons["Use canvas.notenabled.example"]
        XCTAssertTrue(useAddress.waitForExistence(timeout: 5), "Hierarchy: \(app.debugDescription)")
        useAddress.tap()

        XCTAssertTrue(app.buttons["Ask My School"].waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)")
        let candidates = app.buttons.matching(identifier: Self.exploreLabel)
        let explore = (0..<candidates.count).map { candidates.element(boundBy: $0) }.first { $0.isHittable }
        XCTAssertNotNil(explore, "Hierarchy: \(app.debugDescription)")
        explore?.tap()

        assertSampleIsTheRoot(app)
        exitToWelcome(app)
    }

    private func enterSampleFromWelcome(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let exploreButton = app.buttons[Self.exploreLabel]
        XCTAssertTrue(exploreButton.waitForExistence(timeout: 10), file: file, line: line)
        exploreButton.tap()
        assertSampleIsTheRoot(app, file: file, line: line)
    }

    /// The persistent SAMPLE DATA banner (ASC-14) is up, and Welcome is gone from the hierarchy:
    /// the route switched roots. A push would leave the welcome stack (and its button) behind it.
    private func assertSampleIsTheRoot(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts["SAMPLE DATA"].waitForExistence(timeout: 10),
                      "Hierarchy: \(app.debugDescription)", file: file, line: line)
        XCTAssertFalse(app.buttons[Self.exploreLabel].exists,
                       "Welcome is still in the hierarchy, so sample data was pushed, not a root switch",
                       file: file, line: line)
    }

    private func exitToWelcome(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let exit = app.buttons["Exit"]
        XCTAssertTrue(exit.waitForExistence(timeout: 10), file: file, line: line)
        exit.tap()
        XCTAssertTrue(app.buttons[Self.exploreLabel].waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertFalse(app.staticTexts["SAMPLE DATA"].exists, file: file, line: line)
    }
}
