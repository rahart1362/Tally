import XCTest

/// PMO marketing tour (branch `pmo/flyer-tour` only, never merged): the app's strongest screens in
/// sample-data mode, kept as named screenshots for the go-to-market flyer. It asserts nothing: a step
/// that cannot be reached is recorded as a "missing" screenshot and the tour goes on.
final class MarketingTourUITests: TallyUITestCase {
    @MainActor
    func testMarketingTour() throws {
        continueAfterFailure = true
        XCUIDevice.shared.appearance = .light

        // 1. Signed in (the seeded flagship account on the bundled replay: fictional, offline, and no
        //    "Sample data" banner), the screens a student sees every day.
        let app = launchApp(arguments: TestHooks.seedFlagship + TestHooks.replayAccounts)
        _ = app.staticTexts[TestHooks.flagshipHero].waitForExistence(timeout: 30)
        settle(); settle(); snap(app, "M02 Dashboard")
        app.swipeUp(); settle(); snap(app, "M03 Dashboard, scrolled")
        app.swipeDown(); app.swipeDown()

        if go(app.tabBars.buttons["Courses"], app) {
            settle(); settle(); snap(app, "M04 Courses")
            let cards = app.descendants(matching: .any).matching(identifier: "course.card")
            if cards.count > 0, go(cards.element(boundBy: 0), app) {
                settle(); snap(app, "M05 Course Detail")
                if go(app.buttons["Grades"], app) {
                    settle(); snap(app, "M06 Course Detail, Grades")
                    _ = go(app.buttons["Overview"], app)
                }
                let whatIf = app.descendants(matching: .any).matching(identifier: "courseDetail.whatIf").firstMatch
                for _ in 0..<6 where !whatIf.isHittable { app.swipeUp() }
                if go(whatIf, app) {
                    settle()
                    let bar = app.navigationBars["What-If"]
                    if bar.waitForExistence(timeout: 5) { bar.swipeUp() }
                    settle(); snap(app, "M07 What-if")
                    _ = go(app.navigationBars["What-If"].buttons["Done"], app)
                }
            }
        }
        for (name, tab) in [("M08 Calendar", "Calendar"), ("M09 To-Do", "To-Do"), ("M10 Insights", "Insights")] {
            if go(app.tabBars.buttons[tab], app) { settle(); snap(app, name) }
        }
        app.swipeUp(); settle(); snap(app, "M11 Insights, scrolled")
        if go(app.tabBars.buttons["Dashboard"], app), go(app.buttons["Settings"], app) {
            settle(); snap(app, "M13 Settings")
        }
        app.terminate()

        // 2. Signed out: Welcome, then sample data's fictional family for parent mode (FAM-14; parent
        //    mode on real accounts arrives with M4).
        let fresh = launchApp(arguments: TestHooks.reset)
        let explore = fresh.buttons["Explore with Sample Data"]
        _ = explore.waitForExistence(timeout: 30)
        settle(); snap(fresh, "M01 Welcome")
        _ = go(explore, fresh)
        _ = fresh.staticTexts["Average of 5 courses"].waitForExistence(timeout: 30)
        if go(fresh.buttons["Settings"], fresh) {
            let parent = fresh.buttons["family.sample.viewAsParent"]
            for _ in 0..<30 where !(parent.exists && parent.isHittable) { fresh.swipeUp() }
            if go(parent, fresh) {
                settle(); settle(); snap(fresh, "M14 Parent mode, Dashboard")
                let switchers = fresh.descendants(matching: .any).matching(identifier: "family.switcher")
                let visible = (0..<switchers.count).map { switchers.element(boundBy: $0) }.first { $0.exists && $0.isHittable }
                if let visible {
                    visible.tap(); settle(); snap(fresh, "M15 Parent mode, switcher")
                    if go(fresh.buttons["Skyler Sample"], fresh) { settle(); snap(fresh, "M16 Parent mode, second student") }
                }
                if go(fresh.buttons["Settings"], fresh) { settle(); snap(fresh, "M18 Parent mode, Linked Students") }
            }
        }
    }

    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Taps `element` once it is hittable; records a "missing" screenshot instead when it never is.
    @MainActor
    private func go(_ element: XCUIElement, _ app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND isHittable == true"), object: element)
        guard XCTWaiter().wait(for: [hittable], timeout: timeout) == .completed else {
            snap(app, "missing \(element)")
            return false
        }
        element.tap()
        return true
    }

    /// Lets a tab switch, sheet or appearance change finish before the screenshot.
    private func settle() { Thread.sleep(forTimeInterval: 1.5) }
}
