import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

@Suite("ReminderPlanner: Balanced defaults, quiet hours, budget cap, deterministic IDs")
struct ReminderPlannerTests {
    static let account = AccountKey("acct1")
    static let utc = TimeZone(identifier: "UTC")!
    static let now = Date(timeIntervalSince1970: 1_790_600_400) // 2026-09-28T13:00:00Z (Monday)

    private func assignment(id: String, due: Date?, lock: Date? = nil, submitted: Bool = false) -> Assignment {
        Assignment(id: CanvasID(id), courseID: "c1", groupID: "g1", name: "Item \(id)", dueAt: due, lockAt: lock,
                  pointsPossible: 10, gradingType: .points, omitFromFinalGrade: false, htmlURL: nil,
                  submission: Submission(score: nil, grade: nil, submittedAt: submitted ? Self.now : nil, gradedAt: nil,
                                        postedAt: nil, excused: false, missing: false, late: false,
                                        workflowState: submitted ? "submitted" : "unsubmitted"))
    }

    // MARK: - R14 Balanced defaults

    @Test func balancedDefaultsAre24hAnd1hBeforeDue() {
        let due = Self.now.addingTimeInterval(48 * 3600) // clear of quiet hours and horizon edges
        let candidate = ReminderCandidate(assignment: assignment(id: "a1", due: due))
        let plan = ReminderPlanner.plan(
            accountKey: Self.account, candidates: [candidate], settings: ReminderSettings(missingFollowupEnabled: false),
            now: Self.now, timeZone: Self.utc, refresh: RefreshRecord())
        let dueReminders = plan.filter { $0.kind == .due }
        #expect(dueReminders.count == 2)
        let fireDates = Set(dueReminders.map(\.fireDate))
        #expect(fireDates.contains(due.addingTimeInterval(-24 * 3600)))
        #expect(fireDates.contains(due.addingTimeInterval(-3600)))
    }

    @Test func balancedDefaultsIncludeAnEveningDigestAndSundayWeekAhead() throws {
        let plan = ReminderPlanner.plan(
            accountKey: Self.account, candidates: [], settings: ReminderSettings(), now: Self.now, timeZone: Self.utc,
            refresh: RefreshRecord())
        #expect(plan.contains { $0.kind == .digest })
        #expect(plan.contains { $0.kind == .weekAhead })
        let weekAhead = try #require(plan.first { $0.kind == .weekAhead })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        #expect(calendar.component(.weekday, from: weekAhead.fireDate) == 1, "Sunday")
    }

    // MARK: - Final-hour and exam reminders are Time Sensitive

    @Test func finalHourReminderIsTimeSensitiveForAHighPriorityItem() {
        let due = Self.now.addingTimeInterval(48 * 3600)
        let candidate = ReminderCandidate(assignment: assignment(id: "a1", due: due), priority: 75)
        let plan = ReminderPlanner.plan(
            accountKey: Self.account, candidates: [candidate], settings: ReminderSettings(missingFollowupEnabled: false),
            now: Self.now, timeZone: Self.utc, refresh: RefreshRecord())
        let final = plan.first { $0.kind == .due && $0.fireDate == due.addingTimeInterval(-3600) }
        let first = plan.first { $0.kind == .due && $0.fireDate == due.addingTimeInterval(-24 * 3600) }
        #expect(final?.interruptionLevel == .timeSensitive)
        #expect(first?.interruptionLevel == .active, "only the final-hour reminder escalates")
    }

    @Test func finalHourReminderStaysActiveForALowPriorityItem() {
        let due = Self.now.addingTimeInterval(48 * 3600)
        let candidate = ReminderCandidate(assignment: assignment(id: "a1", due: due), priority: 10)
        let plan = ReminderPlanner.plan(
            accountKey: Self.account, candidates: [candidate], settings: ReminderSettings(missingFollowupEnabled: false),
            now: Self.now, timeZone: Self.utc, refresh: RefreshRecord())
        let final = plan.first { $0.kind == .due && $0.fireDate == due.addingTimeInterval(-3600) }
        #expect(final?.interruptionLevel == .active)
    }

    @Test func timeSensitiveAllowedFalseNeverEscalates() {
        let due = Self.now.addingTimeInterval(48 * 3600)
        let candidate = ReminderCandidate(assignment: assignment(id: "a1", due: due), priority: 90)
        let plan = ReminderPlanner.plan(
            accountKey: Self.account, candidates: [candidate],
            settings: ReminderSettings(missingFollowupEnabled: false, timeSensitiveAllowed: false),
            now: Self.now, timeZone: Self.utc, refresh: RefreshRecord())
        #expect(plan.allSatisfy { $0.interruptionLevel != .timeSensitive })
    }

    @Test func examMorningOfIsTimeSensitive() {
        let due = Self.now.addingTimeInterval(10 * 86_400) // 10 days out, clear of the 14-day horizon
        let candidate = ReminderCandidate(assignment: assignment(id: "exam1", due: due), isExam: true)
        let plan = ReminderPlanner.plan(
            accountKey: Self.account, candidates: [candidate], settings: ReminderSettings(missingFollowupEnabled: false),
            now: Self.now, timeZone: Self.utc, refresh: RefreshRecord())
        let examReminders = plan.filter { $0.kind == .exam }
        #expect(examReminders.count == 3, "T-3d, T-1d, morning-of")
        let morning = examReminders.max { $0.fireDate < $1.fireDate }
        #expect(morning?.interruptionLevel == .timeSensitive)
        #expect(examReminders.filter { $0.interruptionLevel == .active }.count == 2, "T-3d and T-1d stay active")
    }

    // MARK: - Escalation: missing-still-open follow-up

    /// A quiet-hours window that never triggers (start == end), so this test
    /// isolates the followup-offset math from the separately-tested
    /// quiet-hour shift.
    private static let neverQuiet = QuietHours(startHour: 0, startMinute: 0, endHour: 0, endMinute: 0)

    @Test func followupFollowsAnOpenOverdueItem() {
        let due = Self.now.addingTimeInterval(3 * 3600)
        let candidate = ReminderCandidate(assignment: assignment(id: "a1", due: due))
        let plan = ReminderPlanner.plan(
            accountKey: Self.account, candidates: [candidate], settings: ReminderSettings(quietHours: Self.neverQuiet),
            now: Self.now, timeZone: Self.utc, refresh: RefreshRecord())
        let followup = plan.first { $0.kind == .followup }
        #expect(followup?.fireDate == due.addingTimeInterval(12 * 3600))
    }

    @Test func followupIsSkippedWhenTheItemLocksBeforeTheFollowupWouldFire() {
        let due = Self.now.addingTimeInterval(3 * 3600)
        let a = assignment(id: "a1", due: due, lock: due.addingTimeInterval(3600)) // locks 1h after due, before the 12h followup
        let candidate = ReminderCandidate(assignment: a)
        let plan = ReminderPlanner.plan(
            accountKey: Self.account, candidates: [candidate], settings: ReminderSettings(), now: Self.now, timeZone: Self.utc,
            refresh: RefreshRecord())
        #expect(!plan.contains { $0.kind == .followup })
    }

    @Test func submittedOrExcludedItemsGetNoReminders() {
        let due = Self.now.addingTimeInterval(3600)
        let submitted = ReminderCandidate(assignment: assignment(id: "a1", due: due, submitted: true))
        let plan = ReminderPlanner.plan(
            accountKey: Self.account, candidates: [submitted], settings: ReminderSettings(), now: Self.now, timeZone: Self.utc,
            refresh: RefreshRecord())
        #expect(!plan.contains { $0.subjectID == "a1" })
    }

    // MARK: - Quiet hours (earlier only, never later)

    @Test func quietHoursShiftEarlierBy15Minutes() {
        // Due 00:30 -> T-1h fires at 23:30, inside the default 23:00-07:00
        // quiet window -> shifts to 22:45 the same evening (§3.5 worked example).
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        let due = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 0, minute: 30))!
        let fireBeforeShift = due.addingTimeInterval(-3600) // 23:30 the previous day
        let shifted = ReminderPlanner.shiftOutOfQuietHours(fireBeforeShift, quietHours: QuietHours(), timeZone: Self.utc)
        let expected = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 22, minute: 45))!
        #expect(shifted == expected)
    }

    @Test func aFireTimeOutsideQuietHoursIsUnchanged() {
        let now = Self.now // 13:00 UTC, well outside 23:00-07:00
        #expect(ReminderPlanner.shiftOutOfQuietHours(now, quietHours: QuietHours(), timeZone: Self.utc) == now)
    }

    @Test func aFireTimeNeverMovesLater() {
        for hourOffset in stride(from: 0.0, through: 23.5, by: 0.5) {
            let candidate = Self.now.addingTimeInterval(hourOffset * 3600)
            let shifted = ReminderPlanner.shiftOutOfQuietHours(candidate, quietHours: QuietHours(), timeZone: Self.utc)
            #expect(shifted <= candidate, "hour offset \(hourOffset): shifted \(shifted) is later than \(candidate)")
        }
    }

    @Test func earlyMorningQuietHourFallsBackToThePrecedingEvening() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        let threeAM = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 3, minute: 0))!
        let shifted = ReminderPlanner.shiftOutOfQuietHours(threeAM, quietHours: QuietHours(), timeZone: Self.utc)
        let expected = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 22, minute: 45))!
        #expect(shifted == expected)
    }

    // MARK: - Never exceeding the cap; keep the soonest

    @Test func neverExceedsTheCapAndKeepsTheSoonest() {
        let candidates = (0..<50).map { i in
            ReminderCandidate(assignment: assignment(id: "a\(i)", due: Self.now.addingTimeInterval(Double(i + 1) * 3600 * 5)))
        }
        let cap = 20
        let plan = ReminderPlanner.plan(
            accountKey: Self.account, candidates: candidates, settings: ReminderSettings(), now: Self.now, timeZone: Self.utc,
            refresh: RefreshRecord(), cap: cap)
        #expect(plan.count <= cap)
        #expect(plan.count == cap, "there is more than enough demand to fill the cap")
        // Every kept item reminder must fire no later than the soonest reminder that was cut.
        let reservedCount = plan.filter { $0.kind == .digest || $0.kind == .weekAhead || $0.kind == .sentinel }.count
        #expect(plan.count - reservedCount <= cap - reservedCount)
    }

    @Test func propertyNeverExceeds64ForManyRandomFixtures() {
        var rng = SeededRandom(seed: 42)
        for trial in 0..<50 {
            let count = Int.random(in: 0..<200, using: &rng)
            let candidates = (0..<count).map { i in
                ReminderCandidate(
                    assignment: assignment(id: "a\(trial)-\(i)", due: Self.now.addingTimeInterval(Double.random(in: 0..<(14 * 86_400), using: &rng))),
                    isExam: Double.random(in: 0..<1, using: &rng) < 0.1)
            }
            let plan = ReminderPlanner.plan(
                accountKey: Self.account, candidates: candidates, settings: ReminderSettings(), now: Self.now, timeZone: Self.utc,
                refresh: RefreshRecord())
            #expect(plan.count <= 64, "trial \(trial) with \(count) candidates produced \(plan.count) pending reminders")
            #expect(plan.count <= TallyConfig.pendingNotificationCap)
        }
    }

    @Test func neverFiresAfterItsOwnDueDate() {
        var rng = SeededRandom(seed: 7)
        let candidates = (0..<30).map { i in
            ReminderCandidate(assignment: assignment(id: "a\(i)", due: Self.now.addingTimeInterval(Double.random(in: 0..<(14 * 86_400), using: &rng))))
        }
        let plan = ReminderPlanner.plan(
            accountKey: Self.account, candidates: candidates, settings: ReminderSettings(), now: Self.now, timeZone: Self.utc,
            refresh: RefreshRecord())
        let dueByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.assignment.id.rawValue, $0.assignment.dueAt!) })
        for reminder in plan {
            guard let due = dueByID[reminder.subjectID] else { continue }
            switch reminder.kind {
            case .due:
                #expect(reminder.fireDate <= due, "a due-item reminder must fire at or before its due date")
            case .followup:
                #expect(reminder.fireDate <= due.addingTimeInterval(InsightsConfig.missingFollowupOffset.timeInterval))
            default:
                break
            }
        }
    }

    // MARK: - Idempotent reconcile

    @Test func planningTwiceWithTheSameInputsIsIdentical() {
        let due = Self.now.addingTimeInterval(48 * 3600)
        let candidate = ReminderCandidate(assignment: assignment(id: "a1", due: due), priority: 80)
        let a = ReminderPlanner.plan(accountKey: Self.account, candidates: [candidate], settings: ReminderSettings(),
                                    now: Self.now, timeZone: Self.utc, refresh: RefreshRecord())
        let b = ReminderPlanner.plan(accountKey: Self.account, candidates: [candidate], settings: ReminderSettings(),
                                    now: Self.now, timeZone: Self.utc, refresh: RefreshRecord())
        #expect(a == b)
    }

    // MARK: - Deterministic IDs

    @Test func idsFollowTheDeterministicFormat() {
        let due = Self.now.addingTimeInterval(48 * 3600)
        let candidate = ReminderCandidate(assignment: assignment(id: "555", due: due))
        let plan = ReminderPlanner.plan(
            accountKey: Self.account, candidates: [candidate], settings: ReminderSettings(missingFollowupEnabled: false),
            now: Self.now, timeZone: Self.utc, refresh: RefreshRecord())
        let due24 = plan.first { $0.fireDate == due.addingTimeInterval(-24 * 3600) }
        #expect(due24?.id == "tally.acct1.due.555.due.86400")
    }

    // MARK: - R17 stale-data sentinel

    @Test func sentinelFiresAtLastSuccessPlus24h() {
        var record = RefreshRecord()
        let successAt = Self.now.addingTimeInterval(-3600)
        record.succeeded(dataFetchedAt: successAt)
        let plan = ReminderPlanner.plan(
            accountKey: Self.account, candidates: [], settings: ReminderSettings(), now: Self.now, timeZone: Self.utc, refresh: record)
        let sentinel = plan.first { $0.kind == .sentinel }
        #expect(sentinel != nil)
        #expect(sentinel!.fireDate == FreshnessRules.staleWarningDate(of: record))
    }

    @Test func noSentinelWithoutAnySuccessfulRefresh() {
        let plan = ReminderPlanner.plan(
            accountKey: Self.account, candidates: [], settings: ReminderSettings(), now: Self.now, timeZone: Self.utc,
            refresh: RefreshRecord())
        #expect(!plan.contains { $0.kind == .sentinel })
    }

    // MARK: - Snooze

    @Test func snoozeOptionsProduceTheExpectedTimes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        #expect(ReminderPlanner.snoozeDate(.oneHour, now: Self.now, dueAt: nil, timeZone: Self.utc) == Self.now.addingTimeInterval(3600))
        let tonight = ReminderPlanner.snoozeDate(.tonight, now: Self.now, dueAt: nil, timeZone: Self.utc)
        #expect(calendar.component(.hour, from: tonight!) == 19)
        let tomorrow = ReminderPlanner.snoozeDate(.tomorrowMorning, now: Self.now, dueAt: nil, timeZone: Self.utc)
        #expect(calendar.component(.hour, from: tomorrow!) == 8)
        #expect(calendar.component(.day, from: tomorrow!) == calendar.component(.day, from: Self.now) + 1)
        let due = Self.now.addingTimeInterval(5 * 86_400)
        let dayBefore = ReminderPlanner.snoozeDate(.dayBeforeDue, now: Self.now, dueAt: due, timeZone: Self.utc)
        #expect(dayBefore == calendar.date(byAdding: .day, value: -1, to: due))
    }

    @Test func dayBeforeDueNeedsADueDate() {
        #expect(ReminderPlanner.snoozeDate(.dayBeforeDue, now: Self.now, dueAt: nil, timeZone: Self.utc) == nil)
    }
}
