import XCTest

/// Idea 7 ("Open Canvas links in: App / Browser", `pmo-audit/.build-audit/ideas1/report.md`,
/// FEAT-8): the Settings picker that feeds `CanvasLinkOpener`. Defaults to "App" (today's
/// behaviour) and switches to "Browser".
final class CanvasLinkPreferenceUITests: TallyUITestCase {
    @MainActor
    func testOpenCanvasLinksInDefaultsToAppAndCanSwitchToBrowser() throws {
        let app = launchSample()
        openSettings(app)
        let picker = element("settings.canvasLinks", in: app)
        XCTAssertTrue(scrollUntilHittable(picker, in: app), "Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(picker.label.contains("App") || (picker.value as? String) == "App",
                      "default should be App. Hierarchy: \(app.debugDescription)")

        tapWhenHittable(picker, in: app)
        tapWhenHittable(app.buttons["Browser"], in: app)
        XCTAssertTrue(eventually { (picker.value as? String) == "Browser" || picker.label.contains("Browser") },
                      "did not switch to Browser. Hierarchy: \(app.debugDescription)")
    }
}
