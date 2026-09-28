import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

/// R-4 (resilience.md; crash-safety-2.md F-8 and F-10): public entry points that trusted their
/// caller. None of these values comes from Canvas today (every caller in TallyCore passes a bounded
/// priority and the default cap), but each is a public parameter or a snapshot that can bypass the
/// gateway, and each used to trap or to depend on `Dictionary` order.
@Suite("Entry points that trusted their caller (R-4)", .timeLimit(.minutes(TestTimeBudget.minutes(1))))
struct HardenedEntryPointTests {
    private static let now = Date(timeIntervalSince1970: 1_790_600_400) // 2026-09-28T13:00:00Z
    private static let utc = TimeZone(secondsFromGMT: 0) ?? .current

    private static func assignment(_ id: CanvasID<Assignment>, dueInHours hours: Double) -> Assignment {
        Assignment(id: id, courseID: "c1", groupID: "g1", name: "A", dueAt: now.addingTimeInterval(hours * 3_600), lockAt: nil,
                   pointsPossible: 10, gradingType: .points, omitFromFinalGrade: false, htmlURL: nil,
                   submission: Submission(score: nil, grade: nil, submittedAt: nil, gradedAt: nil, postedAt: nil,
                                          excused: false, missing: false, late: false, workflowState: "unsubmitted"),
                   submissionTypes: ["online_upload"])
    }

    // MARK: - AlertEngine.dueSoonAlert: `Int(priorityScore)`

    /// NaN missed the critical test and reached `Int(NaN)` in the high branch; an infinity or
    /// 2^63 trapped in `Int(_:)` too.
    @Test(arguments: [Double.nan, .infinity, -.infinity, 1e300, -1e300, Double(Int.max)])
    func aDueSoonAlertTakesAnyPriorityScore(_ score: Double) {
        let alert = AlertEngine.dueSoonAlert(assignment: Self.assignment("a1", dueInHours: 10), priorityScore: score, weight: 0.5,
                                             now: Self.now)
        #expect(alert != nil)
        #expect((0...99).contains(alert?.priority ?? -1))
        #expect(alert?.priority == (score.isNaN || score < 0 ? 0 : 99))
    }

    // MARK: - ReminderPlanner: a negative cap

    private func plan(cap: Int) -> [PendingReminder] {
        var refresh = RefreshRecord()
        refresh.succeeded(dataFetchedAt: Self.now) // so the R17 stale-data sentinel is reserved too
        let candidates = (1...5).map { ReminderCandidate(assignment: Self.assignment(CanvasID("a\($0)"), dueInHours: Double($0) * 30)) }
        return ReminderPlanner.plan(accountKey: AccountKey("acct"), candidates: candidates, settings: ReminderSettings(),
                                    now: Self.now, timeZone: Self.utc, refresh: refresh, cap: cap)
    }

    /// A negative cap is 0: nothing pending. The reserved account-level reminders used to come
    /// back whatever the cap, and `Int.min` overflowed `cap - reserved.count` and trapped.
    @Test(arguments: [-1, -60, Int.min])
    func aNegativeReminderCapIsZero(_ cap: Int) {
        #expect(plan(cap: cap).isEmpty)
        #expect(plan(cap: cap) == plan(cap: 0))
    }

    /// A cap below the reserved count keeps reserved reminders in their order (digest, week ahead,
    /// stale-data sentinel), and never more than the cap.
    @Test func aCapBelowTheReservedCountKeepsTheFirstReserved() {
        #expect(plan(cap: 1).map(\.kind) == [.digest])
        #expect(plan(cap: 2).count == 2)
        #expect(plan(cap: 3).count == 3)
        #expect(plan(cap: 60).count > 3)
    }

    // MARK: - ChangeDigest: the first occurrence of a repeated assignment

    /// The repeat is due 2.5 days out, the original 2. Keeping the first, nothing moved; keeping the
    /// last (as it did, in `Dictionary` order across courses) reported a due-date change.
    @Test(arguments: [DuplicateIDFixture.Kind.assignmentWithinGroup, .assignmentAcrossGroups, .assignmentGroup, .assignmentAcrossCourses])
    func aDigestComparesTheFirstOccurrenceOfARepeatedAssignment(_ kind: DuplicateIDFixture.Kind) {
        let base = DuplicateIDFixture.base()
        let repeated = DuplicateIDFixture.snapshot(duplicating: kind)
        #expect(ChangeDigest.diff(old: base, new: repeated).dueDateChanges.isEmpty)
        #expect(ChangeDigest.diff(old: repeated, new: base).dueDateChanges.isEmpty)
        #expect(ChangeDigest.diff(old: base, new: repeated) == ChangeDigest.diff(old: base, new: base))
    }

    /// The gateway drops a repeated group whole, its assignment list with it (CS-07's
    /// `SnapshotDeduplication`), so the digest does too: an assignment found only in the repeat of a
    /// group is not "new".
    @Test func aDigestSkipsARepeatedGroupWholeLikeTheGateway() {
        let base = DuplicateIDFixture.base()
        var groups = base.groups
        let onlyInTheRepeat = Assignment(id: "8119", courseID: DuplicateIDFixture.biology, groupID: "9011", name: "Lab report 9",
                                         dueAt: nil, lockAt: nil, pointsPossible: 10, gradingType: .points,
                                         omitFromFinalGrade: false, htmlURL: nil, submission: nil)
        let repeatedGroup = AssignmentGroup(id: "9011", name: "Homework (repeat)", position: 1, weight: 5, rules: DropRules(),
                                            assignments: [onlyInTheRepeat])
        groups[DuplicateIDFixture.biology, default: []].append(repeatedGroup)
        let repeated = CanvasSnapshot(generation: 1, accountKey: base.accountKey, host: base.host, fetchedAt: base.fetchedAt,
                                      profile: base.profile, courses: base.courses, groups: groups,
                                      gradingPeriods: base.gradingPeriods, planner: base.planner, events: base.events,
                                      announcements: base.announcements, courseColors: base.courseColors, sections: base.sections)
        #expect(ChangeDigest.diff(old: base, new: repeated).newAssignments.isEmpty)
        #expect(ChangeDigest.diff(old: base, new: repeated) == ChangeDigest.diff(old: base, new: base))
    }
}
