import XCTest

/// UX-WP-14 (S-1): the Courses list and card on the flagship persona. A11Y-06 (course code and
/// health words in every card's label), no "+" button, and Edit's reorder kept locally.
final class CoursesUITests: TallyUITestCase {
    private static let codes = ["BIO 101", "MATH 122", "ENG 101", "PSY 101", "HIST 210"]
    private static let healthWords = ["On track", "Needs attention", "At risk", "No grade yet"]

    @MainActor
    private func cards(in app: XCUIApplication) -> XCUIElementQuery {
        elements("course.card", in: app)
    }

    @MainActor
    func testCardsCarryCodeAndHealthAndEditReordersLocally() throws {
        let app = launchSample()
        openTab("Courses", in: app)
        let cards = cards(in: app)
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
        XCTAssertEqual(cards.count, 5, "Hierarchy: \(app.debugDescription)")

        // A11Y-06: one element per card, with the code and the health words.
        for index in 0..<cards.count {
            let label = cards.element(boundBy: index).label
            XCTAssertTrue(Self.codes.contains { label.contains($0) }, "no course code in '\(label)'")
            XCTAssertTrue(Self.healthWords.contains { label.contains($0) }, "no health words in '\(label)'")
        }
        // Courses come from Canvas: no "+".
        XCTAssertEqual(app.navigationBars.buttons.matching(NSPredicate(format: "label IN {'Add', '+'}")).count, 0)
        assertEveryButtonHasALabel(app, screen: "Courses")

        // Edit: drag the first card to the bottom with its reorder control, then Done.
        let firstLabel = cards.element(boundBy: 0).label
        tapWhenHittable(app.buttons["courses.edit"], in: app)
        let handles = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Reorder'"))
        XCTAssertTrue(handles.firstMatch.waitForExistence(timeout: 5), "no reorder controls. Hierarchy: \(app.debugDescription)")
        let last = handles.element(boundBy: handles.count - 1)
        handles.element(boundBy: 0).press(forDuration: 1.0, thenDragTo: last)
        tapWhenHittable(app.buttons["courses.edit"], in: app)
        XCTAssertTrue(eventually { cards.element(boundBy: 0).label != firstLabel },
                      "the move did not change the order. Hierarchy: \(app.debugDescription)")
        let movedOrder = (0..<cards.count).map { cards.element(boundBy: $0).label }

        // Kept locally: leave the tab and come back; the order is the student's.
        openTab("Dashboard", in: app)
        openTab("Courses", in: app)
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual((0..<cards.count).map { cards.element(boundBy: $0).label }, movedOrder,
                       "the student's order was not kept")
    }

    /// A11Y-02: at the largest text size the cards scale (a card is several times a line tall),
    /// stay hittable, and the audit finds nothing unwaived.
    @MainActor
    func testCoursesAtAccessibilityXXXL() throws {
        let app = launchSample(arguments: Self.largestTextArguments)
        openTab("Courses", in: app)
        let first = cards(in: app).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(first.isHittable)
        XCTAssertGreaterThan(first.frame.height, 200, "the card did not grow with Dynamic Type: \(first.frame)")
        XCTAssertLessThanOrEqual(first.frame.maxX, app.frame.maxX + 0.5, "the card runs off the screen: \(first.frame)")
        assertEveryButtonHasALabel(app, screen: "Courses AX XXXL")
        assertAccessibilityAudit(app, screen: "Courses AX XXXL")
    }
}
