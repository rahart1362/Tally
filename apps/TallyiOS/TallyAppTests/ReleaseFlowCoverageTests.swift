import XCTest
import TallyDomain

/// ASC-10 release-gate flows (program plan §3, MVP milestone): `REL.flow.07-threshold-alert` and
/// `REL.flow.08-quiet-hours` (`scripts/ci/check_release.py`'s `FLOWS`). `ReminderPlanner` (E07) is
/// already exhaustively covered by `ReminderPlannerTests`
/// (packages/TallyCore/Tests/TallyDomainTests), but that suite runs under `swift test` on Linux
/// (`make core-test`) and never produces an xcresult, so it cannot satisfy the release gate's flow
/// checks, which read only the iOS gate's own xcresult (`xcresulttool get test-results tests`).
/// These two lean hosted tests call the same public planner directly, so the gate has its own
/// Xcode-run proof that a reminder is scheduled ahead of its due date and that quiet hours shift it
/// earlier. No test hook, no DEBUG-only support (`ReminderTestHooks` et al. need `TALLY_TEST_HOOKS`,
/// which only `make ios-perf` sets): both run in the Release configuration.
final class ReleaseFlowCoverageTests: XCTestCase {
    private static let account = AccountKey("release-flow-coverage")
    private static let utc = TimeZone(identifier: "UTC")!
    private static let now = Date(timeIntervalSince1970: 1_790_600_400) // 2026-09-28T13:00:00Z (Monday)

    private func assignment(id: String, due: Date) -> Assignment {
        Assignment(id: CanvasID(id), courseID: CanvasID("c1"), groupID: CanvasID("g1"), name: "Item \(id)",
                  dueAt: due, lockAt: nil, pointsPossible: 10, gradingType: .points, omitFromFinalGrade: false,
                  htmlURL: nil, submission: nil)
    }

    /// REL.flow.07-threshold-alert: a due item is actually planned for a reminder, ahead of its own
    /// deadline, through the real `ReminderPlanner` — not a fixture pretending it is. Mirrors
    /// `ReminderPlannerTests.balancedDefaultsAre24hAnd1hBeforeDue` (TallyCore, Linux): the same
    /// scenario, run here so the iOS gate has its own xcresult-backed proof.
    func testThresholdAlertIsScheduled() {
        let due = Self.now.addingTimeInterval(48 * 3600) // clear of quiet hours and the horizon edges
        let candidate = ReminderCandidate(assignment: assignment(id: "a1", due: due))
        let plan = ReminderPlanner.plan(
            accountKey: Self.account, candidates: [candidate], settings: ReminderSettings(missingFollowupEnabled: false),
            now: Self.now, timeZone: Self.utc, refresh: RefreshRecord())
        let dueReminders = plan.filter { $0.kind == .due }
        XCTAssertEqual(dueReminders.count, 2, "the balanced default (24h and 1h before due) did not schedule a reminder")
        XCTAssertTrue(dueReminders.allSatisfy { $0.fireDate < due }, "a reminder fired at or after its own due date")
    }

    /// REL.flow.08-quiet-hours: a fire time inside the default 23:00-07:00 window moves earlier,
    /// never later, and lands outside the window — through the same `ReminderPlanner.shiftOutOfQuietHours`
    /// `ReminderPlannerTests.quietHoursShiftEarlierBy15Minutes` (TallyCore, Linux) exercises.
    func testQuietHoursShiftReminderOutsideTheWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        let insideQuietHours = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 23, minute: 30))!
        let shifted = ReminderPlanner.shiftOutOfQuietHours(insideQuietHours, quietHours: QuietHours(), timeZone: Self.utc)
        XCTAssertLessThanOrEqual(shifted, insideQuietHours, "quiet hours must never move a reminder later")
        let quiet = QuietHours()
        let startMinutes = quiet.startHour * 60 + quiet.startMinute
        let shiftedMinutes = calendar.component(.hour, from: shifted) * 60 + calendar.component(.minute, from: shifted)
        XCTAssertLessThan(shiftedMinutes, startMinutes, "the shifted time is still inside the quiet-hours window")
    }
}
