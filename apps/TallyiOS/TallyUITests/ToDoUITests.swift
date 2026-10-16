import XCTest

/// UX-WP-18 (S-4): To-Do on the flagship persona. Missing work first, the first rows' labels with
/// their course codes and the first row's status words (A11Y-06; every row is checked in
/// `ScreenProjectionTests`), the completion control at 44 × 44 pt (A11Y-04), the honest "done"
/// copy, swipe actions and batch select.
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
        // L10N-04 round 2: "todo.row" split into "todo.row.done"/"todo.row.notDone" (a VoiceOver-
        // safe way to carry the done state for the Audit tour's batch-select filter); this still
        // finds every row, exactly as the flat "todo.row" identifier did.
        let rows = elementsWithPrefix("todo.row", in: app)
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

        // Batch select: two rows not yet done, then Mark Done. Rows are found by their labels,
        // since scrolling changes which rows are in the hierarchy.
        tapWhenHittable(app.buttons["todo.select"], in: app)
        let notDone = rows.matching(NSPredicate(format: "NOT (label CONTAINS 'Marked done in Tally')"))
        XCTAssertGreaterThanOrEqual(notDone.count, 2, "Hierarchy: \(app.debugDescription)")
        let picked = [notDone.element(boundBy: 0).label, notDone.element(boundBy: 1).label]
        for label in picked {
            let row = rows.matching(NSPredicate(format: "label == %@", label)).firstMatch
            XCTAssertTrue(bringClearOfTheBottom(row, in: app), "'\(label)' is not clear of the bottom bar. Hierarchy: \(app.debugDescription)")
            // bringClearOfTheBottom only guards the bottom-bar overlap (run 36463736410): isHittable
            // and the frame check both pass while the list is still decelerating from its swipe, so
            // a tap right after can land mid-scroll and miss the selection (run 38059604806,
            // 38039203669, 37925235523: "'<row>' was not selected"). Wait for the row to stop
            // moving, tap its centre (not whichever point XCTest's default tap picks), and retry
            // once before failing.
            //
            // MVP-2c: the row can also rest under the navigation bar (runs 38634697575, both attempts,
            // and 38652917902: the picked row at y = 108 to 207 under a bar ending at 170, so its
            // centre was inside the bar and "was not selected" with nothing selected at all; the same
            // failure on two branches without this package's changes, runs 38201921389 and
            // 38235284131). Bring it clear of the top too, and tap the middle of its part that is
            // clear of both bars. A retry taps only a row that is still not selected.
            bringClearOfTheTop(row, in: app)
            waitUntilRowAtRest(row, in: app)
            clearTapPoint(row, in: app).tap()
            if !eventually(timeout: 3, { row.isSelected }) {
                waitUntilRowAtRest(row, in: app)
                let stillNotSelected = !row.isSelected
                if stillNotSelected { clearTapPoint(row, in: app).tap() }
            }
            XCTAssertTrue(eventually(timeout: 2) { row.isSelected }, "'\(label)' was not selected after a retry. Hierarchy: \(app.debugDescription)")
        }
        tapWhenHittable(app.buttons["todo.markDone"], in: app)
        // The rows keep their places; the scroll may have moved the first one above the screen.
        for label in picked.reversed() {
            let done = rows.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS 'Marked done in Tally'", label)).firstMatch
            var found = eventually(timeout: 5) { done.exists }
            for _ in 0..<3 where !found {
                app.swipeDown(velocity: .slow)
                found = eventually(timeout: 2) { done.exists }
            }
            XCTAssertTrue(found, "batch Mark Done did not mark '\(label)'. Hierarchy: \(app.debugDescription)")
        }

        // MVP-2g (item 2): the standard iOS pattern — exit selection mode once a batch action
        // completes (`ToDoScreen.swift`'s own `withAnimation { editMode = .inactive }` right after
        // `setDone`) — asserted structurally, not by `todo.markDone`'s own absence alone. The
        // gate-2 final review found that guard blind to a List whose own selection circles can
        // persist even once `editMode` reads inactive (verdict §B: the smallest device's AX5 legs
        // only; no simulator here to reproduce that device-specific case). This is the general
        // assertion the fix list asked for on whatever device this suite actually runs on.
        XCTAssertFalse(app.buttons["todo.markDone"].exists, "batch Mark Done did not exit selection mode")
        XCTAssertTrue(app.buttons.matching(identifier: "todo.complete").firstMatch.exists,
                      "no row shows its own completion control after exiting selection mode")
    }
}
