import XCTest

/// UX-WP-15 (S-2) and UX-WP-16 (S-3): Course Detail on MATH 122 of the flagship persona, then the
/// what-if sheet. Segments without "People", the hero as one element, `chart.weights` with a label
/// and a value (A11Y-08), no distribution (no score statistics), and the what-if score set by
/// typing, by the 44 pt ±1 stepper (A11Y-04), and by VoiceOver-style adjustment of the row's slider
/// (`adjust(toNormalizedSliderPosition:)`; XCUITest has no increment or decrement on iOS).
final class CourseDetailUITests: TallyUITestCase {
    @MainActor
    private func openMath(_ app: XCUIApplication) {
        openTab("Courses", in: app)
        let math = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'course.card' AND label CONTAINS 'MATH 122'")).firstMatch
        // At the accessibility sizes one card fills most of the screen, so MATH 122 may start below it.
        XCTAssertTrue(elements("course.card", in: app).firstMatch.waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(scrollUntilHittable(math, in: app, maxSwipes: 15), "MATH 122 never came on screen. Hierarchy: \(app.debugDescription)")
        tapWhenHittable(math, in: app, timeout: 15)
        XCTAssertTrue(element("courseDetail.hero", in: app).waitForExistence(timeout: 10),
                      "Course Detail never opened. Hierarchy: \(app.debugDescription)")
    }

    @MainActor
    func testSegmentsChartsAndTheWhatIfSheet() throws {
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
        XCTAssertTrue(element("whatif.simulationLabel", in: app).label.contains("Simulation"))
        let projected = element("whatif.projected", in: app)
        XCTAssertTrue(eventually(timeout: 15) { projected.label.contains("the same as your current grade") },
                      "the baseline never landed: '\(projected.label)'")

        // VoiceOver-style adjust first, while no keyboard covers the sheet: the first row's slider,
        // moved as an assistive technology moves it.
        let field = app.textFields.matching(identifier: "whatif.field").firstMatch
        let slider = app.sliders.matching(identifier: "whatif.slider").firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "no score slider. Hierarchy: \(app.debugDescription)")
        slider.adjust(toNormalizedSliderPosition: 0.9)
        XCTAssertTrue(eventually {
            guard let text = field.value as? String, let value = Double(text) else { return false }
            return (80...100).contains(value)
        }, "adjusting the slider did not set the score: \(String(describing: field.value))")
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

        // Typing: clear the field, then a zero on this item lowers the projection.
        tapWhenHittable(field, in: app)
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

    /// A11Y-02 on Course Detail and the what-if sheet at the largest text size.
    @MainActor
    func testCourseDetailAndWhatIfAtAccessibilityXXXL() throws {
        let app = launchSample(arguments: Self.largestTextArguments)
        openMath(app)
        let hero = element("courseDetail.hero", in: app)
        XCTAssertGreaterThan(hero.frame.height, 150, "the hero did not grow with Dynamic Type: \(hero.frame)")
        assertAccessibilityAudit(app, screen: "Course Detail AX XXXL")

        let whatIf = element("courseDetail.whatIf", in: app)
        XCTAssertTrue(scrollUntilHittable(whatIf, in: app, maxSwipes: 15), "Hierarchy: \(app.debugDescription)")
        whatIf.tap()
        let raise = app.buttons.matching(identifier: "whatif.increment").firstMatch
        XCTAssertTrue(raise.waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)")
        XCTAssertGreaterThanOrEqual(raise.frame.height, 44)
        XCTAssertTrue(app.sliders.matching(identifier: "whatif.slider").firstMatch.exists)
        assertEveryButtonHasALabel(app, screen: "What-If AX XXXL")
        // A11Y-04 names the what-if stepper: the audit's hit-region check runs here too.
        assertAccessibilityAudit(app, screen: "What-If AX XXXL",
                                 types: [.dynamicType, .textClipped, .sufficientElementDescription, .hitRegion])
    }
}
