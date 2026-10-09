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

        // UX-SPARK-2's dedicated trend column (D14) makes each card taller, so the flagship's 5
        // may no longer all be simultaneously materialized in a List's lazy viewport the way they
        // were before — this moved the element this test checks (run 37925235523 found 4, not 5,
        // with the list scrolled no further than its rest position). Collecting codes while
        // scrolling checks the same thing (every course shows with its code and health words)
        // without assuming they all fit on screen at once.
        var seenLabels: [String: String] = [:]
        for _ in 0..<8 {
            for index in 0..<cards.count {
                let label = cards.element(boundBy: index).label
                if let code = Self.codes.first(where: { label.contains($0) }) {
                    seenLabels[code] = label
                }
            }
            if seenLabels.count == Self.codes.count { break }
            app.swipeUp()
        }
        XCTAssertEqual(Set(seenLabels.keys), Set(Self.codes), "Hierarchy: \(app.debugDescription)")
        for (code, label) in seenLabels {
            XCTAssertTrue(Self.healthWords.contains { label.contains($0) }, "\(code): no health words in '\(label)'")
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
