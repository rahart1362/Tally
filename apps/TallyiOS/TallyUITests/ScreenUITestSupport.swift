import XCTest

/// Shared steps for the M3-A screen UI tests (UX-WP-14…20). Every screen runs on the bundled
/// flagship persona through "Explore with Sample Data": real domain data, never mock data in views.
extension TallyUITestCase {
    /// The Dynamic Type launch argument `WelcomeCTAUITests` proved takes effect on the CI simulator.
    static let largestTextArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

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

    /// The first element of `query` that is on screen and hittable, waiting up to `timeout`.
    @MainActor
    func firstHittable(_ query: XCUIElementQuery, timeout: TimeInterval = 10) -> XCUIElement? {
        var found: XCUIElement?
        _ = eventually(timeout: timeout) {
            found = (0..<query.count).lazy.map { query.element(boundBy: $0) }.first { $0.isHittable }
            return found != nil
        }
        return found
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

    /// A11Y-01/02: Apple's accessibility audit on the screen as it is now. Every issue fails the test
    /// unless `ScreenAuditWaivers` accepts it (A11Y-01: waivers only through the issue handler, each
    /// with its reason in code). Every issue, waived or not, is listed with its element: waived ones
    /// in an attachment, the rest in the failure message.
    @MainActor
    func assertAccessibilityAudit(_ app: XCUIApplication, screen: String,
                                  types: XCUIAccessibilityAuditType = [.dynamicType, .textClipped, .sufficientElementDescription],
                                  file: StaticString = #filePath, line: UInt = #line) {
        let bars = (app.navigationBars.allElementsBoundByIndex + app.tabBars.allElementsBoundByIndex
                    + app.toolbars.allElementsBoundByIndex).map(\.frame)
        var failing: [String] = []
        var waived: [String] = []
        do {
            try app.performAccessibilityAudit(for: types) { issue in
                let described = ScreenAuditWaivers.describe(issue)
                if let reason = ScreenAuditWaivers.waiver(for: issue, systemBars: bars) {
                    waived.append("\(described) | waived: \(reason)")
                } else {
                    failing.append(described)
                }
                return true
            }
        } catch {
            XCTFail("\(screen): the accessibility audit could not run: \(error)", file: file, line: line)
        }
        if !waived.isEmpty {
            for entry in waived { print("M3A-AUDIT-WAIVED \(screen): \(entry)") }
            let attachment = XCTAttachment(string: waived.joined(separator: "\n"))
            attachment.name = "\(screen): waived audit issues"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(failing.isEmpty, "\(screen): \(failing.count) accessibility audit issue(s):\n"
                      + failing.joined(separator: "\n") + "\nHierarchy: \(app.debugDescription)", file: file, line: line)
    }
}

/// Audit issues this suite accepts. A11Y-01 allows a waiver only through the issue handler with a
/// ticket ID in code; the repository has no ticket tracker, so each waiver carries an ID that
/// docs/pmo/reviews/m3-screens-report.md lists with its evidence.
@MainActor
enum ScreenAuditWaivers {
    /// M3A-W1: text drawn by UIKit's navigation bars, tab bar and toolbars. UIKit sizes that text
    /// itself and caps it at the accessibility sizes (bar items offer the Large Content Viewer on
    /// a long press instead); Tally does not size or draw it. Only these two audit types, and only
    /// for an element that lies wholly inside one of those bars.
    static let systemBarTextID = "M3A-W1"
    static let systemBarTypes: XCUIAccessibilityAuditType = [.dynamicType, .textClipped]

    static func waiver(for issue: XCUIAccessibilityAuditIssue, systemBars: [CGRect]) -> String? {
        guard systemBarTypes.contains(issue.auditType), let frame = issue.element?.frame, !frame.isEmpty,
              systemBars.contains(where: { $0.insetBy(dx: -1, dy: -1).contains(frame) }) else { return nil }
        return "\(systemBarTextID): text drawn by a system bar"
    }

    static func describe(_ issue: XCUIAccessibilityAuditIssue) -> String {
        let element = issue.element.map {
            "element type \($0.elementType.rawValue) label '\($0.label)' id '\($0.identifier)' frame \($0.frame)"
        } ?? "no element"
        return "\(name(of: issue.auditType)) | \(issue.compactDescription) | \(issue.detailedDescription) | \(element)"
    }

    static func name(of type: XCUIAccessibilityAuditType) -> String {
        let names: [(XCUIAccessibilityAuditType, String)] = [
            (.contrast, "contrast"), (.elementDetection, "elementDetection"), (.hitRegion, "hitRegion"),
            (.sufficientElementDescription, "sufficientElementDescription"), (.dynamicType, "dynamicType"),
            (.textClipped, "textClipped"), (.trait, "trait"),
        ]
        let matched = names.filter { type.contains($0.0) }.map(\.1)
        return matched.isEmpty ? "type \(type.rawValue)" : matched.joined(separator: "+")
    }
}
