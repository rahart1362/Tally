import XCTest

/// AGE-1 (engineering-backlog-us.md §2 EB-01(h): "a UI test of the consent screen"). Scripts a
/// minor whose significant-change consent was denied (`AgeAssuranceTestHooks`, never real
/// `DeclaredAgeRange`/`PermissionKit` state — those have no effect in the Simulator at all, which
/// is exactly why this hook exists) and confirms `AgeRestrictedView` shows over the signed-in Home
/// instead of the Dashboard.
final class AgeRestrictedUITests: TallyUITestCase {
    private static let demoHost = "canvas.northfield.example"

    override func tearDownWithError() throws {
        // The demo sign-in's account must not outlive the test: the other suites expect Welcome,
        // and this file's own second test signs in again.
        MainActor.assumeIsolated { LifecycleUITest.resetAppState() }
    }

    @MainActor
    func testDeniedSignificantChangeConsentShowsTheRestrictedScreenInsteadOfTheDashboard() throws {
        let app = launchApp(arguments: TestHooks.entitled + TestHooks.demoSignIn + TestHooks.ageRestricted)
        signInToTheDemoSchool(app)
        XCTAssertTrue(element("ageRestricted.screen", in: app).waitForExistence(timeout: scaled(60)),
                      "the restricted screen never appeared. Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(element("ageRestricted.title", in: app).exists, "Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(element("ageRestricted.body", in: app).exists, "Hierarchy: \(app.debugDescription)")
        // EB-01(e): no escape — the Dashboard's own hero text must not be reachable behind it.
        XCTAssertFalse(app.staticTexts[TestHooks.flagshipHero].isHittable,
                       "the Dashboard was reachable behind the restricted screen")
    }

    @MainActor
    func testAllowedAgeAssuranceNeverShowsTheRestrictedScreen() throws {
        // The default every other UI test already exercises implicitly (no `ageRestricted`
        // argument); asserted explicitly here so a future default change is caught by name.
        let app = launchApp(arguments: TestHooks.entitled + TestHooks.demoSignIn)
        signInToTheDemoSchool(app)
        XCTAssertTrue(app.staticTexts[TestHooks.flagshipHero].waitForExistence(timeout: scaled(30)),
                      "the first sync never reached the Home. Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(element("ageRestricted.screen", in: app).waitForExistence(timeout: scaled(3)),
                       "the restricted screen appeared with no reason to")
    }

    /// Welcome → Find My School → the demo school → Continue: the first sync starts (as
    /// `PaywallUITests`' own copy does — each UI test file keeps this small helper to itself).
    @MainActor
    private func signInToTheDemoSchool(_ app: XCUIApplication) {
        tapWhenHittable(app.buttons["Find My School"], in: app, timeout: LifecycleUITest.tapTimeout)
        let searchField = app.searchFields.firstMatch
        tapWhenHittable(searchField, in: app, timeout: LifecycleUITest.tapTimeout)
        searchField.typeText(Self.demoHost)
        tapWhenHittable(app.buttons["Use \(Self.demoHost)"], in: app, timeout: LifecycleUITest.tapTimeout)
        tapWhenHittable(app.buttons["Continue to \(Self.demoHost)"], in: app, timeout: LifecycleUITest.tapTimeout)
    }
}
