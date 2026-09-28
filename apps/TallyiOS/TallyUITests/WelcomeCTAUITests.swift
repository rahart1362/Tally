import XCTest

/// perf-app-runtime.md §7 step 3: Welcome's two entry actions are pinned above the bottom safe
/// area, so both are hittable right after launch, at the default text size and at the largest
/// accessibility size. CI runs this class on the default simulator and again on the smallest
/// available iPhone (`scripts/ci/pick_ios_simulator.py --smallest`).
final class WelcomeCTAUITests: TallyUITestCase {
    private static let ctaLabels = ["Find My School", "Explore with Sample Data"]
    private static let accessibilityXXXL = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    @MainActor
    func testBothCTAsAreHittableRightAfterLaunch() {
        let app = launchApp()
        assertCTAsAreHittable(in: app)
    }

    /// The Dynamic Type launch argument is UNVERIFIED on iOS 26 (perf-app-runtime.md §7 step 3),
    /// so this test also proves it took effect: the primary CTA must be clearly taller than at
    /// the default size, or the hittability check below would prove nothing about large text.
    @MainActor
    func testBothCTAsAreHittableAtAccessibilityXXXL() {
        let standard = launchApp()
        let standardButton = standard.buttons[Self.ctaLabels[0]]
        XCTAssertTrue(standardButton.waitForExistence(timeout: 10), "Hierarchy: \(standard.debugDescription)")
        let standardHeight = standardButton.frame.height
        standard.terminate()

        let large = launchApp(arguments: Self.accessibilityXXXL)
        assertCTAsAreHittable(in: large)
        let largeHeight = large.buttons[Self.ctaLabels[0]].frame.height
        XCTAssertGreaterThan(largeHeight, standardHeight * 1.3,
                             "The AX XXXL launch argument did not enlarge the CTA (\(standardHeight) pt -> \(largeHeight) pt)")
    }

    /// No waiting for hittability here: "right after launch" is the requirement, so each CTA
    /// must be hittable the moment it exists.
    @MainActor
    private func assertCTAsAreHittable(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for label in Self.ctaLabels {
            let button = app.buttons[label]
            XCTAssertTrue(button.waitForExistence(timeout: 10),
                          "\(label) is missing. Hierarchy: \(app.debugDescription)", file: file, line: line)
            XCTAssertTrue(button.isHittable,
                          "\(label) is not hittable right after launch. Hierarchy: \(app.debugDescription)",
                          file: file, line: line)
        }
    }
}
