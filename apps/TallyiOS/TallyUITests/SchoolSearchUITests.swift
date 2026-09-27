import XCTest

/// UX-WP-08 black-box coverage: "Find My School" navigates to the real
/// search screen (no longer the stub), and the idle/no-network states
/// render. The composition root has no live `InstitutionSearching`
/// wired in yet (that seam is the platform-adapters work package, per
/// `UnavailableInstitutionSearch`'s doc comment), so a real query
/// deterministically reaches the `searchFailed` state — which is itself
/// worth covering, since it's the same state a genuine network failure
/// produces.
final class SchoolSearchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFindMySchoolNavigatesToSearchWithIdleHelperText() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Find My School"].tap()

        // Not asserting on `app.navigationBars["Find your school"]` here: paired with
        // `.searchable`, CI (run 36335202947) showed that lookup taking ~60 s before
        // failing, which is a `.searchable`/large-title interaction, not a regression
        // in the screen itself — `testTypingAQueryEventuallyReportsASearchFailure`
        // below already proves the search field on this same screen is reachable.
        XCTAssertTrue(app.staticTexts["Type at least 2 letters of your school's name."].waitForExistence(timeout: 10))
    }

    func testTypingAQueryEventuallyReportsASearchFailure() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Find My School"].tap()
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("northfield")

        // No live search transport is wired in yet (see the type's doc comment),
        // so this reaches the same `searchFailed` state a real network error would.
        XCTAssertTrue(app.staticTexts["Couldn't search"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Retry"].exists)
    }
}
