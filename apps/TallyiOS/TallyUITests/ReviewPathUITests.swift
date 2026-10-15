import XCTest

/// MVP-4, O6: the owner's decision that **Sample Data mode is the App Review path** -- the full
/// app on a synthetic student, no account, no real school (dossier.md "Owner decision O6";
/// Guideline 2.1(a)'s built-in demo-mode exception, "with prior approval by Apple", requested in
/// `docs/release/app-store/en-US/review_notes.txt`, EB-13). This file is that path's proof, end to
/// end from a fresh install:
///
///   - **no sign-in is required**: the walk never visits "Find My School" or a web-auth sheet.
///     Welcome's own "Explore with Sample Data" is a root switch (`AppModel.enterSample()`),
///     never a push, so once it fires Welcome -- and the only way to reach sign-in -- is gone
///     from the hierarchy for the rest of the walk (`runReviewPathWalk` below, checked right
///     after the tap).
///   - **no network request leaves the app**: every seam the composition root wires an
///     `HTTPTransport` into (the account's own gateway, the sign-in token exchange, institution
///     search -- `AppEnvironment.live()` and `SignInServices`'s own defaults, the same two
///     places `scripts/ci/check_policy_matches_app.py` reads for EB-07) traps instead of
///     sending, and records the attempt instead of fabricating a response
///     (`LaunchTestHooks.Key.trapAllNetwork`, new for this proof: the existing `blockNetwork`
///     hook only replaces one signed-in account's gateway, which Sample Data never builds, so it
///     would prove nothing here). The count is read from `testHook.networkProbe`, the exact
///     identifier `LaunchRefreshThrottleUITests` already reads for the same counter
///     (`LaunchProbe`). Sample Data's own data path (`SampleDataCanvasGateway`,
///     `SampleDataGateway.swift`) has no `HTTPTransport` dependency in its own init at all -- it
///     replays bundled fixtures from `TallySampleFixtures` -- so this is defence in depth for
///     every OTHER seam the walk might touch, not sample mode's own path, which cannot reach the
///     network by construction. **Scope**: this traps TallyCore's one HTTP transport, the app's
///     only network path (dossier.md F4). It does not and cannot reach StoreKit, which is
///     Apple's own system (dossier.md F9) -- the paywall step below only ever DISPLAYS a price
///     StoreKit Testing already holds locally; it never purchases (PAY-09's own `PaywallUITests`
///     covers a purchase).
///   - **every screen shows content**: Dashboard, Courses, Course detail with What-If, To-Do with
///     Mark Done, Calendar, Insights, Settings, parent mode (the Sample Data family, FAM-14's own
///     "App Review path" comment) and the paywall's display.
///
/// Every lookup is an accessibility identifier, never an English label, with one unavoidable
/// exception each for two pieces of system chrome that carry no identifier of their own to
/// XCUITest: the tab bar (`Tab(_:systemImage:value:)` does not expose one -- `AuditTourUITests`'
/// own finding, run 38175021381, which this file's `tabLabel` mirrors) and the Subscription
/// interstitial's `.alert` buttons (a plain SwiftUI `.alert` action has no identifier API at
/// all). Both read English only, and only `ReviewPathUITests` (the English leg) uses them:
/// `ReviewPathSpanishUITests` below uses the tab-bar table in Spanish and skips the interstitial
/// (and the paywall step after it) rather than depend on an `.alert`'s label text in a second
/// language.
class ReviewPathUITestsBase: TallyUITestCase {
    override func tearDownWithError() throws {
        // Leave Welcome for whichever suite runs next (every lifecycle suite does this).
        MainActor.assumeIsolated { LifecycleUITest.resetAppState() }
    }

    private enum ReviewTab { case dashboard, courses, calendar, toDo, insights }

    /// Matches `AuditTourUITests.tabLabel`'s own table (private there; this walk needs its own
    /// copy, since the tab bar itself carries no accessibility identifier to XCUITest).
    private func tabLabel(_ tab: ReviewTab, locale: String) -> String {
        let labels: [ReviewTab: [String: String]] = [
            .dashboard: ["en": "Dashboard", "es": "Tablero"],
            .courses: ["en": "Courses", "es": "Cursos"],
            .calendar: ["en": "Calendar", "es": "Calendario"],
            .toDo: ["en": "To-Do", "es": "Por hacer"],
            .insights: ["en": "Insights", "es": "Estadísticas"],
        ]
        return labels[tab]?[locale] ?? labels[tab]?["en"] ?? ""
    }

    /// The whole review path, from a fresh install to parent mode, optionally through the
    /// paywall's display. One method, reused by both the English and Spanish legs, so the two
    /// can never silently drift apart.
    @MainActor
    func runReviewPathWalk(locale: String, showsPaywall: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        resetAppState(file: file, line: line) // O6: "a fresh install".

        var arguments = TestHooks.trapAllNetwork
        // Only not-entitled shows "See Plans" (SubscriptionSettingsView: `if !isActive`); every
        // other launch in this suite keeps the base class's default entitled state.
        if showsPaywall { arguments += TestHooks.entitlement("none") }
        let app = launchApp(arguments: arguments)

        // --- Welcome: both entry actions exist, neither needs a Canvas account. ---------------
        let exploreSampleData = element("account.exploreWithSampleData", in: app)
        XCTAssertTrue(exploreSampleData.waitForExistence(timeout: 30), "Hierarchy: \(app.debugDescription)", file: file, line: line)
        XCTAssertTrue(element("account.findMySchool", in: app).exists, "Hierarchy: \(app.debugDescription)", file: file, line: line)
        // EB-06: the Welcome footer's Privacy Policy link, unobtrusive beside the disclaimer.
        XCTAssertTrue(element("account.privacyPolicy", in: app).exists,
                     "EB-06's Welcome footer Privacy Policy link is missing. Hierarchy: \(app.debugDescription)",
                     file: file, line: line)

        // --- O6: "Explore with Sample Data" -- a root switch, never a push; no sign-in. -------
        exploreSampleData.tap()
        let hero = element("dashboard.hero.averageOfCourses", in: app)
        XCTAssertTrue(hero.waitForExistence(timeout: 30), "the sample projection never landed. Hierarchy: \(app.debugDescription)",
                     file: file, line: line)
        XCTAssertFalse(exploreSampleData.exists,
                       "Welcome -- and the only way to reach sign-in -- is still in the hierarchy: a push, not a root switch",
                       file: file, line: line)

        // --- Dashboard: already proven content (the hero above). ------------------------------

        // --- Courses, then Course detail with What-If. ----------------------------------------
        openTab(tabLabel(.courses, locale: locale), in: app)
        let card = element("course.card", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Courses shows no content. Hierarchy: \(app.debugDescription)",
                     file: file, line: line)
        tapWhenHittable(card, in: app, timeout: 15, file: file, line: line)
        let courseDetailHero = element("courseDetail.hero", in: app)
        XCTAssertTrue(courseDetailHero.waitForExistence(timeout: 15), "Course detail shows no content. Hierarchy: \(app.debugDescription)",
                     file: file, line: line)
        let whatIf = element("courseDetail.whatIf", in: app)
        if scrollUntilHittable(whatIf, in: app) {
            whatIf.tap()
            // `whatif.projected` is the sticky summary (`WhatIfSummary`), shown unconditionally
            // whenever the sheet opens, unlike the per-item controls (slider/stepper), which vary
            // with the item's own type.
            XCTAssertTrue(element("whatif.projected", in: app).waitForExistence(timeout: 10),
                         "What-If opened with no content. Hierarchy: \(app.debugDescription)", file: file, line: line)
            tapWhenHittable(element("whatif.done", in: app), in: app, file: file, line: line)
        } else {
            // A course without a What-If setup (`detail.whatIfUnavailable`) shows the disabled
            // row instead; the flagship persona has at least one course that offers it, but this
            // keeps the walk from failing outright if the first card tapped happens not to.
            XCTAssertTrue(element("courseDetail.whatIf.disabled", in: app).exists || whatIf.exists,
                         "neither What-If nor its disabled row is on Course detail. Hierarchy: \(app.debugDescription)",
                         file: file, line: line)
        }

        // --- To-Do, with Mark Done. ------------------------------------------------------------
        openTab(tabLabel(.toDo, locale: locale), in: app)
        let notDoneRows = elements("todo.row.notDone", in: app)
        XCTAssertTrue(eventually(timeout: 15) { notDoneRows.count > 0 }, "To-Do shows no content. Hierarchy: \(app.debugDescription)",
                     file: file, line: line)
        let doneRowsBefore = elements("todo.row.done", in: app).count
        tapWhenHittable(element("todo.complete", in: app), in: app, file: file, line: line)
        XCTAssertTrue(eventually(timeout: 10) { elements("todo.row.done", in: app).count > doneRowsBefore },
                     "Mark Done did not flip a row. Hierarchy: \(app.debugDescription)", file: file, line: line)

        // --- Calendar. ---------------------------------------------------------------------------
        openTab(tabLabel(.calendar, locale: locale), in: app)
        XCTAssertTrue(element("calendar.day", in: app).waitForExistence(timeout: 15),
                     "Calendar shows no content. Hierarchy: \(app.debugDescription)", file: file, line: line)

        // --- Insights. ---------------------------------------------------------------------------
        openTab(tabLabel(.insights, locale: locale), in: app)
        XCTAssertTrue(element("chart.trend", in: app).waitForExistence(timeout: 30),
                     "Insights shows no content. Hierarchy: \(app.debugDescription)", file: file, line: line)

        // --- Settings, visit 1: the paywall (English only), then About (bottom of the Form). ---
        // `accountSection` (Subscription) sits above `aboutSection` (Version, Privacy Policy) in
        // `SettingsView.body`, and `scrollUntilHittable` only ever scrolls forward (down) -- so
        // the paywall step, which needs Subscription, comes first, in the same visit, before
        // scrolling on down to About. Parent mode (below Subscription, above About) is a SEPARATE
        // visit below: `family.sample.viewAsParent` dismisses Settings the instant it is tapped,
        // which would otherwise skip straight past About.
        if showsPaywall {
            openSubscriptionSettings(app)
            openPaywallThroughTheInterstitial(app)
            XCTAssertTrue(element("paywall.root", in: app).exists, "Hierarchy: \(app.debugDescription)", file: file, line: line)
            tapWhenHittable(element("paywall.close", in: app), in: app, file: file, line: line)
            XCTAssertFalse(element("paywall.root", in: app).exists, "the paywall stayed open. Hierarchy: \(app.debugDescription)",
                           file: file, line: line)
            // Back from the pushed Subscription page to Settings' own root: the leading item in
            // a `NavigationStack` page's bar is always the back control, whatever its label reads
            // in this leg's language.
            tapWhenHittable(app.navigationBars.buttons.element(boundBy: 0), in: app, file: file, line: line)
        } else {
            openSettings(app, file: file, line: line)
        }

        let version = element("settings.version", in: app)
        XCTAssertTrue(scrollUntilHittable(version, in: app), "no settings.version. Hierarchy: \(app.debugDescription)",
                     file: file, line: line)
        let privacyPolicyRow = element("settings.privacyPolicy", in: app)
        XCTAssertTrue(scrollUntilHittable(privacyPolicyRow, in: app),
                     "EB-06's Settings → About Privacy Policy row is missing. Hierarchy: \(app.debugDescription)",
                     file: file, line: line)
        tapWhenHittable(element("settings.done", in: app), in: app, file: file, line: line)

        // --- Settings, visit 2: parent mode -- the Sample Data family (FAM-14's own "App Review
        // path" comment). A fresh visit starts back at the top of the Form.
        openSettings(app, file: file, line: line)
        let exploreParentMode = element("family.sample.viewAsParent", in: app)
        XCTAssertTrue(scrollUntilHittable(exploreParentMode, in: app, maxSwipes: 30),
                     "no family.sample.viewAsParent. Hierarchy: \(app.debugDescription)", file: file, line: line)
        exploreParentMode.tap() // Settings dismisses itself (AppModel.enterSampleFamily()).
        let switcher = element("family.switcher", in: app)
        XCTAssertTrue(switcher.waitForExistence(timeout: 15), "parent mode shows no content. Hierarchy: \(app.debugDescription)",
                     file: file, line: line)

        // --- O6, confirmed cumulatively over the whole walk: zero network requests. ------------
        // A sign-in attempt is itself a network request (the token exchange), so this one check
        // also stands as the walk's proof that no sign-in happened, not only that none was asked
        // for.
        let probe = element("testHook.networkProbe", in: app)
        XCTAssertTrue(probe.waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)", file: file, line: line)
        XCTAssertTrue(probe.label.hasSuffix("\u{00B7} 0 requests"),
                     "a network request left the app during the review path: \(probe.label)", file: file, line: line)
    }
}

/// The English leg: the full walk, including the paywall's display (PAY-09's required review
/// path -- App Review buys from sample mode too, but this proof only ever displays the price;
/// `PaywallUITests` covers a purchase).
final class ReviewPathUITests: ReviewPathUITestsBase {
    @MainActor
    func testReviewPathShowsEveryScreenWithNoSignInAndNoNetwork() throws {
        try runReviewPathWalk(locale: "en", showsPaywall: true)
    }
}

/// The Spanish leg (the brief's "run it in both en and es if the launch-argument pin allows"):
/// the same walk, in `TallyUITestCase`'s other shipping language, minus the paywall step -- the
/// Subscription interstitial is a plain SwiftUI `.alert`, whose buttons carry no accessibility
/// identifier in either language, and this file does not depend on an `.alert`'s English label
/// the way `PaywallUITests`' own (English-only) helpers do.
final class ReviewPathSpanishUITests: ReviewPathUITestsBase {
    override class var currentLocaleArguments: [String] { ["-AppleLanguages", "(es)", "-AppleLocale", "es_US"] }

    @MainActor
    func testReviewPathInSpanishShowsEveryScreenWithNoSignInAndNoNetwork() throws {
        try runReviewPathWalk(locale: "es", showsPaywall: false)
    }
}
