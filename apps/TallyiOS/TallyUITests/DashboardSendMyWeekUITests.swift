import XCTest

/// Idea 11 ("Send my week", `pmo-audit/.build-audit/ideas1/report.md`): a `ShareLink` on the
/// Dashboard's Week-ahead strip shares the student's own week as plain text -- counts and titles
/// only, never a grade value, respecting "Hide Course Names" (`ScreenPresenterTests
/// .weekShareTextContentRules` covers the content rules). The system share sheet itself is not
/// driven here (the same reasoning
/// `ScreenPresenterTests.swift` documents for `EKEventEditViewController`): this checks only that
/// Tally's own row is present and offers something to share.
final class DashboardSendMyWeekUITests: TallyUITestCase {
    @MainActor
    func testSendMyWeekButtonAppearsOnTheWeekAheadStrip() throws {
        let app = launchSample()
        let button = element("dashboard.shareWeek", in: app)
        XCTAssertTrue(scrollUntilHittable(button, in: app), "Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(button.label.isEmpty, "Hierarchy: \(app.debugDescription)")
    }
}
