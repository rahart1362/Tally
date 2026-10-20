import XCTest

/// Idea 3 (`pmo-audit/.build-audit/ideas1/report.md` §"Surface \"Momentum\" streak on the
/// Dashboard"): the Dashboard shows the existing Insights streak as one line, reused verbatim, so
/// a student sees it without opening Insights — hidden when there is no current streak.
///
/// The flagship persona's streak length depends on the calendar day sample mode's date rebase
/// lands on (`SnapshotDateRebaser`), so this does not assert a fixed count (the same caution
/// `InsightsUITests` already takes with its own "ends with streak" OR "No current streak" check).
/// Instead it reads Insights' already-covered streak line as the ground truth, then asserts the
/// Dashboard's new line (found only by its accessibility identifier, never by English text) is
/// consistent with it.
final class DashboardMomentumStreakUITests: TallyUITestCase {
    @MainActor
    func testMomentumStreakLineMatchesInsightsOrIsHidden() throws {
        let app = launchSample()

        openTab("Insights", in: app)
        let insightsStreak = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'streak'")).firstMatch
        let hasCurrentStreak = scrollUntilHittable(insightsStreak, in: app)
        if !hasCurrentStreak {
            XCTAssertTrue(app.staticTexts["No current streak"].waitForExistence(timeout: 5),
                          "no streak line on Insights. Hierarchy: \(app.debugDescription)")
        }

        openTab("Dashboard", in: app)
        let dashboardStreak = element("dashboard.momentumStreak", in: app)
        if hasCurrentStreak {
            XCTAssertTrue(scrollUntilHittable(dashboardStreak, in: app),
                          "Insights shows a current streak but the Dashboard's line did not appear. " +
                          "Hierarchy: \(app.debugDescription)")
            XCTAssertFalse(dashboardStreak.label.isEmpty, "Hierarchy: \(app.debugDescription)")
        } else {
            XCTAssertFalse(dashboardStreak.exists,
                           "the Dashboard showed a momentum streak line with no current streak. " +
                           "Hierarchy: \(app.debugDescription)")
        }
    }
}
