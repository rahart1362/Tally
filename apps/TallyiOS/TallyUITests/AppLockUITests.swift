import XCTest

/// SEC-07 / UX-WP-21 (security.md WP-SEC-07; ADR 0001; ux-ui.md §3.7.8; plan 07 §3 item 3) in the
/// running app, over a seeded, signed-in flagship store:
/// - the app locks at cold launch, and a cancel keeps it locked with no alert;
/// - the privacy cover is on screen while the app is inactive (the app switcher, or Notification
///   Center), with a screenshot of it attached to the result;
/// - a return from the background after the grace period locks again;
/// - with the real `LAContext` on the CI simulator (no passcode, no enrolled biometry) the app
///   stays locked, and the only way out it offers is sign-out.
///
/// The scripted device authenticator (`deviceAuth` hook) stands in for Face ID where a test needs a
/// specific answer; the adapter's mapping of every `LAError` is `LocalAuthenticationAdapterTests`.
final class AppLockUITests: TallyUITestCase {
    private static let lockedTitle = "Tally is locked"

    override func tearDownWithError() throws {
        // XCTest runs a synchronous tearDown on the main thread.
        MainActor.assumeIsolated { LifecycleUITest.resetAppState() }
    }

    @MainActor
    func testLocksAtColdLaunchAndACancelKeepsItLockedWithNoAlert() throws {
        seedFlagshipAccount()
        let app = launchApp(arguments: TestHooks.replayAccounts + TestHooks.appLockOn + TestHooks.deviceAuth("cancel"))

        XCTAssertTrue(app.staticTexts[Self.lockedTitle].waitForExistence(timeout: 15),
                      "the app did not lock at cold launch. Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(app.staticTexts[TestHooks.flagshipHero].exists, "cached grades were built under the lock")
        XCTAssertEqual(app.alerts.count, 0, "a cancel raised an alert")

        tapWhenHittable(app.buttons["lock.unlock"], in: app)
        XCTAssertTrue(app.staticTexts[Self.lockedTitle].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["lock.unlock"].waitForExistence(timeout: 5), "the unlock button went away")
        XCTAssertFalse(app.staticTexts[TestHooks.flagshipHero].exists, "a cancel unlocked the app")
        XCTAssertEqual(app.alerts.count, 0, "a cancel raised an alert")
    }

    @MainActor
    func testThePrivacyCoverShowsWhileTheAppIsInactive() throws {
        seedFlagshipAccount()
        let app = launchApp(arguments: TestHooks.replayAccounts + TestHooks.appLockOn + TestHooks.deviceAuth("success"))
        XCTAssertTrue(app.staticTexts[TestHooks.flagshipHero].waitForExistence(timeout: 20),
                      "the unlock never showed the dashboard. Hierarchy: \(app.debugDescription)")
        let cover = app.otherElements["privacy.cover"]
        XCTAssertFalse(cover.exists, "the cover is up while the app is active")

        guard let method = makeInactive(app) else {
            throw XCTSkip("""
                XCUITest could not make the app inactive on this simulator (neither the app switcher \
                gesture nor Notification Center). The cover on .inactive is covered by the hosted \
                AppLockModelTests.privacyCoverOnInactive.
                """)
        }
        XCTAssertTrue(cover.waitForExistence(timeout: 5),
                      "no privacy cover while inactive (\(method)). Hierarchy: \(app.debugDescription)")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "privacy-cover-while-inactive (\(method))"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let appShot = XCTAttachment(screenshot: app.screenshot())
        appShot.name = "privacy-cover-app-window (\(method))"
        appShot.lifetime = .keepAlways
        add(appShot)

        app.activate()
        XCTAssertTrue(waitForScenePhase("active", in: app, timeout: 10), "the app did not become active again")
        XCTAssertTrue(app.staticTexts[TestHooks.flagshipHero].waitForExistence(timeout: 10),
                      "the dashboard did not come back after .inactive. Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(app.staticTexts[Self.lockedTitle].exists, ".inactive alone must not lock")
        XCTAssertFalse(cover.exists, "the cover stayed up once the app was active")
    }

    @MainActor
    func testReturningAfterTheGracePeriodLocksAgain() throws {
        seedFlagshipAccount()
        let app = launchApp(arguments: TestHooks.replayAccounts + TestHooks.appLockOn + TestHooks.appLockGrace("immediately")
                                + TestHooks.deviceAuth("success,cancel"))
        XCTAssertTrue(app.staticTexts[TestHooks.flagshipHero].waitForExistence(timeout: 20),
                      "the first unlock never showed the dashboard. Hierarchy: \(app.debugDescription)")

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10) || app.wait(for: .runningBackgroundSuspended, timeout: 5),
                      "the app never went to the background")
        app.activate()
        XCTAssertTrue(app.staticTexts[Self.lockedTitle].waitForExistence(timeout: 15),
                      "no lock after the grace period. Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(app.staticTexts[TestHooks.flagshipHero].exists)
    }

    @MainActor
    func testTheRealLAContextOnTheSimulatorKeepsTheAppLocked() throws {
        seedFlagshipAccount()
        // No scripted authenticator: `LocalAuthenticationAdapter` over a real `LAContext`.
        let app = launchApp(arguments: TestHooks.replayAccounts + TestHooks.appLockOn)
        XCTAssertTrue(app.staticTexts[Self.lockedTitle].waitForExistence(timeout: 15),
                      "the app did not lock at cold launch. Hierarchy: \(app.debugDescription)")
        // Give the auto-prompt time to fail (or to wait for a Face ID that never comes).
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(app.staticTexts[Self.lockedTitle].exists, "the real LAContext unlocked the app")
        XCTAssertFalse(app.staticTexts[TestHooks.flagshipHero].exists)
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "lock-with-the-real-LAContext"
        evidence.lifetime = .keepAlways
        add(evidence)

        // With no device passcode the lock offers only sign-out (security.md §3.3), and it works.
        let signOut = app.buttons["lock.signOut"]
        if signOut.waitForExistence(timeout: 2) {
            signOut.tap()
            XCTAssertTrue(app.buttons["Find My School"].waitForExistence(timeout: 15),
                          "Sign Out & Erase from the lock did not reach Welcome. Hierarchy: \(app.debugDescription)")
            XCTAssertFalse(app.staticTexts[Self.lockedTitle].exists, "the lock outlived sign-out")
        }
    }

    // MARK: - Making the app inactive

    /// Tries the app switcher, then Notification Center; returns the method that left the app
    /// `.inactive` (read from the test-hook bar, which sits outside the cover), or `nil`.
    @MainActor
    private func makeInactive(_ app: XCUIApplication) -> String? {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let attempts: [(String, () -> Void)] = [
            ("app switcher", {
                let bottom = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.998))
                let middle = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
                bottom.press(forDuration: 0.05, thenDragTo: middle, withVelocity: .slow, thenHoldForDuration: 1.5)
            }),
            ("Notification Center", {
                let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.001))
                let lower = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.6))
                top.press(forDuration: 0.05, thenDragTo: lower)
            }),
        ]
        for (name, gesture) in attempts {
            gesture()
            if waitForScenePhase("inactive", in: app, timeout: 4) { return name }
            app.activate()
            _ = waitForScenePhase("active", in: app, timeout: 10)
        }
        return nil
    }

    @MainActor
    private func waitForScenePhase(_ phase: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let probe = app.staticTexts["testHook.scenePhase"]
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "scene: \(phase)"), object: probe)
        return XCTWaiter().wait(for: [expected], timeout: timeout) == .completed
    }
}
