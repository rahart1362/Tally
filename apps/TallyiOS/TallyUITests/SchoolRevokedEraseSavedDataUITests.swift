import XCTest

/// EB-26 ("Erase Saved Data"): the school-revoked notice's new button, confirmed, erases the
/// signed-in account's saved data without signing out. The flagship account is seeded with its
/// refresh record already failed with `.schoolDisabled` (`TestHooks.schoolRevoked`), so the notice
/// shows at launch over the signed-in Home (PAY-10), with Tally's own identifiers throughout —
/// never the English copy, which Spanish translates.
final class SchoolRevokedEraseSavedDataUITests: TallyUITestCase {
    override func tearDown() {
        // XCTest runs a synchronous tearDown on the main thread.
        MainActor.assumeIsolated { LifecycleUITest.resetAppState() }
        super.tearDown()
    }

    @MainActor
    func testEraseSavedDataClosesTheNoticeWithoutSigningOut() {
        let app = launchApp(arguments: TestHooks.seedFlagship + TestHooks.replayAccounts + TestHooks.schoolRevoked)

        let title = element("schoolOff.title", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: 30), "the school-revoked notice never showed. Hierarchy: \(app.debugDescription)")
        let eraseButton = element("schoolOff.eraseSavedData", in: app)
        XCTAssertTrue(eraseButton.exists)
        // EB-26: the automatic-expiry footnote is part of the same notice.
        XCTAssertTrue(element("schoolOff.autoEraseNotice", in: app).exists)

        tapWhenHittable(eraseButton, in: app, timeout: LifecycleUITest.tapTimeout)

        // D03 round 2's confirmation (`tallyDestructiveConfirmation`): an `.alert` below the
        // accessibility sizes, a full-screen sheet at AX1 and up — either way the confirm action
        // carries this identifier.
        let confirmErase = element("schoolOff.eraseSavedDataConfirm.erase", in: app)
        XCTAssertTrue(confirmErase.waitForExistence(timeout: 10), "the erase confirmation never showed. Hierarchy: \(app.debugDescription)")
        tapWhenHittable(confirmErase, in: app, timeout: LifecycleUITest.tapTimeout)

        // The notice closes (its freshness state is no longer .failed(.schoolDisabled, _) once the
        // coordinator's record resets), and the signed-in Home is still showing underneath it —
        // never Welcome, which would mean this signed the student out.
        XCTAssertTrue(waitUntilGone(title, in: app, timeout: 15), "the notice stayed up after Erase Saved Data. Hierarchy: \(app.debugDescription)")
        openSettings(app)
        // UX2-15 moved the Canvas-links picker into the Account section, pushing Subscription
        // further down (PR run 40108237805).
        XCTAssertTrue(scrollUntilHittable(element("settings.subscription", in: app), in: app), "no Subscription row. Hierarchy: \(app.debugDescription)")
        tapWhenHittable(element("settings.subscription", in: app), in: app)
        XCTAssertTrue(element("subscription.status", in: app).waitForExistence(timeout: 15),
                      "Settings > Subscription never reopened: EB-26 must not sign the student out. Hierarchy: \(app.debugDescription)")
    }

    @MainActor
    func testContinueWithSavedDataStillWorksBesideEraseSavedData() {
        // EB-26's scope: "stay as they are" for the notice's existing buttons.
        let app = launchApp(arguments: TestHooks.seedFlagship + TestHooks.replayAccounts + TestHooks.schoolRevoked)
        let continueButton = element("schoolOff.continue", in: app)
        XCTAssertTrue(continueButton.waitForExistence(timeout: 30), "Hierarchy: \(app.debugDescription)")
        tapWhenHittable(continueButton, in: app, timeout: LifecycleUITest.tapTimeout)
        XCTAssertTrue(waitUntilGone(element("schoolOff.title", in: app), in: app, timeout: 15),
                      "Continue with Saved Data must still close the notice. Hierarchy: \(app.debugDescription)")
    }

    /// Waits until `element` is no longer part of the hierarchy (the opposite of
    /// `waitForExistence`); `XCUIElement` has no built-in wait for this.
    @MainActor
    private func waitUntilGone(_ element: XCUIElement, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: scaled(timeout)) == .completed
    }
}
