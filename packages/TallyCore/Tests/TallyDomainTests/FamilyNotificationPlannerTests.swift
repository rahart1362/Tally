import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

@Suite("FamilySubjectBudget: §6.4 floor-of-4, weighted-by-due-count split")
struct FamilySubjectBudgetTests {
    @Test func everySubjectGetsAtLeastItsFloorWhenCapAllows() {
        let allocation = FamilySubjectBudget.allocate(
            weights: [(SubjectKey("a"), 10), (SubjectKey("b"), 1)], cap: 20, floorPerSubject: 4)
        #expect(allocation[SubjectKey("a")]! >= 4)
        #expect(allocation[SubjectKey("b")]! >= 4)
        #expect(allocation.values.reduce(0, +) <= 20)
    }

    @Test func moreDueItemsMeansMoreOfTheRemainingSlots() {
        let allocation = FamilySubjectBudget.allocate(
            weights: [(SubjectKey("busy"), 20), (SubjectKey("quiet"), 1)], cap: 24, floorPerSubject: 4)
        // floors: 4 + 4 = 8; remaining 16, split ~20:1 in favour of "busy" by the largest-
        // remainder method — "quiet"'s 1/21 share rounds to 0 whole slots, but its fractional
        // remainder (0.76) is larger than "busy"'s (0.24), so of the 1 leftover slot the method
        // owes somewhere, "quiet" collects it. Either way "quiet" never drops below its floor.
        #expect(allocation[SubjectKey("busy")]! > allocation[SubjectKey("quiet")]!)
        #expect(allocation[SubjectKey("quiet")]! >= 4, "an idle-ish subject never drops below its floor")
    }

    @Test func aSubjectWithZeroDueItemsStillGetsItsFloor() {
        // The caller passes max(1, count), so a true zero-weight subject never reaches this
        // function with weight 0 in practice, but the allocator must not crash or starve it.
        let allocation = FamilySubjectBudget.allocate(weights: [(SubjectKey("idle"), 0)], cap: 10, floorPerSubject: 4)
        #expect(allocation[SubjectKey("idle")] == 4)
    }

    @Test func totalNeverExceedsCapEvenWhenFloorsAlone0Overflow() {
        let allocation = FamilySubjectBudget.allocate(
            weights: (0..<10).map { (SubjectKey("s\($0)"), 1) }, cap: 8, floorPerSubject: 4)
        #expect(allocation.values.reduce(0, +) == 8)
        // Split as evenly as possible: nobody gets starved to make room for an earlier subject's
        // full floor (every value is 0 or 1 here, 8 cap / 10 subjects).
        #expect(Set(allocation.values) == [0, 1])
    }

    @Test func zeroCapGivesEverySubjectZero() {
        let allocation = FamilySubjectBudget.allocate(weights: [(SubjectKey("a"), 5)], cap: 0, floorPerSubject: 4)
        #expect(allocation[SubjectKey("a")] == 0)
    }

    @Test func emptySubjectListAllocatesNothing() {
        #expect(FamilySubjectBudget.allocate(weights: [], cap: 60, floorPerSubject: 4).isEmpty)
    }

    @Test func allocationIsDeterministicAcrossRepeatedCalls() {
        let weights = [(SubjectKey("x"), 7), (SubjectKey("y"), 3), (SubjectKey("z"), 11)]
        let first = FamilySubjectBudget.allocate(weights: weights, cap: 30, floorPerSubject: 4)
        let second = FamilySubjectBudget.allocate(weights: weights, cap: 30, floorPerSubject: 4)
        #expect(first == second)
    }
}

@Suite("FamilyNotificationPlanner: schedules per subject, thread ids, caps (family-linking.md §6.5)")
struct FamilyNotificationPlannerTests {
    static let account = AccountKey("parent-acct")
    static let utc = TimeZone(identifier: "UTC")!
    static let now = Date(timeIntervalSince1970: 1_790_600_400) // 2026-09-28T13:00:00Z (Monday)

    private func assignment(id: String, due: Date?, lock: Date? = nil) -> Assignment {
        Assignment(id: CanvasID(id), courseID: "c1", groupID: "g1", name: "Item \(id)", dueAt: due, lockAt: lock,
                  pointsPossible: 10, gradingType: .points, omitFromFinalGrade: false, htmlURL: nil,
                  submission: Submission(score: nil, grade: nil, submittedAt: nil, gradedAt: nil, postedAt: nil,
                                        excused: false, missing: false, late: false, workflowState: "unsubmitted"))
    }

    @Test func emptySubjectsPlanNothing() {
        let plan = FamilyNotificationPlanner.plan(accountKey: Self.account, subjects: [], now: Self.now, timeZone: Self.utc)
        #expect(plan.isEmpty)
    }

    @Test func weekAheadFiresNextSundayAndIsPassive() throws {
        let subject = FamilySubjectPlanInput(subjectID: SubjectKey("maya"), studentName: "Maya", candidates: [])
        let plan = FamilyNotificationPlanner.plan(accountKey: Self.account, subjects: [subject], now: Self.now, timeZone: Self.utc)
        let weekAhead = try #require(plan.first { $0.kind == .weekAhead })
        #expect(weekAhead.interruptionLevel == .passive)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        #expect(calendar.component(.weekday, from: weekAhead.fireDate) == 1, "Sunday")
        #expect(weekAhead.fireDate > Self.now)
    }

    @Test func missingStillOpenFiresOnlyWhileTheAssignmentIsStillAcceptingWork() {
        let due = Self.now.addingTimeInterval(-3600) // due an hour ago
        let stillOpen = ReminderCandidate(assignment: assignment(id: "a1", due: due, lock: due.addingTimeInterval(7 * 24 * 3600)))
        let closed = ReminderCandidate(assignment: assignment(id: "a2", due: due, lock: due.addingTimeInterval(60))) // lock already passed
        let subject = FamilySubjectPlanInput(subjectID: SubjectKey("maya"), studentName: "Maya", candidates: [stillOpen, closed])
        let plan = FamilyNotificationPlanner.plan(accountKey: Self.account, subjects: [subject], now: Self.now, timeZone: Self.utc)
        let followups = plan.filter { $0.kind == .missingStillOpen }
        #expect(followups.count == 1)
        #expect(followups[0].id.contains(".a1."))
    }

    @Test func dueRemindersAreOffByDefaultAndOnWhenEnabled() {
        let due = Self.now.addingTimeInterval(48 * 3600)
        let candidate = ReminderCandidate(assignment: assignment(id: "a1", due: due))
        let off = FamilySubjectPlanInput(subjectID: SubjectKey("maya"), studentName: "Maya", candidates: [candidate])
        let planOff = FamilyNotificationPlanner.plan(accountKey: Self.account, subjects: [off], now: Self.now, timeZone: Self.utc)
        #expect(!planOff.contains { $0.kind == .dueReminder })

        var settings = FamilySubjectNotificationSettings()
        settings.dueRemindersEnabled = true
        let on = FamilySubjectPlanInput(subjectID: SubjectKey("maya"), studentName: "Maya", candidates: [candidate], settings: settings)
        let planOn = FamilyNotificationPlanner.plan(accountKey: Self.account, subjects: [on], now: Self.now, timeZone: Self.utc)
        #expect(planOn.filter { $0.kind == .dueReminder }.count == 2) // T-24h and T-1h
    }

    @Test func gradePostedAndBelowGoalAreOffByDefaultAndCarryOnlyTheCourseID() throws {
        let noSignals = FamilySubjectPlanInput(subjectID: SubjectKey("maya"), studentName: "Maya", candidates: [],
                                               newlyGradedCourses: [FamilyCourseSignal(courseID: "61001", courseCode: "BIO-1")],
                                               belowGoalCourses: [FamilyCourseSignal(courseID: "61002", courseCode: "ALG-1")])
        let planOff = FamilyNotificationPlanner.plan(accountKey: Self.account, subjects: [noSignals], now: Self.now, timeZone: Self.utc)
        #expect(!planOff.contains { $0.kind == .gradePosted || $0.kind == .belowGoal }, "off by default")

        var settings = FamilySubjectNotificationSettings()
        settings.gradePostedEnabled = true
        settings.belowGoalEnabled = true
        let subject = FamilySubjectPlanInput(
            subjectID: SubjectKey("maya"), studentName: "Maya", candidates: [],
            newlyGradedCourses: [FamilyCourseSignal(courseID: "61001", courseCode: "BIO-1")],
            belowGoalCourses: [FamilyCourseSignal(courseID: "61002", courseCode: "ALG-1")], settings: settings)
        let plan = FamilyNotificationPlanner.plan(accountKey: Self.account, subjects: [subject], now: Self.now, timeZone: Self.utc)
        let posted = try #require(plan.first { $0.kind == .gradePosted })
        #expect(posted.id.contains(".61001."))
        let attention = try #require(plan.first { $0.kind == .belowGoal })
        #expect(attention.id.contains(".61002."))
    }

    @Test func everyIDIsThreadedAndScopedToItsSubject() {
        let subject = FamilySubjectPlanInput(subjectID: SubjectKey("subj-123"), studentName: "Maya", candidates: [])
        let plan = FamilyNotificationPlanner.plan(accountKey: Self.account, subjects: [subject], now: Self.now, timeZone: Self.utc)
        for reminder in plan {
            #expect(reminder.threadIdentifier == "subj-123")
            #expect(reminder.id.hasPrefix("tally.\(Self.account.rawValue).subj-123."))
            #expect(reminder.subjectID == SubjectKey("subj-123"))
        }
    }

    @Test func twoSubjectsNeverCollideAndEachStaysUnderItsOwnBudget() {
        let due = Self.now.addingTimeInterval(48 * 3600)
        let manyCandidates = (0..<30).map { ReminderCandidate(assignment: assignment(id: "busy\($0)", due: due.addingTimeInterval(Double($0) * 60))) }
        let busy = FamilySubjectPlanInput(subjectID: SubjectKey("busy"), studentName: "Busy", candidates: manyCandidates)
        let quiet = FamilySubjectPlanInput(subjectID: SubjectKey("quiet"), studentName: "Quiet", candidates: [])
        let plan = FamilyNotificationPlanner.plan(accountKey: Self.account, subjects: [busy, quiet], now: Self.now,
                                                  timeZone: Self.utc, cap: 20, floorPerSubject: 4)
        #expect(plan.count <= 20)
        #expect(plan.contains { $0.subjectID == SubjectKey("quiet") }, "the quiet subject still keeps its floor")
        #expect(Set(plan.map(\.id)).count == plan.count, "no id collides across subjects")
    }

    @Test func aPastFireDateIsNeverScheduled() {
        // A follow-up computed into the past (due long before `now`, lock already passed) must
        // never be handed back, mirroring ReminderPlanner's own horizon filter.
        let longAgo = Self.now.addingTimeInterval(-30 * 24 * 3600)
        let candidate = ReminderCandidate(assignment: assignment(id: "old", due: longAgo, lock: longAgo.addingTimeInterval(3600)))
        let subject = FamilySubjectPlanInput(subjectID: SubjectKey("maya"), studentName: "Maya", candidates: [candidate])
        let plan = FamilyNotificationPlanner.plan(accountKey: Self.account, subjects: [subject], now: Self.now, timeZone: Self.utc)
        #expect(!plan.contains { $0.kind == .missingStillOpen })
    }
}
