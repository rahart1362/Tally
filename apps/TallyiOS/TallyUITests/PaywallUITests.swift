import XCTest

/// M3-B2: the paywall (PAY-05), its placement (PAY-06 (a)-(d)) and the sample-mode path App Review
/// takes (PAY-09), with no network: the demo sign-in and the flagship replay, and the test-only
/// entitlement and App Store (`TestHooks.entitlement`; StoreKit Testing serves nothing to an app a UI
/// test launches on CI). Apple's own sheets (Manage Subscription, Request a Refund, Redeem Code) are
/// never opened here: the hosted tests check that their triggers fire.
final class PaywallUITests: TallyUITestCase {
    private static let demoHost = "canvas.northfield.example"
    private static let accessibilityXXXL = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    /// Every control that offers a purchase or leads to one.
    private static let purchaseControls = ["paywall.purchase", "paywall.price", "subscription.locked.seePlans",
                                           "subscription.refreshBanner.seePlans", "subscription.seePlans"]

    override func tearDownWithError() throws {
        // The demo sign-in's account must not outlive the test: the other suites expect Welcome.
        MainActor.assumeIsolated { LifecycleUITest.resetAppState() }
    }

    // MARK: - PAY-05 and PAY-09: the sample-mode path

    /// Sample data → Settings → Subscription → See Plans → the interstitial → Continue → the paywall,
    /// every element by its identifier; then a purchase (the test App Store's) closes it.
    @MainActor
    func testSampleModeSettingsInterstitialPaywallAndPurchase() throws {
        let app = launchSample(arguments: TestHooks.entitlement("none"))
        openSubscriptionSettings(app)
        for control in ["subscription.restore", "subscription.redeem", "subscription.manage"] {
            XCTAssertTrue(app.buttons[control].exists, "Settings → Subscription has no \(control). Hierarchy: \(app.debugDescription)")
        }
        openPaywallThroughTheInterstitial(app)
        assertPaywall(app, trial: true)

        // The most prominent price: "$9.99/year" is taller than the plan's name.
        let price = element("paywall.price", in: app)
        XCTAssertGreaterThan(price.frame.height, element("paywall.name", in: app).frame.height, "the price is not the most prominent text")

        XCTAssertTrue(scrollUntilHittable(app.buttons["paywall.purchase"], in: app), "the purchase button is out of reach")
        app.buttons["paywall.purchase"].tap()
        XCTAssertTrue(eventually(timeout: scaled(15)) { !self.element("paywall.root", in: app).exists },
                      "the paywall stayed open after the purchase. Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Active until'")).firstMatch
            .waitForExistence(timeout: scaled(10)), "Settings → Subscription did not show the purchase. Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(app.buttons["subscription.refund"].waitForExistence(timeout: scaled(5)),
                      "no Request a Refund for a purchase. Hierarchy: \(app.debugDescription)")
    }

    /// PAY-05 at the largest accessibility size (AX5): everything stays reachable; a screenshot is kept
    /// as the snapshot.
    @MainActor
    func testPaywallAtAccessibilityXXXL() throws {
        let app = launchSample(arguments: TestHooks.entitlement("none") + Self.accessibilityXXXL)
        openSubscriptionSettings(app)
        openPaywallThroughTheInterstitial(app)
        XCTAssertTrue(element("paywall.price", in: app).waitForExistence(timeout: scaled(15)),
                      "no price at AX5. Hierarchy: \(app.debugDescription)")
        let snapshot = XCTAttachment(screenshot: app.screenshot())
        snapshot.name = "Paywall at AX5 (PAY-05)"
        snapshot.lifetime = .keepAlways
        add(snapshot)
        for control in ["paywall.purchase", "paywall.restore", "paywall.redeem"] {
            XCTAssertTrue(scrollUntilHittable(app.buttons[control], in: app), "\(control) is out of reach at AX5")
        }
        XCTAssertTrue(scrollUntilHittable(element("paywall.terms", in: app), in: app), "Terms of Use is out of reach at AX5")
        XCTAssertTrue(scrollUntilHittable(element("paywall.privacy", in: app), in: app), "Privacy Policy is out of reach at AX5")
        assertEveryButtonHasALabel(app, screen: "the paywall at AX5")
    }

    // MARK: - PAY-06: placement

    /// (a) Before sign-in and on "not available at your school": no purchase control at all.
    @MainActor
    func testNoPurchaseControlOnWelcomeOrSchoolNotEnabled() throws {
        let app = launchApp(arguments: TestHooks.entitlement("none"))
        XCTAssertTrue(app.buttons["Find My School"].waitForExistence(timeout: scaled(30)), "Hierarchy: \(app.debugDescription)")
        assertNoPurchaseControls(app, at: "Welcome")
        tapWhenHittable(app.buttons["Find My School"], in: app, timeout: LifecycleUITest.tapTimeout)
        let searchField = app.searchFields.firstMatch
        tapWhenHittable(searchField, in: app, timeout: LifecycleUITest.tapTimeout)
        searchField.typeText("canvas.notenabled.example")
        tapWhenHittable(app.buttons["Use canvas.notenabled.example"], in: app, timeout: LifecycleUITest.tapTimeout)
        XCTAssertTrue(app.buttons["Ask My School"].waitForExistence(timeout: scaled(10)), "Hierarchy: \(app.debugDescription)")
        assertNoPurchaseControls(app, at: "school not enabled")
    }

    /// (b) A first sync that fails (no network: the coordinator's ceiling ends it) shows no purchase
    /// control.
    @MainActor
    func testNoPurchaseControlAfterAFailedFirstSync() throws {
        let app = launchApp(arguments: TestHooks.entitlement("none") + TestHooks.demoSignIn + TestHooks.blockNetwork)
        signInToTheDemoSchool(app)
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: scaled(120)),
                      "the first sync never failed. Hierarchy: \(app.debugDescription)")
        assertNoPurchaseControls(app, at: "the failed first sync")
    }

    /// (c) After the first successful sync renders the Dashboard: the paywall, exactly once. Closed, it
    /// does not come back by itself, in this launch or the next.
    @MainActor
    func testPaywallOnceAfterTheFirstSync() throws {
        let app = launchApp(arguments: TestHooks.entitlement("none") + TestHooks.demoSignIn)
        signInToTheDemoSchool(app)
        XCTAssertTrue(app.staticTexts[TestHooks.flagshipHero].waitForExistence(timeout: scaled(30)),
                      "the first sync never reached the Home. Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(element("paywall.root", in: app).waitForExistence(timeout: scaled(15)),
                      "no paywall after the first sync. Hierarchy: \(app.debugDescription)")
        assertPaywall(app, trial: true)
        tapWhenHittable(app.buttons["paywall.close"], in: app)
        XCTAssertTrue(eventually(timeout: scaled(10)) { !self.element("paywall.root", in: app).exists })
        openTab("Calendar", in: app)
        openTab("Dashboard", in: app)
        XCTAssertFalse(element("paywall.root", in: app).waitForExistence(timeout: scaled(3)), "the paywall came back by itself")
        app.terminate()

        let relaunched = launchApp(arguments: TestHooks.entitlement("none") + TestHooks.replayAccounts)
        XCTAssertTrue(relaunched.staticTexts[TestHooks.flagshipHero].waitForExistence(timeout: scaled(30)),
                      "the relaunch did not reach the Home. Hierarchy: \(relaunched.debugDescription)")
        XCTAssertFalse(element("paywall.root", in: relaunched).waitForExistence(timeout: scaled(5)),
                       "the paywall showed again at a relaunch")
    }

    /// (d) A signed-in account with no trial or subscription: the saved data stays readable under
    /// "Subscribe to refresh"; the locked tabs show the inline card, whose See Plans opens the paywall
    /// (a locked feature).
    @MainActor
    func testLockedTabsShowTheCardThatOpensThePaywall() throws {
        seedFlagshipAccount()
        let app = launchApp(arguments: TestHooks.entitlement("none") + TestHooks.replayAccounts)
        XCTAssertTrue(app.staticTexts[TestHooks.flagshipHero].waitForExistence(timeout: scaled(30)),
                      "the launch did not reach the Home. Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(element("subscription.refreshBanner", in: app).waitForExistence(timeout: scaled(10)),
                      "no 'Subscribe to refresh' over the saved data. Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(element("paywall.root", in: app).exists, "the paywall showed by itself at a launch")

        openTab("Courses", in: app)
        XCTAssertTrue(app.buttons["subscription.locked.seePlans"].waitForExistence(timeout: scaled(10)),
                      "Courses is not locked. Hierarchy: \(app.debugDescription)")
        tapWhenHittable(app.buttons["subscription.locked.seePlans"], in: app)
        XCTAssertTrue(element("paywall.root", in: app).waitForExistence(timeout: scaled(10)),
                      "the locked card did not open the paywall. Hierarchy: \(app.debugDescription)")
        tapWhenHittable(app.buttons["paywall.close"], in: app)
        XCTAssertTrue(eventually(timeout: scaled(10)) { !self.element("paywall.root", in: app).exists })
        for tab in ["Calendar", "To-Do", "Insights"] {
            openTab(tab, in: app)
            XCTAssertTrue(app.buttons["subscription.locked.seePlans"].waitForExistence(timeout: scaled(10)),
                          "\(tab) is not locked. Hierarchy: \(app.debugDescription)")
        }
    }

    // MARK: - Steps

    /// Welcome → Find My School → the demo school → Continue: the first sync starts.
    @MainActor
    private func signInToTheDemoSchool(_ app: XCUIApplication) {
        tapWhenHittable(app.buttons["Find My School"], in: app, timeout: LifecycleUITest.tapTimeout)
        let searchField = app.searchFields.firstMatch
        tapWhenHittable(searchField, in: app, timeout: LifecycleUITest.tapTimeout)
        searchField.typeText(Self.demoHost)
        tapWhenHittable(app.buttons["Use \(Self.demoHost)"], in: app, timeout: LifecycleUITest.tapTimeout)
        tapWhenHittable(app.buttons["Continue to \(Self.demoHost)"], in: app, timeout: LifecycleUITest.tapTimeout)
    }

    /// Settings → Subscription.
    @MainActor
    private func openSubscriptionSettings(_ app: XCUIApplication) {
        openSettings(app)
        let row = app.buttons["settings.subscription"]
        XCTAssertTrue(scrollUntilHittable(row, in: app), "no Subscription row in Settings. Hierarchy: \(app.debugDescription)")
        row.tap()
        XCTAssertTrue(app.navigationBars["Subscription"].waitForExistence(timeout: scaled(10)), "Hierarchy: \(app.debugDescription)")
    }

    /// PAY-09: See Plans → "[Check My School] [Continue]" → Continue.
    @MainActor
    private func openPaywallThroughTheInterstitial(_ app: XCUIApplication) {
        let seePlans = app.buttons["subscription.seePlans"]
        XCTAssertTrue(scrollUntilHittable(seePlans, in: app), "no See Plans. Hierarchy: \(app.debugDescription)")
        seePlans.tap()
        let interstitial = app.alerts.firstMatch
        XCTAssertTrue(interstitial.waitForExistence(timeout: scaled(10)),
                      "sample mode went to the paywall with no interstitial. Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(interstitial.buttons["Check My School"].exists, "Hierarchy: \(app.debugDescription)")
        tapWhenHittable(interstitial.buttons["Continue"], in: app)
        XCTAssertTrue(element("paywall.root", in: app).waitForExistence(timeout: scaled(10)),
                      "Continue did not open the paywall. Hierarchy: \(app.debugDescription)")
    }

    /// PAY-05: every element, by identifier. The test App Store's offer: a year at "$9.99", with the
    /// one-month free trial when eligible.
    @MainActor
    private func assertPaywall(_ app: XCUIApplication, trial: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let price = element("paywall.price", in: app)
        XCTAssertTrue(price.waitForExistence(timeout: scaled(15)), "no price. Hierarchy: \(app.debugDescription)",
                      file: file, line: line)
        XCTAssertEqual(price.label, "$9.99 per year", "VoiceOver's reading of the price", file: file, line: line)
        for id in ["paywall.name", "paywall.duration", "paywall.renewal", "paywall.feature.dueDates",
                   "paywall.feature.reminders", "paywall.feature.privacy", "paywall.terms", "paywall.privacy"] {
            XCTAssertTrue(element(id, in: app).exists, "no \(id). Hierarchy: \(app.debugDescription)", file: file, line: line)
        }
        XCTAssertEqual(element("paywall.trial", in: app).exists, trial, "the trial line", file: file, line: line)
        if trial {
            XCTAssertEqual(element("paywall.trial", in: app).label, "1 month free, then $9.99/year", file: file, line: line)
        }
        for id in ["paywall.purchase", "paywall.restore", "paywall.redeem", "paywall.close"] {
            XCTAssertTrue(app.buttons[id].exists, "no \(id) button. Hierarchy: \(app.debugDescription)", file: file, line: line)
        }
    }

    @MainActor
    private func assertNoPurchaseControls(_ app: XCUIApplication, at place: String, file: StaticString = #filePath,
                                          line: UInt = #line) {
        for id in Self.purchaseControls {
            XCTAssertFalse(element(id, in: app).exists, "\(id) at \(place). Hierarchy: \(app.debugDescription)", file: file, line: line)
        }
        let labels = ["Start Free Trial", "Subscribe", "See Plans"]
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label IN %@", labels)).count, 0,
                       "a purchase button at \(place). Hierarchy: \(app.debugDescription)", file: file, line: line)
    }
}
