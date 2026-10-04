import XCTest

/// UX-WP-14 (S-1) smoke test on the flagship persona: the Courses tab lists every course, each card
/// one element whose label carries the course code and the health words (A11Y-06); Edit is there
/// and "+" is not. The reorder itself is pinned by hosted tests (`HomeModel.moveCourses`,
/// `CourseOrder`); a drag through Edit passed in run 36454544581 before the suite was made lean.
final class CoursesUITests: TallyUITestCase {
    private static let codes = ["BIO 101", "MATH 122", "ENG 101", "PSY 101", "HIST 210"]
    private static let healthWords = ["On track", "Needs attention", "At risk", "No grade yet"]

    @MainActor
    func testCoursesListsEveryCourseWithCodeAndHealth() throws {
        let app = launchSample()
        openTab("Courses", in: app)
        let cards = elements("course.card", in: app)
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
        XCTAssertEqual(cards.count, 5, "Hierarchy: \(app.debugDescription)")
        for index in 0..<cards.count {
            let label = cards.element(boundBy: index).label
            XCTAssertTrue(Self.codes.contains { label.contains($0) }, "no course code in '\(label)'")
            XCTAssertTrue(Self.healthWords.contains { label.contains($0) }, "no health words in '\(label)'")
        }
        // Courses come from Canvas: Edit reorders them, and there is no "+".
        XCTAssertTrue(app.buttons["courses.edit"].exists, "Hierarchy: \(app.debugDescription)")
        XCTAssertEqual(app.navigationBars.buttons.matching(NSPredicate(format: "label IN {'Add', '+'}")).count, 0)
        assertEveryButtonHasALabel(app, screen: "Courses")
    }

    /// UX-SPARK (PRD §2.B): at least one flagship course has enough graded history for the trend
    /// sparkline beside its letter grade.
    @MainActor
    func testCoursesShowAtLeastOneTrendSparkline() throws {
        let app = launchSample()
        openTab("Courses", in: app)
        let cards = elements("course.card", in: app)
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
        let sparklines = elements("course.sparkline", in: app)
        XCTAssertTrue(sparklines.firstMatch.waitForExistence(timeout: 15),
                      "no course.sparkline on screen. Hierarchy: \(app.debugDescription)")
    }
}
