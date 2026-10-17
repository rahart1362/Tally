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
        // MVP-2g (PMO direction, binding): the normal list's own leading inset, captured before
        // Select is ever tapped — the baseline the post-Mark-Done check below reads against. The
        // gate-2 final review's own evidence for the smallest-device defect (verdict.md §B) was
        // exactly this: every row sat 65 pt further right than this baseline, the List's own
        // selection accessory never having let go, even once `editMode` read `.inactive`.
        let normalLeadingInset = first.frame.minX
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

        // MVP-2g (PMO direction, binding): prove or disprove the smallest-device defect the
        // gate-2 final review flagged (verdict.md §B), structurally — never assumed from
        // `todo.markDone`'s own absence alone, and never a coordinate guess. This method runs
        // again, unchanged, on the smallest iPhone via `ci.yml`'s own "To-Do batch Mark Done exits
        // selection mode" step (`steps.small.outputs.udid`), the same device the tour found stuck.
        //
        // `ToDoScreen.swift`'s own exit (`withAnimation { editMode = .inactive }` right after
        // `setDone`) is the standard iOS pattern already; `todo.select`'s toggle and the tab bar's
        // return already confirm `editMode` really did flip. What the tour could not tell was
        // whether the List's own leading selection accessory actually let go too.
        //
        // MVP-2h (narrow re-check, `review/verdict.md` section 2.2): two of the three checks that
        // used to run here — by identifier (one `todo.complete` per visible row) and by trait (a
        // marked row does not read `isSelected`) — both still pass in the stuck, broken state
        // (the review's own table: `editMode` reads `.inactive` either way, so every row still
        // draws its own `todo.complete`, and no `todo.row.*` element ever carries `Selected` in
        // that state either). They proved nothing about this defect and are dropped. Only the
        // geometry check below ever actually failed on the real bug (run 38889379284), so it is
        // the one kept.
        XCTAssertFalse(app.buttons["todo.markDone"].exists, "batch Mark Done did not exit selection mode")
        let visibleRows = elementsWithPrefix("todo.row", in: app)
        // By geometry: every visible row's own leading inset must match the normal list's — the
        // List's own selection accessory, stuck or not, is what shifts it (verdict.md §B: 65 pt on
        // the smallest device, both AX5 legs, never resolving).
        for index in 0..<min(visibleRows.count, 5) {
            let row = visibleRows.element(boundBy: index)
            guard row.exists else { continue }
            XCTAssertEqual(row.frame.minX, normalLeadingInset, accuracy: 1,
                          "row \(index) is not at its normal leading inset after batch Mark Done — " +
                          "the List's own selection accessory may still be showing. Hierarchy: \(app.debugDescription)")
        }
    }

    /// MVP-2h (PMO direction, binding — `review/verdict.md` fix list item 1's own required
    /// assertion): the leading-inset check above only ever caught the stuck-selection-accessory
    /// defect; it says nothing about the narrow re-check's own finding against MVP-2g's fix for
    /// it (`.id(listGeneration)`) — that the List was rebuilt from scratch on every exit from
    /// select mode, resetting its scroll position to the top every time (6 of 6 scrolled tour
    /// legs). This scrolls to a row that needs scrolling to reach, selects only that row, taps
    /// Mark Done, and — with NO swipe anywhere after that tap, which would hide exactly this
    /// regression (the verdict's own note on the swipe-to-find loop above: "would hide a
    /// reset") — checks the SAME row is still on screen, within one row height of where it was,
    /// and clear of both bars.
    @MainActor
    func testBatchMarkDoneKeepsAMidListRowOnScreen() throws {
        let app = launchSample()
        openTab("To-Do", in: app)
        let weekHeader = text("Due this week", in: app)
        XCTAssertTrue(scrollUntilHittable(weekHeader, in: app, maxSwipes: 10),
                      "could not scroll to 'Due this week'. Hierarchy: \(app.debugDescription)")

        let rows = elementsWithPrefix("todo.row", in: app)
        // A row under "Due this week": reaching it needs the scroll above, which is the whole
        // point — a reset to the top would put it off screen again. Found by reading each row's
        // own `.frame` directly (no geometry predicate: nothing else in this file trusts
        // `NSPredicate` against a CGRect key, and there is no simulator here to check it would
        // even match).
        var midRow: XCUIElement?
        for index in 0..<rows.count {
            let candidate = rows.element(boundBy: index)
            if candidate.exists, candidate.frame.minY > weekHeader.frame.maxY {
                midRow = candidate
                break
            }
        }
        guard let midRow else {
            XCTFail("no row under 'Due this week'. Hierarchy: \(app.debugDescription)")
            return
        }
        let label = midRow.label

        tapWhenHittable(app.buttons["todo.select"], in: app)
        let row = rows.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(bringClearOfTheBottom(row, in: app), "'\(label)' is not clear of the bottom bar. Hierarchy: \(app.debugDescription)")
        bringClearOfTheTop(row, in: app)
        waitUntilRowAtRest(row, in: app)
        clearTapPoint(row, in: app).tap()
        if !eventually(timeout: 3, { row.isSelected }) {
            waitUntilRowAtRest(row, in: app)
            if !row.isSelected { clearTapPoint(row, in: app).tap() }
        }
        XCTAssertTrue(eventually(timeout: 2) { row.isSelected }, "'\(label)' was not selected after a retry. Hierarchy: \(app.debugDescription)")

        // The resting position right before Mark Done, not before Select was even tapped — so the
        // pre-tap positioning just above (clear of both bars) is already accounted for, and only
        // Mark Done's own exit can move it from here. "Within one row height" (the brief's own
        // tolerance) uses this row's own measured height, not a hard-coded guess.
        waitUntilRowAtRest(row, in: app)
        let rowHeight = row.frame.height
        let originalY = row.frame.minY

        tapWhenHittable(app.buttons["todo.markDone"], in: app)
        XCTAssertFalse(app.buttons["todo.markDone"].exists, "Mark Done did not exit selection mode")

        // No swipe anywhere below: if the list reset to the top, this row is simply gone (or at
        // the wrong y), not merely scrolled-to.
        let after = rows.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
        guard eventually(timeout: 5, { after.exists }) else {
            XCTFail("'\(label)' is gone after Mark Done, with no swipe — the list likely reset " +
                    "to the top. Hierarchy: \(app.debugDescription)")
            return
        }
        XCTAssertEqual(after.frame.minY, originalY, accuracy: rowHeight,
                      "'\(label)' moved by more than one row height after Mark Done, with no " +
                      "swipe — the list likely reset to the top. Hierarchy: \(app.debugDescription)")
        // Still on screen, clear of both bars — not merely present somewhere off the visible area.
        let navBar = app.navigationBars.firstMatch
        if navBar.exists {
            XCTAssertGreaterThanOrEqual(after.frame.minY + 0.5, navBar.frame.maxY,
                                        "'\(label)' sits under the navigation bar after Mark Done. Hierarchy: \(app.debugDescription)")
        }
        let tabBar = app.tabBars.firstMatch
        let bottomEdge = tabBar.exists ? tabBar.frame.minY : app.frame.maxY
        XCTAssertLessThanOrEqual(after.frame.maxY, bottomEdge + 0.5,
                                 "'\(label)' sits under the tab bar after Mark Done. Hierarchy: \(app.debugDescription)")
    }
}
