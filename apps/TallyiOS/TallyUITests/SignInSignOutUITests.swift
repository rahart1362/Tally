import XCTest

/// Plan 07 M2-C1 L-2 and L-3 (plan 06 steps 9 and 10), end to end with no network: the demo
/// sign-in (`demoSignIn` hook) answers the web-auth sheet at once, exchanges the code at a stubbed
/// token endpoint, and syncs the bundled flagship replay. Then:
/// - the FirstSync page is a plain page in the Welcome stack, and `.finished` is a **root switch**
///   (Welcome is gone from the hierarchy, not merely covered);
/// - sign-out (the test hook's button; Settings' "Sign Out & Erase" is M3-A's) returns to Welcome,
///   and a relaunch stays on Welcome: the account was erased, not just hidden.
final class SignInSignOutUITests: TallyUITestCase {
    private static let demoHost = "canvas.northfield.example"

    override func tearDownWithError() throws {
        MainActor.assumeIsolated { resetAppState() }
    }

    @MainActor
    func testDemoSignInFirstSyncRootSwitchThenSignOut() throws {
        resetAppState()
        let app = launchApp(arguments: TestHooks.demoSignIn + TestHooks.signOutButton)

        tapWhenHittable(app.buttons["Find My School"], in: app)
        let searchField = app.searchFields.firstMatch
        tapWhenHittable(searchField, in: app)
        // A typed Canvas address resolves through the (demo) registry with no network call.
        searchField.typeText(Self.demoHost)
        tapWhenHittable(app.buttons["Use \(Self.demoHost)"], in: app)

        // The sign-in hand-off, then the first sync (a plain page), then the Home as the root.
        tapWhenHittable(app.buttons["Continue to \(Self.demoHost)"], in: app, timeout: 15)
        XCTAssertTrue(app.staticTexts[TestHooks.flagshipHero].waitForExistence(timeout: 30),
                      "the first sync never reached the Home. Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(app.buttons["Find My School"].exists,
                       "Welcome is still in the hierarchy: the first sync pushed the Home instead of switching the root")
        XCTAssertFalse(app.staticTexts["Setting up Tally"].exists, "the FirstSync page is still in the hierarchy")
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].exists)

        // Sign-out: back to Welcome (with the brand moment's heading), then a relaunch stays there.
        tapWhenHittable(app.buttons["testHook.signOut"], in: app)
        XCTAssertTrue(app.buttons["Find My School"].waitForExistence(timeout: 15),
                      "sign-out did not return to Welcome. Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(app.staticTexts[TestHooks.flagshipHero].exists)
        app.terminate()

        let relaunched = launchApp(arguments: TestHooks.replayAccounts)
        XCTAssertTrue(relaunched.buttons["Find My School"].waitForExistence(timeout: 15),
                      "the signed-out account came back at the next launch. Hierarchy: \(relaunched.debugDescription)")
        XCTAssertFalse(relaunched.staticTexts[TestHooks.flagshipHero].exists)
    }
}
