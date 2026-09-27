import XCTest

/// The WP-E02 smoke test: "the app launches and the root view exists".
final class TallyLaunchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesAndRootViewExists() throws {
        let app = XCUIApplication()
        app.launch()

        // The welcome screen's brand heading and both entry actions, per
        // ux-ui.md §3.2 stage 2. Their presence is the "root view exists"
        // check the work package asks for.
        XCTAssertTrue(app.staticTexts["Tally"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Find My School"].exists)
        XCTAssertTrue(app.buttons["Explore with Sample Data"].exists)
    }
}
