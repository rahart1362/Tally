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

    /// Every element whose identifier begins with `prefix` — for a row whose identifier itself
    /// carries state (L10N-04 round 2: `todo.row.done`/`todo.row.notDone`, so a query for "every
    /// row regardless of state" still finds them all, the same count `elements("todo.row", …)`
    /// found before that identifier was split).
    @MainActor
    func elementsWithPrefix(_ prefix: String, in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
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

    /// Swipes up until `element` is hittable and its bottom edge sits `bottomMargin` points above the
    /// screen's bottom, clear of a bottom bar (a tap near that edge can land on the bar instead:
    /// run 36463736410's To-Do batch select). `true` when it does.
    @MainActor
    @discardableResult
    func bringClearOfTheBottom(_ element: XCUIElement, in app: XCUIApplication,
                               bottomMargin: CGFloat = 160, maxSwipes: Int = 4) -> Bool {
        let clear = { element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - bottomMargin }
        for _ in 0..<maxSwipes where !clear() {
            app.swipeUp(velocity: .slow)
        }
        return clear()
    }

    /// MVP-2c: the other edge from `bringClearOfTheBottom`. Drags the list down, with a hold before
    /// release so it stops where it is put, until `element`'s top is `margin` below the navigation
    /// bar. To-Do's batch select failed with its first picked row resting under the bar (y = 108 to
    /// 207 against a bar ending at 170; runs 38634697575, both attempts, and 38652917902): its
    /// centre, where the row was tapped, was inside the bar, so the tap selected nothing.
    @MainActor
    func bringClearOfTheTop(_ element: XCUIElement, in app: XCUIApplication, margin: CGFloat = 8) {
        let bar = app.navigationBars.firstMatch
        guard bar.exists, element.exists else { return }
        let overlap = bar.frame.maxY + margin - element.frame.minY
        guard overlap > 0 else { return }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // A pan starts only after the touch has moved a few points; the extra margin covers that.
        let end = start.withOffset(CGVector(dx: 0, dy: overlap + 2 * margin))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// MVP-2c: the middle of the part of `element` that is between the navigation bar and
    /// `bottomMargin` above the screen's bottom (the floating tab bar or a bottom bar), so a tap lands
    /// on the element itself, never on a bar over it.
    @MainActor
    func clearTapPoint(_ element: XCUIElement, in app: XCUIApplication, bottomMargin: CGFloat = 160) -> XCUICoordinate {
        let frame = element.frame
        let bar = app.navigationBars.firstMatch
        let top = max(frame.minY, bar.exists ? bar.frame.maxY : app.frame.minY)
        let bottom = min(frame.maxY, app.frame.maxY - bottomMargin)
        let middle = bottom > top ? (top + bottom) / 2 : frame.midY
        return element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: (middle - frame.minY) / max(frame.height, 1)))
    }

    /// Waits for `element`'s frame to stop moving (two checks `interval` apart land on the same
    /// rect), up to `timeout`: the swipe that brought it on screen (`bringClearOfTheBottom`) has
    /// finished decelerating. `true` once it has, or once `timeout` passes regardless (run
    /// 38059604806's To-Do batch select: `isHittable` and clear of the bottom bar both go true
    /// before the list's deceleration ends, so a tap right after can still land mid-scroll).
    @MainActor
    @discardableResult
    func waitUntilRowAtRest(_ element: XCUIElement, in app: XCUIApplication, timeout: TimeInterval = 3,
                            interval: TimeInterval = 0.15) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var previous = element.frame
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(interval))
            let next = element.frame
            if next == previous { return true }
            previous = next
        }
        return element.frame == previous
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
