import UIKit
import XCTest

/// UX-WP-15 (S-2) and UX-WP-16 (S-3): Course Detail on MATH 122 of the flagship persona, then the
/// what-if sheet. Segments without "People", the hero as one element, `chart.weights` with a label
/// and a value (A11Y-08), no distribution (no score statistics), and the what-if score set by
/// typing, by the 44 pt ±1 stepper (A11Y-04), and by VoiceOver-style adjustment of the row's slider
/// (`adjust(toNormalizedSliderPosition:)`; XCUITest has no increment or decrement on iOS). The
/// first what-if row is Problem Set 7, out of 100 points.
final class CourseDetailUITests: TallyUITestCase {
    @MainActor
    private func openMath(_ app: XCUIApplication) {
        openTab("Courses", in: app)
        // MATH 122 by its place, never by its card's label, so a fault in the card label (the Courses
        // test's to catch) cannot mask a fault here (MU12, masked by MU1 in run 36468704319). A new
        // sample session lists the flagship's courses in Canvas order, MATH 122 second; the hero's
        // "Calculus II" check below proves the right course opened.
        let cards = elements("course.card", in: app)
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
        let math = cards.element(boundBy: TestHooks.flagshipCourseCodes.firstIndex(of: "MATH 122") ?? 1)
        // At the accessibility sizes one card fills most of the screen, so MATH 122 may start below it.
        XCTAssertTrue(scrollUntilHittable(math, in: app, maxSwipes: 15), "MATH 122 never came on screen. Hierarchy: \(app.debugDescription)")
        tapWhenHittable(math, in: app, timeout: 15)
        XCTAssertTrue(element("courseDetail.hero", in: app).waitForExistence(timeout: 10),
                      "Course Detail never opened. Hierarchy: \(app.debugDescription)")
    }

    @MainActor
    func testSegmentsChartsAndTheWhatIfSheet() throws {
        // The longest screen test: 202.4 s in run 36463736410 (the slider's adjust steps through
        // its positions), close to the suite's 240 s. The command line's maximum is 300 s.
        executionTimeAllowance = 300
        let app = launchSample()
        openMath(app)

        // The hero is one element; the segments are Overview, Assignments and Grades, never People.
        let hero = element("courseDetail.hero", in: app)
        XCTAssertTrue(hero.label.contains("Calculus II") && hero.label.contains("90.1 percent"), "hero: '\(hero.label)'")
        for segment in ["Overview", "Assignments", "Grades"] {
            XCTAssertTrue(app.buttons[segment].exists, "no \(segment) segment. Hierarchy: \(app.debugDescription)")
        }
        XCTAssertFalse(app.buttons["People"].exists)

        // The segments, while the picker is on screen: Assignments (its first section) and Grades.
        tapWhenHittable(app.buttons["Assignments"], in: app)
        XCTAssertTrue(eventually { self.text("Upcoming", in: app).exists || self.text("Missing", in: app).exists },
                      "no assignment sections. Hierarchy: \(app.debugDescription)")
        tapWhenHittable(app.buttons["Grades"], in: app)
        XCTAssertTrue(app.staticTexts["Current grade counts graded work only."].waitForExistence(timeout: 5),
                      "Hierarchy: \(app.debugDescription)")
        tapWhenHittable(app.buttons["Overview"], in: app)

        // A11Y-08: the category-weights chart has a label and a value.
        let weights = element("chart.weights", in: app)
        XCTAssertTrue(scrollUntilHittable(weights, in: app), "no weights chart. Hierarchy: \(app.debugDescription)")
        XCTAssertEqual(weights.label, "Category weights")
        XCTAssertEqual(weights.value as? String, "Problem Sets 30%, Quizzes 20%, Exams 50%")
        // No score statistics in Canvas's data: the distribution is hidden, never invented.
        XCTAssertFalse(element("chart.distribution", in: app).exists)
        assertEveryButtonHasALabel(app, screen: "Course Detail")

        // The what-if sheet.
        let whatIf = element("courseDetail.whatIf", in: app)
        XCTAssertTrue(scrollUntilHittable(whatIf, in: app), "no What-If button. Hierarchy: \(app.debugDescription)")
        whatIf.tap()
        XCTAssertTrue(element("whatif.simulationLabel", in: app).waitForExistence(timeout: 10),
                      "no 'Simulation — not your real grade'. Hierarchy: \(app.debugDescription)")
        let simulation = element("whatif.simulationLabel", in: app)
        XCTAssertTrue(simulation.label.contains("Simulation"), "simulation label: '\(simulation.label)'")
        let projected = element("whatif.projected", in: app)
        XCTAssertTrue(eventually(timeout: 15) { projected.label.contains("the same as your current grade") },
                      "the baseline never landed: '\(projected.label)'")
        // The sheet opens at the medium height; pull it up so the first row is on screen whole.
        let sheetBar = app.navigationBars["What-If"]
        if sheetBar.waitForExistence(timeout: 5) { sheetBar.swipeUp() }

        // VoiceOver-style adjust first, while no keyboard covers the sheet: the first row's slider,
        // moved as an assistive technology moves it. Halfway is about 50 of 100 points, enough to
        // move the course grade (90 of 100 would change it by less than 0.05 points).
        let field = app.textFields.matching(identifier: "whatif.field").firstMatch
        let slider = app.sliders.matching(identifier: "whatif.slider").firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "no score slider. Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(scrollUntilHittable(slider, in: app, maxSwipes: 3), "Hierarchy: \(app.debugDescription)")
        let before = Double(field.value as? String ?? "")
        slider.adjust(toNormalizedSliderPosition: 0.5)
        // XCUITest's adjust lands only near the position asked for (21 and 32 as well as about 50
        // for 0.5 on CI simulators: PR #6 run 36519966442, M3-A O15), so the check is that the
        // slider set a different, valid score, not which one. MU12 (the slider sets nothing) still
        // fails it.
        XCTAssertTrue(eventually {
            guard let text = field.value as? String, let value = Double(text) else { return false }
            return value != before && (0...100).contains(value)
        }, "adjusting the slider did not set the score: \(String(describing: field.value)) (was \(String(describing: before)))")
        XCTAssertTrue(eventually(timeout: 15) { !projected.label.contains("the same as your current grade") },
                      "the projection did not follow the slider: '\(projected.label)'")

        // The ±1 stepper: two 44 pt buttons (A11Y-04) on the same row.
        XCTAssertTrue(element("whatif.stepper", in: app).exists, "Hierarchy: \(app.debugDescription)")
        let raise = app.buttons.matching(identifier: "whatif.increment").firstMatch
        let lower = app.buttons.matching(identifier: "whatif.decrement").firstMatch
        for button in [raise, lower] {
            XCTAssertGreaterThanOrEqual(button.frame.width, 44, "\(button.label): \(button.frame)")
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, "\(button.label): \(button.frame)")
        }
        let adjusted = Double(field.value as? String ?? "") ?? 0
        tapWhenHittable(lower, in: app)
        XCTAssertTrue(eventually { Double(field.value as? String ?? "") == adjusted - 1 },
                      "the stepper did not lower the score by 1: \(String(describing: field.value))")
        tapWhenHittable(raise, in: app)
        XCTAssertTrue(eventually { Double(field.value as? String ?? "") == adjusted },
                      "the stepper did not raise the score by 1: \(String(describing: field.value))")

        // Typing: put the cursor at the end of the field, clear it, then a zero on this item lowers
        // the projection. ux-fp2 (carried over from ux-fp1): type only once the field has the
        // keyboard (PR run 37810483577 typed into a field that did not have it yet, once).
        waitUntilHittable(field, in: app)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        if !waitForKeyboardFocus(field, in: app) {
            XCTContext.runActivity(named: "Re-tap once: the score field did not take the keyboard") { _ in field.tap() }
        }
        XCTAssertTrue(waitForKeyboardFocus(field, in: app), "the score field never took the keyboard. Hierarchy: \(app.debugDescription)")
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "0")
        XCTAssertTrue(eventually { field.value as? String == "0" }, "typing did not set 0: \(String(describing: field.value))")
        XCTAssertTrue(eventually(timeout: 15) { projected.label.contains("down") },
                      "typing a score did not move the projection: '\(projected.label)'")

        // Reset clears every hypothetical score.
        tapWhenHittable(app.buttons["whatif.reset"], in: app)
        XCTAssertTrue(eventually(timeout: 15) { projected.label.contains("the same as your current grade") },
                      "reset did not restore the baseline: '\(projected.label)'")
        assertEveryButtonHasALabel(app, screen: "What-If")
    }

    /// ux-fp2 D02 (S1): at AX XXXL a recent grade's score sits under its title on ONE line, and no
    /// text in its row overlaps another. The audit (run 37649050231) read "93.2/100" as
    /// "9 / 3.2/10 / 0": three lines in a column squeezed beside the title.
    @MainActor
    func testRecentGradeScoreStaysOnOneLineAtAccessibilityXXXL() throws {
        let app = launchSample(arguments: Self.accessibilityXXXL)
        openTab("Courses", in: app)
        let cards = elements("course.card", in: app)
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
        let firstCard = cards.element(boundBy: 0)
        XCTAssertTrue(scrollUntilHittable(firstCard, in: app, maxSwipes: 5), "the first course never came on screen. Hierarchy: \(app.debugDescription)")
        tapWhenHittable(firstCard, in: app, timeout: 15)
        XCTAssertTrue(element("courseDetail.hero", in: app).waitForExistence(timeout: 10),
                      "Course Detail never opened. Hierarchy: \(app.debugDescription)")

        // The row is one element whose label reads "<title>, <score> out of <points>, posted <day>"
        // (`gradedItemAccessibility`); its texts are its children in the hierarchy.
        let row = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", " out of ", ", posted ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no recent grade. Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(scrollUntilHittable(row, in: app, maxSwipes: 15), "the first recent grade never came on screen. Hierarchy: \(app.debugDescription)")

        // Every frame below comes from ONE snapshot, so they agree even if the list is still settling.
        let snapshot = try app.snapshot()
        let screen = snapshot.frame
        let nodes = Self.staticTextNodes(in: snapshot)
        let rows = nodes.filter { node in
            let isRow = node.label.contains(" out of ") && node.label.contains(", posted ")
            return isRow && screen.contains(node.frame)
        }
        let rowNode = try XCTUnwrap(rows.first, "no recent grade wholly on screen: \(nodes)")
        let bounds = rowNode.frame.insetBy(dx: -Self.overlapTolerance, dy: -Self.overlapTolerance)
        let texts = nodes.filter { $0.frame != rowNode.frame && bounds.contains($0.frame) }
        let scores = texts.filter { $0.label.range(of: Self.scorePattern, options: .regularExpression) != nil }
        let score = try XCTUnwrap(scores.first, "no score text in '\(rowNode.label)': \(texts)")
        // The chip's words are `caption` (semibold): one line of it at AX XXXL, from UIKit's own metrics.
        let captionLine = UIFont.preferredFont(
            forTextStyle: .caption1,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)).lineHeight
        let scoreHeight = score.frame.height
        XCTAssertLessThan(scoreHeight, 2 * captionLine,
                          "'\(score.label)' is \(scoreHeight) pt tall, more than one \(captionLine) pt line: it wrapped")
        for (index, first) in texts.enumerated() {
            for second in texts.dropFirst(index + 1) {
                let firstFrame = first.frame.insetBy(dx: Self.overlapTolerance, dy: Self.overlapTolerance)
                let secondFrame = second.frame.insetBy(dx: Self.overlapTolerance, dy: Self.overlapTolerance)
                let overlaps = firstFrame.intersects(secondFrame)
                XCTAssertFalse(overlaps, "'\(first.label)' \(first.frame) overlaps '\(second.label)' \(second.frame)")
            }
        }
    }

    private static let accessibilityXXXL = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    /// A recent grade's score text: "93.2/100", "20/20".
    private static let scorePattern = #"^[0-9][0-9.,]*/[0-9][0-9.,]*$"#
    /// Frames that only touch (rounding) are not an overlap.
    private static let overlapTolerance: CGFloat = 0.5

    /// Waits until a keyboard is up for `field` (or the field reports keyboard focus).
    @MainActor
    private func waitForKeyboardFocus(_ field: XCUIElement, in app: XCUIApplication) -> Bool {
        eventually(timeout: scaled(5)) {
            let keyboardUp = app.keyboards.count > 0
            if keyboardUp { return true }
            let focused = (field.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
            return focused
        }
    }

    /// Every non-empty static text in `root`'s hierarchy, its label and frame read into plain values
    /// (never captured in an autoclosure: the Release test build rejects sending a snapshot, run
    /// 37704108738).
    @MainActor
    private static func staticTextNodes(in root: XCUIElementSnapshot) -> [(label: String, frame: CGRect)] {
        var found: [(label: String, frame: CGRect)] = []
        var pending: [XCUIElementSnapshot] = [root]
        while let node = pending.popLast() {
            pending.append(contentsOf: node.children)
            let type = node.elementType
            let frame = node.frame
            let label = node.label
            guard type == .staticText, !frame.isEmpty else { continue }
            found.append((label: label, frame: frame))
        }
        return found
    }
}
