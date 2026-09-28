import XCTest

/// UX-WP-15 (S-2) and UX-WP-16 (S-3): Course Detail on MATH 122 of the flagship persona, then the
/// what-if sheet. Segments without "People", the hero as one element, `chart.weights` with a label
/// and a value (A11Y-08), no distribution (no score statistics), and the what-if score set by
/// typing and by VoiceOver-style adjustment on a 44 pt stepper (A11Y-04).
final class CourseDetailUITests: TallyUITestCase {
    @MainActor
    private func openMath(_ app: XCUIApplication) {
        openTab("Courses", in: app)
        let math = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'course.card' AND label CONTAINS 'MATH 122'")).firstMatch
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

        // A11Y-08: the category-weights chart has a label and a value.
        let weights = element("chart.weights", in: app)
        XCTAssertTrue(scrollUntilHittable(weights, in: app), "no weights chart. Hierarchy: \(app.debugDescription)")
        XCTAssertEqual(weights.label, "Category weights")
        XCTAssertEqual(weights.value as? String, "Problem Sets 30%, Quizzes 20%, Exams 50%")
        // No score statistics in Canvas's data: the distribution is hidden, never invented.
        XCTAssertFalse(element("chart.distribution", in: app).exists)
        assertEveryButtonHasALabel(app, screen: "Course Detail")

        tapWhenHittable(app.buttons["Assignments"], in: app)
        XCTAssertTrue(text("Missing", in: app).waitForExistence(timeout: 5), "Hierarchy: \(app.debugDescription)")
        tapWhenHittable(app.buttons["Grades"], in: app)
        XCTAssertTrue(app.staticTexts["Current grade counts graded work only."].waitForExistence(timeout: 5),
                      "Hierarchy: \(app.debugDescription)")

        // The what-if sheet.
        tapWhenHittable(app.buttons["Overview"], in: app)
        let whatIf = element("courseDetail.whatIf", in: app)
        XCTAssertTrue(scrollUntilHittable(whatIf, in: app), "no What-If button. Hierarchy: \(app.debugDescription)")
        whatIf.tap()
        XCTAssertTrue(element("whatif.simulationLabel", in: app).waitForExistence(timeout: 10),
                      "no 'Simulation — not your real grade'. Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(element("whatif.simulationLabel", in: app).label.contains("Simulation"))
        let projected = element("whatif.projected", in: app)
        XCTAssertTrue(eventually(timeout: 15) { projected.label.contains("the same as your current grade") },
                      "the baseline never landed: '\(projected.label)'")

        // Typing: a zero on the first ungraded item lowers the projection.
        let field = app.textFields.matching(identifier: "whatif.field").firstMatch
        tapWhenHittable(field, in: app)
        field.typeText("0")
        XCTAssertTrue(eventually(timeout: 15) { projected.label.contains("down") },
                      "typing a score did not move the projection: '\(projected.label)'")

        // VoiceOver-style adjust on the same row's stepper, a 44 pt target (A11Y-04).
        let stepper = element("whatif.stepper", in: app)
        XCTAssertTrue(stepper.exists, "Hierarchy: \(app.debugDescription)")
        XCTAssertGreaterThanOrEqual(stepper.frame.height, 44)
        XCTAssertGreaterThanOrEqual(stepper.frame.width, 44)
        XCTAssertEqual(stepper.value as? String, "0 out of 100")
        stepper.increment()
        XCTAssertTrue(eventually { stepper.value as? String == "1 out of 100" },
                      "adjusting did not step the score: \(String(describing: stepper.value))")
        XCTAssertTrue(eventually { field.value as? String == "1" }, "the field did not follow the stepper")
        stepper.decrement()
        XCTAssertTrue(eventually { stepper.value as? String == "0 out of 100" })

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
        let stepper = element("whatif.stepper", in: app)
        XCTAssertTrue(stepper.waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)")
        XCTAssertGreaterThanOrEqual(stepper.frame.height, 44)
        assertEveryButtonHasALabel(app, screen: "What-If AX XXXL")
        assertAccessibilityAudit(app, screen: "What-If AX XXXL")
    }
}
