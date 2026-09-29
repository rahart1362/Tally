import XCTest

/// A PMO screenshot tour: walks every screen the app has today, in sample-data mode, and keeps a
/// named screenshot of each (`lifetime = .keepAlways`). CI exports the images from the result bundle
/// for the owner's "current screens" page. It asserts nothing beyond reaching each screen: a step
/// that cannot be reached is recorded as such, and the tour goes on.
final class ScreenshotTourUITests: TallyUITestCase {
    private static let accessibilityXXXL = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    @MainActor
    func testTourOfCurrentScreens() throws {
        continueAfterFailure = true
        let app = launchApp()

        let explore = app.buttons["Explore with Sample Data"]
        _ = explore.waitForExistence(timeout: 30)
        snap(app, "01 Welcome")

        // Onboarding: school search, then a Canvas address with no registry entry ("not enabled").
        if tap(app.buttons["Find My School"], in: app) {
            let field = app.searchFields.firstMatch
            _ = field.waitForExistence(timeout: 10)
            snap(app, "02 Find your school")
            if tap(field, in: app) {
                field.typeText("canvas.notenabled.example")
                snap(app, "03 School search, typed address")
                if tap(app.buttons["Use canvas.notenabled.example"], in: app) {
                    _ = app.buttons["Ask My School"].waitForExistence(timeout: 10)
                    snap(app, "04 School not enabled (Ask My School)")
                }
            }
            // The Welcome stack sits under this page: pick the hittable "Explore" button.
            let candidates = app.buttons.matching(identifier: "Explore with Sample Data")
            let hittable = (0..<candidates.count).map { candidates.element(boundBy: $0) }.first { $0.isHittable }
            hittable?.tap()
        } else {
            _ = tap(explore, in: app)
        }

        // Sample data: the Home tab shell.
        _ = app.staticTexts["Average of 5 courses"].waitForExistence(timeout: 30)
        snap(app, "05 Dashboard (sample data)")
        app.swipeUp()
        snap(app, "06 Dashboard, scrolled")
        app.swipeUp()
        snap(app, "07 Dashboard, further down")
        app.swipeDown(); app.swipeDown()

        // Courses, then one course's detail and its what-if sheet (M3-A).
        if tap(app.tabBars.buttons["Courses"], in: app) {
            sleepBriefly()
            snap(app, "08 Courses")
            let cards = app.descendants(matching: .any).matching(identifier: "course.card")
            if cards.count > 1, tap(cards.element(boundBy: 1), in: app) {
                sleepBriefly()
                snap(app, "09 Course Detail")
                if tap(app.buttons["Grades"], in: app) {
                    sleepBriefly()
                    snap(app, "10 Course Detail, Grades")
                    _ = tap(app.buttons["Overview"], in: app)
                }
                let whatIf = app.descendants(matching: .any).matching(identifier: "courseDetail.whatIf").firstMatch
                for _ in 0..<6 where !whatIf.isHittable { app.swipeUp() }
                if tap(whatIf, in: app) {
                    sleepBriefly()
                    snap(app, "11 What-if sheet")
                    let sheetBar = app.navigationBars["What-If"]
                    if sheetBar.waitForExistence(timeout: 5) { sheetBar.swipeUp() }
                    sleepBriefly()
                    snap(app, "12 What-if sheet, expanded")
                    // Close it with Done (a swipe on the bar did not dismiss it in run 36530758199).
                    _ = tap(app.navigationBars["What-If"].buttons["Done"], in: app)
                    sleepBriefly()
                }
            }
        }
        for (number, tab) in [("13", "Calendar"), ("14", "To-Do"), ("16", "Insights")] {
            if tap(app.tabBars.buttons[tab], in: app) {
                sleepBriefly()
                snap(app, "\(number) \(tab)")
                if tab == "To-Do", tap(app.buttons["todo.select"], in: app) {
                    sleepBriefly()
                    snap(app, "15 To-Do, select mode")
                    _ = tap(app.buttons["todo.select"], in: app) // now "Cancel"
                }
                if tab == "Insights" {
                    app.swipeUp()
                    sleepBriefly()
                    snap(app, "17 Insights, scrolled")
                }
            }
        }
        if tap(app.tabBars.buttons["Dashboard"], in: app) {
            let settings = app.buttons["Settings"]
            if tap(settings, in: app) {
                sleepBriefly()
                snap(app, "18 Settings")
                app.swipeUp()
                sleepBriefly()
                snap(app, "19 Settings, scrolled")
                app.swipeUp()
                sleepBriefly()
                snap(app, "20 Settings, further down")
                app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast); app.swipeDown(velocity: .fast)
            }
        }

        // The hero's Refresh button starts a manual refresh: the footer shows "Refreshing…".
        let refresh = app.buttons["Refresh"]
        if tap(refresh, in: app) {
            snap(app, "21 Refreshing")
        }
        app.terminate()

        // The Dashboard again at the largest accessibility text size.
        let large = launchApp(arguments: Self.accessibilityXXXL)
        _ = large.buttons["Explore with Sample Data"].waitForExistence(timeout: 30)
        snap(large, "22 Welcome at AX XXXL")
        if tap(large.buttons["Explore with Sample Data"], in: large) {
            _ = large.staticTexts["SAMPLE DATA"].waitForExistence(timeout: 30)
            sleepBriefly()
            snap(large, "23 Dashboard at AX XXXL")
        }
    }

    // MARK: - Helpers

    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Taps `element` if it becomes hittable within `timeout`; records the miss otherwise.
    @MainActor
    private func tap(_ element: XCUIElement, in app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
        guard element.waitForExistence(timeout: timeout) else {
            snap(app, "missing \(element)")
            return false
        }
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        guard XCTWaiter().wait(for: [hittable], timeout: timeout) == .completed else {
            snap(app, "not hittable \(element)")
            return false
        }
        element.tap()
        return true
    }

    /// Lets a tab switch or sheet animation finish before the screenshot.
    private func sleepBriefly() { Thread.sleep(forTimeInterval: 1.5) }
}
