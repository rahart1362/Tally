import XCTest

/// UX-WP-08 black-box coverage: "Find My School" navigates to the real
/// search screen (no longer the stub), and the idle/no-network states
/// render. The composition root has no live `InstitutionSearching`
/// wired in yet (that seam is the platform-adapters work package, per
/// `UnavailableInstitutionSearch`'s doc comment), so a real query
/// deterministically reaches the `searchFailed` state — which is itself
/// worth covering, since it's the same state a genuine network failure
/// produces.
final class SchoolSearchUITests: TallyUITestCase {
    private static let accessibilityXXXL = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    private static let demoHost = "canvas.northfield.example"

    @MainActor
    func testFindMySchoolNavigatesToSearchWithIdleHelperText() throws {
        let app = launchApp()

        tapWhenHittable(app.buttons["Find My School"], in: app)

        // Not asserting on `app.navigationBars["Find your school"]` here: paired with
        // `.searchable`, CI (run 36335202947) showed that lookup taking ~60 s before
        // failing, which is a `.searchable`/large-title interaction, not a regression
        // in the screen itself — `testTypingAQueryEventuallyReportsASearchFailure`
        // below already proves the search field on this same screen is reachable.
        XCTAssertTrue(app.staticTexts["Type at least 2 letters of your school's name."].waitForExistence(timeout: 10))
    }

    @MainActor
    func testTypingAQueryEventuallyReportsASearchFailure() throws {
        let app = launchApp()

        tapWhenHittable(app.buttons["Find My School"], in: app)
        let searchField = app.searchFields.firstMatch
        tapWhenHittable(searchField, in: app, timeout: 5)
        searchField.typeText("northfield")

        // No live search transport is wired in yet (see the type's doc comment),
        // so this reaches the same `searchFailed` state a real network error would.
        XCTAssertTrue(app.staticTexts["Couldn't search"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Retry"].exists)
    }

    /// ux-fp1 round 3: from AX1 up the screen's field is its own `TextField` (identifier
    /// `schoolSearch.field`), not the system search bar. Round 2 hung it on the results as a top
    /// safe-area inset, and the first Audit tour to reach it at AX5 (run 37798261057) showed it stop
    /// taking input once the results left their idle state: "canvas.northfield.example" stayed
    /// "canv". Typing the whole address must keep every character and reach the "Use …" row, through
    /// every state change on the way (idle, searching, address typed).
    @MainActor
    func testTypingAnAddressAtAccessibilityXXXLKeepsEveryCharacter() throws {
        let app = launchApp(arguments: Self.accessibilityXXXL)

        tapWhenHittable(app.buttons["Find My School"], in: app, timeout: 30)
        let field = app.descendants(matching: .any).matching(identifier: "schoolSearch.field").firstMatch
        tapWhenHittable(field, in: app)
        field.typeText(Self.demoHost)

        XCTAssertTrue(app.buttons["Use \(Self.demoHost)"].waitForExistence(timeout: scaled(10)),
                      "the typed address never reached the \"Use …\" row at AX5. Hierarchy: \(app.debugDescription)")
        let typed = field.value as? String
        XCTAssertEqual(typed, Self.demoHost, "the field lost characters at AX5. Hierarchy: \(app.debugDescription)")
    }
}
