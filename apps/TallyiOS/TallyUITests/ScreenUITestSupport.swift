import XCTest

/// Shared steps for the M3-A screen UI tests (UX-WP-14…20). Every screen runs on the bundled
/// flagship persona through "Explore with Sample Data": real domain data, never mock data in views.
extension TallyUITestCase {
    /// Launches, enters sample mode and waits for the first projection (the Dashboard's hero).
    @MainActor
    func launchSample(arguments: [String] = []) -> XCUIApplication {
        let app = launchApp(arguments: arguments)
        tapWhenHittable(app.buttons["Explore with Sample Data"], in: app, timeout: 30)
        XCTAssertTrue(app.staticTexts["SAMPLE DATA"].waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["Average of 5 courses"].waitForExistence(timeout: 30),
                      "the sample projection never landed. Hierarchy: \(app.debugDescription)")
        return app
    }

    @MainActor
    func openTab(_ name: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        tapWhenHittable(app.tabBars.buttons[name], in: app, file: file, line: line)
    }

    /// Every element carrying `identifier`, whatever its type.
    @MainActor
    func elements(_ identifier: String, in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    @MainActor
    func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        elements(identifier, in: app).firstMatch
    }

    /// A static text by its words, ignoring case: grouped-list section headers may be shown (and
    /// reported to accessibility) in capitals.
    @MainActor
    func text(_ words: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", words)).firstMatch
    }

    /// Swipes up, slowly, until `element` is hittable. `true` when it is.
    @MainActor
    @discardableResult
    func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 10) -> Bool {
        for _ in 0..<maxSwipes {
            if element.exists, element.isHittable { return true }
            app.swipeUp(velocity: .slow)
        }
        return element.exists && element.isHittable
    }

    /// Flips a Form toggle. The toggle's element spans the whole row, and a tap on the row's centre
    /// lands on the label, which does not flip it; tap the switch itself (the row's inner switch
    /// when the hierarchy has one, else the trailing end of the row where the switch sits).
    @MainActor
    func flip(_ toggle: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        waitUntilHittable(toggle, in: app, file: file, line: line)
        let inner = toggle.switches.firstMatch
        if inner.exists, inner.isHittable {
            inner.tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
    }

    /// Polls `condition` until it holds or `timeout` passes.
    @MainActor
    func eventually(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    /// A11Y-03: every button on screen has a non-empty label.
    @MainActor
    func assertEveryButtonHasALabel(_ app: XCUIApplication, screen: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let unlabeled = app.buttons.matching(NSPredicate(format: "label == ''"))
        XCTAssertEqual(unlabeled.count, 0, "\(screen): unlabelled buttons. Hierarchy: \(app.debugDescription)",
                       file: file, line: line)
    }
}
