import XCTest

/// UX-WP-18 (S-4): To-Do on the flagship persona. Missing work first, every row's label with its
/// course code and status words (A11Y-06), the completion control at 44 × 44 pt (A11Y-04), the
/// honest "done" copy, swipe actions and batch select.
final class ToDoUITests: TallyUITestCase {
    private static let codes = ["BIO 101", "MATH 122", "ENG 101", "PSY 101", "HIST 210"]

    @MainActor
    func testMissingFirstDoneCopySwipeAndBatchSelect() throws {
        let app = launchSample()
        openTab("To-Do", in: app)
        let missingHeader = text("Missing & overdue", in: app)
        XCTAssertTrue(missingHeader.waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
        let weekHeader = text("Due this week", in: app)
        XCTAssertTrue(weekHeader.exists)
        XCTAssertLessThan(missingHeader.frame.minY, weekHeader.frame.minY, "Missing is not the first section")

        // A11Y-06: rows carry the course code and their status words.
        let rows = elements("todo.row", in: app)
        XCTAssertGreaterThanOrEqual(rows.count, 3)
        let first = rows.element(boundBy: 0)
        XCTAssertTrue(Self.codes.contains { first.label.contains($0) }, "row: '\(first.label)'")
        XCTAssertTrue(first.label.contains("Missing"), "the first row is missing work: '\(first.label)'")
        for index in 0..<min(rows.count, 6) {
            let label = rows.element(boundBy: index).label
            XCTAssertTrue(Self.codes.contains { label.contains($0) }, "row \(index): '\(label)'")
        }

        // A11Y-04: the completion control is at least 44 × 44 pt.
        let complete = app.buttons.matching(identifier: "todo.complete").firstMatch
        XCTAssertGreaterThanOrEqual(complete.frame.width, 44)
        XCTAssertGreaterThanOrEqual(complete.frame.height, 44)
        assertEveryButtonHasALabel(app, screen: "To-Do")

        // Done, honestly: marked in Tally, and still not submitted in Canvas.
        complete.tap()
        XCTAssertTrue(eventually { first.label.contains("Marked done in Tally") }, "row: '\(first.label)'")
        XCTAssertTrue(first.label.contains("Not submitted in Canvas"), "row: '\(first.label)'")

        // Swipe actions: Done; no "Open in Canvas" for sample data (it has no real Canvas).
        let second = rows.element(boundBy: 1)
        second.swipeLeft()
        let swipeDone = app.buttons["Done"]
        XCTAssertTrue(swipeDone.waitForExistence(timeout: 5), "no Done swipe action. Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(app.buttons["Open in Canvas"].exists)
        swipeDone.tap()
        XCTAssertTrue(eventually { second.label.contains("Marked done in Tally") }, "row: '\(second.label)'")

        // Batch select: two rows, then Mark Done.
        tapWhenHittable(app.buttons["todo.select"], in: app)
        let third = rows.element(boundBy: 2)
        let fourth = rows.element(boundBy: 3)
        tapWhenHittable(third, in: app)
        tapWhenHittable(fourth, in: app)
        tapWhenHittable(app.buttons["todo.markDone"], in: app)
        XCTAssertTrue(eventually { third.label.contains("Marked done in Tally") && fourth.label.contains("Marked done in Tally") },
                      "batch Mark Done: '\(third.label)' / '\(fourth.label)'")
    }

    /// A11Y-02 at the largest text size.
    @MainActor
    func testToDoAtAccessibilityXXXL() throws {
        let app = launchSample(arguments: Self.largestTextArguments)
        openTab("To-Do", in: app)
        let header = text("Missing & overdue", in: app)
        XCTAssertTrue(header.waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
        let first = elements("todo.row", in: app).firstMatch
        XCTAssertTrue(first.exists)
        XCTAssertGreaterThan(first.frame.height, 150, "the row did not grow with Dynamic Type: \(first.frame)")
        let complete = app.buttons.matching(identifier: "todo.complete").firstMatch
        XCTAssertGreaterThanOrEqual(complete.frame.height, 44)
        assertEveryButtonHasALabel(app, screen: "To-Do AX XXXL")
        assertAccessibilityAudit(app, screen: "To-Do AX XXXL")
    }
}
