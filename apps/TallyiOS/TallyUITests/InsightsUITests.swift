import XCTest

/// UX-WP-19 (S-6): Insights on the flagship persona. Both charts have a label and a value
/// (A11Y-08: `chart.trend`, `chart.weights`), every card's title is on the screen, and the streak
/// is a line of words. (The header trait, the `flame` symbol and "no emoji" are checked in code and
/// by `ScreenSourceHygieneTests`, not here.)
final class InsightsUITests: TallyUITestCase {
    private static let cardTitles = ["Performance trend", "Category breakdown", "Completion", "Momentum",
                                     "Needs a look", "Heavy stretches"]

    @MainActor
    func testChartsHaveDescriptorsAndCardsHaveTitles() throws {
        let app = launchSample()
        openTab("Insights", in: app)

        // The trend is grade math off the main actor; it lands shortly after the screen.
        let trend = element("chart.trend", in: app)
        XCTAssertTrue(trend.waitForExistence(timeout: 30), "no trend chart. Hierarchy: \(app.debugDescription)")
        XCTAssertEqual(trend.label, "Performance trend")
        let trendValue = trend.value as? String ?? ""
        XCTAssertTrue(trendValue.contains("percent"), "trend value: '\(trendValue)'")

        let weights = element("chart.weights", in: app)
        XCTAssertTrue(scrollUntilHittable(weights, in: app), "no category chart. Hierarchy: \(app.debugDescription)")
        XCTAssertEqual(weights.label, "Category breakdown")
        XCTAssertFalse((weights.value as? String ?? "").isEmpty)

        for title in Self.cardTitles {
            let header = text(title, in: app)
            XCTAssertTrue(scrollUntilHittable(header, in: app), "no '\(title)' card. Hierarchy: \(app.debugDescription)")
        }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'streak'")).firstMatch.exists
                      || app.staticTexts["No current streak"].exists,
                      "no streak line. Hierarchy: \(app.debugDescription)")
        XCTAssertGreaterThan(elements("insights.risk", in: app).count, 0)
        assertEveryButtonHasALabel(app, screen: "Insights")
    }

    /// A11Y-02 at the largest text size.
    @MainActor
    func testInsightsAtAccessibilityXXXL() throws {
        let app = launchSample(arguments: Self.largestTextArguments)
        openTab("Insights", in: app)
        let header = text("Performance trend", in: app)
        XCTAssertTrue(header.waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
        XCTAssertGreaterThan(header.frame.height, 40, "the title did not grow with Dynamic Type: \(header.frame)")
        XCTAssertTrue(element("chart.trend", in: app).waitForExistence(timeout: 30), "Hierarchy: \(app.debugDescription)")
        assertEveryButtonHasALabel(app, screen: "Insights AX XXXL")
        assertAccessibilityAudit(app, screen: "Insights AX XXXL")
    }
}
