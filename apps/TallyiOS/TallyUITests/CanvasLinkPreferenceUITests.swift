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

        // TOUR-2: PR runs #82 and #83 both saw the menu's "Browser" option never appear after this
        // first tap on the picker (a timing flake in the menu's own presentation, not a miss on
        // the picker itself — the automatic retry passed both times). `tap(_:expecting:)`
        // (`TallyUITestCase`) is the shared "wait for what the tap should open; re-tap once if it
        // hasn't" helper the other suites already use for this exact shape of flake.
        let browser = app.buttons["Browser"]
        tap(picker, expecting: browser, in: app)
        tapWhenHittable(browser, in: app)
        XCTAssertTrue(eventually { (picker.value as? String) == "Browser" || picker.label.contains("Browser") },
                      "did not switch to Browser. Hierarchy: \(app.debugDescription)")
    }
}
