import XCTest

/// perf-app-runtime.md §7 step 3: Welcome's two entry actions are pinned above the bottom safe
/// area, so both are on screen and hittable from launch, at the default text size and at the largest
/// accessibility size, without scrolling. CI runs this class on the default simulator and again on
/// the smallest available iPhone (`scripts/ci/pick_ios_simulator.py --smallest`).
final class WelcomeCTAUITests: TallyUITestCase {
    private static let ctaLabels = ["Find My School", "Explore with Sample Data"]
    private static let accessibilityXXXL = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    /// A benefit row's words: scrolling content, never capped (unlike the pinned actions, ux-fp2 D05).
    private static let benefit = "See where you stand"
    /// The start of app-store-compliance.md R10's disclaimer, the last thing on the page.
    private static let disclaimerStart = "Tally is an independent app"

    @MainActor
    func testBothCTAsAreHittableRightAfterLaunch() {
        let app = launchApp()
        assertCTAsAreHittable(in: app)
    }

    /// The Dynamic Type launch argument is UNVERIFIED on iOS 26 (perf-app-runtime.md §7 step 3),
    /// so this test also proves it took effect: the benefit row's words must be clearly taller than
    /// at the default size, or the hittability check below would prove nothing about large text.
    ///
    /// ux-fp2 D05: the proof used to be the primary CTA's own height. The pinned actions are now
    /// drawn at most at AX2 (`TallyReflow.pinnedChromeMaximumSize`), about 1.4 times their default
    /// height, too close to this check's 1.3 to prove anything, so it reads scrolling text instead.
    @MainActor
    func testBothCTAsAreHittableAtAccessibilityXXXL() {
        let standard = launchApp()
        let standardBenefit = standard.staticTexts[Self.benefit].firstMatch
        XCTAssertTrue(standardBenefit.waitForExistence(timeout: scaled(10)), "Hierarchy: \(standard.debugDescription)")
        let standardHeight = standardBenefit.frame.height
        standard.terminate()

        let large = launchApp(arguments: Self.accessibilityXXXL)
        assertCTAsAreHittable(in: large)
        let largeBenefit = large.staticTexts[Self.benefit].firstMatch
        XCTAssertTrue(largeBenefit.waitForExistence(timeout: scaled(10)), "Hierarchy: \(large.debugDescription)")
        let largeHeight = largeBenefit.frame.height
        XCTAssertGreaterThan(largeHeight, standardHeight * 1.3,
                             "The AX XXXL launch argument did not enlarge the text (\(standardHeight) pt -> \(largeHeight) pt)")
    }

    /// ux-fp2 D05 (S1): at AX XXXL the pinned actions took half the smallest iPhone's screen and hid
    /// the benefits and the R10 disclaimer under them. Both now scroll into view above the actions,
    /// which stay on screen the whole way.
    @MainActor
    func testBenefitsAndDisclaimerScrollIntoViewAtAccessibilityXXXL() {
        let app = launchApp(arguments: Self.accessibilityXXXL)
        assertCTAsAreHittable(in: app)
        let actionsTop = app.buttons[Self.ctaLabels[0]].frame.minY

        let disclaimer = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", Self.disclaimerStart)).firstMatch
        XCTAssertTrue(disclaimer.waitForExistence(timeout: scaled(10)), "no R10 disclaimer. Hierarchy: \(app.debugDescription)")
        // Full-speed swipes: the page only ends at the disclaimer, so overshooting is harmless, and
        // slow ones took 115 s on the smallest iPhone (CI run 37841711587).
        var swipes = 0
        while disclaimer.frame.maxY > actionsTop, swipes < Self.maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        let disclaimerBottom = disclaimer.frame.maxY
        XCTAssertLessThanOrEqual(disclaimerBottom, actionsTop,
                                 "the disclaimer never cleared the pinned actions (\(disclaimerBottom) > \(actionsTop)) after \(swipes) swipes")
        XCTAssertTrue(disclaimer.isHittable, "the disclaimer is on screen but covered. Hierarchy: \(app.debugDescription)")
        // The benefits came by on the way down: the last one is above the actions too.
        let lastBenefit = app.staticTexts["Private by design"].firstMatch
        let lastBenefitBottom = lastBenefit.frame.maxY
        XCTAssertLessThanOrEqual(lastBenefitBottom, actionsTop, "'Private by design' is still under the pinned actions")
        assertCTAsAreHittable(in: app)
    }

    /// How many swipes the AX XXXL page may need to reach its end on the smallest iPhone.
    private static let maxSwipes = 8

    /// "Right after launch" means without scrolling or any other step: each CTA must be on screen
    /// and hittable as the app settles. The wait is a predicate on `isHittable` (`waitUntilHittable`),
    /// not one read the moment the button exists: CI run 37810483577 read "not hittable" once while
    /// the launch was still settling (a flake, not a layout fault).
    @MainActor
    private func assertCTAsAreHittable(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for label in Self.ctaLabels {
            waitUntilHittable(app.buttons[label], in: app, timeout: 10, file: file, line: line)
        }
    }
}
