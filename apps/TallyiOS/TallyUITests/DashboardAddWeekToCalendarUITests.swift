import XCTest

/// Idea 10 ("Add this week to Calendar", `pmo-audit/.build-audit/ideas1/report.md`): a button on
/// the Dashboard's Week-ahead strip walks the existing per-item sheet
/// (`AddToCalendarView`/`EKEventEditViewController`, PMO R6 -- zero permission) across the week's
/// due items. The system sheet itself is never UI-tested (the owner's guidance,
/// `ScreenPresenterTests.swift`); this checks only the button Tally owns.
final class DashboardAddWeekToCalendarUITests: TallyUITestCase {
    @MainActor
    func testAddWeekToCalendarButtonAppearsOnTheWeekAheadStrip() throws {
        let app = launchSample()
        let button = element("dashboard.addWeekToCalendar", in: app)
        XCTAssertTrue(scrollUntilHittable(button, in: app), "Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(button.label.isEmpty, "Hierarchy: \(app.debugDescription)")
    }
}
