import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

/// CS-07 (crash-safety-2.md, CS7-1): every pure post-fetch consumer in `TallyDomain` survives a
/// snapshot that repeats an identifier. `DashboardBuilder.build` used to trap
/// (`Dictionary(uniqueKeysWithValues:)`, "Fatal error: Duplicate values for key") on a repeated
/// course or assignment ID, and `ChangeDigest.diff` on a repeated course ID in the older
/// snapshot. The consumers must survive on their own, because `GradeInput` and what-if callers
/// build values directly and never pass through the gateway's de-duplication.
@Suite("Repeated identifiers: TallyDomain consumers never trap (CS-07)", .timeLimit(.minutes(TestTimeBudget.minutes(1))))
struct DuplicateIDConsumerTests {
    private let now = DuplicateIDFixture.now

    // MARK: - DashboardBuilder

    @Test(arguments: DuplicateIDFixture.Kind.allCases)
    func dashboardBuilderSurvivesARepeatedID(_ kind: DuplicateIDFixture.Kind) {
        let snapshot = DuplicateIDFixture.snapshot(duplicating: kind)
        let dashboard = DashboardBuilder.build(from: snapshot, digest: nil, digestAsOf: nil, now: now)
        #expect(!dashboard.nextUp.isEmpty)
        #expect(dashboard.weekAhead.count == 7)
    }

    @Test func dashboardBuilderSurvivesEveryRepeatedIDAtOnce() {
        let snapshot = DuplicateIDFixture.snapshot(duplicating: DuplicateIDFixture.Kind.allCases)
        let dashboard = DashboardBuilder.build(from: snapshot, digest: .empty, digestAsOf: now, now: now)
        #expect(!dashboard.nextUp.isEmpty)
    }

    /// First occurrence wins: the repeated Biology course (code "BIO REPEAT") comes after the
    /// original in `courses`, so every Biology row keeps the original's course code.
    @Test func dashboardBuilderKeepsTheFirstOfARepeatedCourse() {
        let dashboard = DashboardBuilder.build(from: DuplicateIDFixture.snapshot(duplicating: .course),
                                               digest: nil, digestAsOf: nil, now: now)
        let codes = Set(dashboard.nextUp.map(\.courseCode) + dashboard.dueSoon.compactMap(\.courseCode))
        #expect(codes.contains("BIO 101"))
        #expect(!codes.contains("BIO REPEAT"))
    }

    /// First occurrence wins inside one course, where the order is fixed (groups in order, then
    /// assignments in order): the original "Lab report 3" title, not the repeat's.
    @Test(arguments: [DuplicateIDFixture.Kind.assignmentWithinGroup, .assignmentAcrossGroups, .assignmentGroup])
    func dashboardBuilderKeepsTheFirstOfARepeatedAssignment(_ kind: DuplicateIDFixture.Kind) {
        let dashboard = DashboardBuilder.build(from: DuplicateIDFixture.snapshot(duplicating: kind),
                                               digest: nil, digestAsOf: nil, now: now)
        let titles = dashboard.nextUp.filter { $0.id == DuplicateIDFixture.repeatedAssignment }.map(\.title)
        #expect(!titles.isEmpty)
        #expect(titles.allSatisfy { $0 == "Lab report 3" })
    }

    /// "Next up" breaks a tie on score, due date and weight by course order. A repeated course
    /// keeps its first position: Biology (listed first, then repeated last) still ranks ahead of
    /// History for two otherwise identical items.
    @Test func dashboardBuilderRanksARepeatedCourseAtItsFirstPosition() {
        func course(_ id: CanvasID<Course>, _ code: String) -> Course {
            Course(id: id, name: code, courseCode: code, term: nil, teachers: [], timeZone: nil, appliesGroupWeights: false,
                   hasGradingPeriods: false, currentGradingPeriodID: nil, gradeVisibility: .visible,
                   scores: ComputedScores(currentScore: 85, finalScore: 85, currentGrade: nil, finalGrade: nil),
                   currentPeriodScores: nil, htmlURL: nil)
        }
        func group(_ id: CanvasID<AssignmentGroup>, _ assignment: CanvasID<Assignment>, in courseID: CanvasID<Course>) -> AssignmentGroup {
            AssignmentGroup(id: id, name: "G", position: 1, weight: nil, rules: DropRules(), assignments: [
                Assignment(id: assignment, courseID: courseID, groupID: id, name: assignment.rawValue,
                           dueAt: now.addingTimeInterval(2 * 86_400), lockAt: nil, pointsPossible: 10, gradingType: .points,
                           omitFromFinalGrade: false, htmlURL: nil, submission: nil),
            ])
        }
        let snapshot = CanvasSnapshot(
            generation: 1, accountKey: AccountKey("tie"), host: "h", fetchedAt: now,
            profile: UserProfile(id: "1", name: "S", shortName: nil, timeZone: nil, calendarFeedURL: nil),
            courses: [course("1", "BIO 101"), course("2", "HIS 210"), course("1", "BIO REPEAT")],
            groups: ["1": [group("11", "501", in: "1")], "2": [group("21", "502", in: "2")]],
            gradingPeriods: [:], planner: [], events: [], announcements: [], courseColors: [:], sections: [:])

        let nextUp = DashboardBuilder.build(from: snapshot, digest: nil, digestAsOf: nil, now: now).nextUp

        #expect(nextUp.map(\.id) == ["501", "502"])
    }

    // MARK: - ChangeDigest

    @Test(arguments: DuplicateIDFixture.Kind.allCases)
    func changeDigestSurvivesARepeatedIDInTheOlderTheNewerAndBothSnapshots(_ kind: DuplicateIDFixture.Kind) {
        let base = DuplicateIDFixture.base()
        let repeated = DuplicateIDFixture.snapshot(duplicating: kind)
        _ = ChangeDigest.diff(old: repeated, new: base)
        _ = ChangeDigest.diff(old: base, new: repeated)
        _ = ChangeDigest.diff(old: repeated, new: repeated)
    }

    /// The repeat of Biology scores 12 against the original's 88.5. Keeping the first occurrence
    /// of the older snapshot's courses means the unchanged Biology score is not reported as a
    /// 76.5-point move.
    @Test func changeDigestComparesAgainstTheFirstOfARepeatedOlderCourse() {
        let digest = ChangeDigest.diff(old: DuplicateIDFixture.snapshot(duplicating: .course), new: DuplicateIDFixture.base())
        #expect(digest.courseScoreChanges.isEmpty)
    }

    // MARK: - ReminderPlanner

    @Test(arguments: DuplicateIDFixture.Kind.allCases)
    func reminderPlannerSurvivesARepeatedID(_ kind: DuplicateIDFixture.Kind) {
        let snapshot = DuplicateIDFixture.snapshot(duplicating: kind)
        let candidates = DuplicateIDFixture.allAssignments(snapshot).map { ReminderCandidate(assignment: $0, priority: 70) }
        let plan = ReminderPlanner.plan(accountKey: snapshot.accountKey, candidates: candidates, settings: ReminderSettings(),
                                        now: now, timeZone: TimeZone(identifier: "America/New_York") ?? .current,
                                        refresh: RefreshRecord())
        #expect(!plan.isEmpty)
        #expect(plan.count <= TallyConfig.pendingNotificationCap)
    }

    // MARK: - GradeEngine, through its real callers

    @Test(arguments: DuplicateIDFixture.Kind.allCases)
    func gradeEngineWhatIfAndGoalSeekSurviveARepeatedID(_ kind: DuplicateIDFixture.Kind) {
        let snapshot = DuplicateIDFixture.snapshot(duplicating: kind)
        for course in snapshot.courses {
            let groups = snapshot.groups[course.id] ?? []
            let periods = snapshot.gradingPeriods[course.id] ?? []
            let scores = GradeEngine.scores(course: course, groups: groups, gradingPeriods: periods)
            #expect(scores.finalScore != nil)
            let input = GradeInput(course: course, groups: groups, gradingPeriods: periods)
            _ = WhatIfSimulator.scores(applying: [.init(assignmentID: DuplicateIDFixture.repeatedAssignment, score: 9)], to: input)
            _ = GoalSeek.solve(assignmentID: DuplicateIDFixture.repeatedAssignment, targetPercent: 90, in: input)
            _ = GradeEngine.currentGradingPeriod(in: periods, at: now)
        }
    }

    // MARK: - AlertEngine and PriorityScore

    @Test(arguments: DuplicateIDFixture.Kind.allCases)
    func alertEngineAndPriorityScoreSurviveARepeatedID(_ kind: DuplicateIDFixture.Kind) {
        let snapshot = DuplicateIDFixture.snapshot(duplicating: kind)
        var load: [AlertEngine.LoadItem] = []
        var schedule: [AlertEngine.ScheduleItem] = snapshot.events.map {
            AlertEngine.ScheduleItem(id: $0.id.rawValue, start: $0.startAt, end: $0.endAt)
        }
        var ranked: [PriorityScore.RankedItem] = []
        for course in snapshot.courses {
            let groups = snapshot.groups[course.id] ?? []
            let context = PriorityScore.WeightContext(course: course, groups: groups,
                                                      gradingPeriods: snapshot.gradingPeriods[course.id] ?? [])
            for assignment in groups.flatMap(\.assignments) {
                let weight = context.weight(of: assignment)
                #expect(weight == PriorityScore.weight(assignment: assignment, course: course, groups: groups,
                                                       gradingPeriods: snapshot.gradingPeriods[course.id] ?? []))
                let hours = assignment.dueAt.map { $0.timeIntervalSince(now) / 3_600 }
                let score = PriorityScore.score(hoursUntilDue: hours, courseWeight: weight)
                ranked.append(.init(assignmentID: assignment.id, score: score, dueAt: assignment.dueAt, weight: weight,
                                    courseOrder: 0))
                _ = AlertEngine.missingAlert(assignment: assignment, now: now)
                _ = AlertEngine.dueSoonAlert(assignment: assignment, priorityScore: score, weight: weight, now: now)
                if let due = assignment.dueAt {
                    load.append(.init(dueAt: due, weight: weight, courseID: course.id))
                    schedule.append(.init(id: assignment.id.rawValue, start: due))
                }
            }
        }
        _ = PriorityScore.sorted(ranked)
        _ = AlertEngine.overloadClusters(load, now: now)
        _ = AlertEngine.scheduleConflicts(schedule)
    }
}
