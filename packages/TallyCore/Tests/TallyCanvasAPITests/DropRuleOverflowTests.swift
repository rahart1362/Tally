import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyCanvasAPI

/// CS-07 (crash-safety-2.md, CS7-3): Canvas's `drop_lowest`/`drop_highest` are plain JSON
/// integers, and a value such as 9223372036854775807 decodes as `Int` without error. Two sites
/// added them with `+` and trapped on the overflow ("Arithmetic overflow", SIGILL):
/// `DropRuleSelection.keptIndices` (every grade computation) and
/// `PriorityScore.WeightContext.weight(of:)` (every Dashboard build). Both now behave exactly as
/// for any count that already covers the whole group.
@Suite("Drop-rule counts near Int.max never trap (CS-07)", .timeLimit(.minutes(TestTimeBudget.minutes(1))))
struct DropRuleOverflowTests {
    private func input(_ rules: DropRules) -> GradeInput {
        GradeInput(weighting: .points, groups: [GradeInput.Group(id: "g1", weight: 100, rules: rules)],
                   items: (1...4).map { i in
                       GradeInput.Item(id: CanvasID("a\(i)"), groupID: "g1", pointsPossible: 10,
                                       submission: GradeInput.ScoredSubmission(score: Double(i * 2)))
                   })
    }

    /// `dropLowest + dropHighest` overflowed. For any sum that reaches the group size, Canvas's rule
    /// (gradecalc.py `drop_assignments`) keeps `dropLowest` and ignores `dropHighest`.
    @Test func gradeEngineTreatsAnOverflowingDropHighestLikeOneThatCoversTheGroup() {
        let huge = GradeEngine.scores(for: input(DropRules(dropLowest: 1, dropHighest: .max)))
        let covering = GradeEngine.scores(for: input(DropRules(dropLowest: 1, dropHighest: 4)))
        #expect(huge == covering)
        #expect(huge.currentScore == covering.currentScore)
    }

    @Test func gradeEngineSurvivesEveryExtremeDropCountPair() {
        for (low, high) in [(Int.max, Int.max), (Int.max, 1), (1, Int.max), (Int.max - 1, 2), (Int.min, Int.max), (Int.max, Int.min)] {
            _ = GradeEngine.scores(for: input(DropRules(dropLowest: low, dropHighest: high)))
        }
    }

    /// `max(0, dropLowest) + max(0, dropHighest)` overflowed. A drop count that covers every
    /// droppable item weighs a droppable item at 0, however large the count.
    @Test func priorityWeightTreatsAnOverflowingDropCountLikeOneThatCoversTheGroup() {
        let course = Course(id: "c1", name: "N", courseCode: "N101", term: nil, teachers: [], timeZone: nil,
                            appliesGroupWeights: false, hasGradingPeriods: false, currentGradingPeriodID: nil,
                            gradeVisibility: .visible, scores: nil, currentPeriodScores: nil, htmlURL: nil)
        func group(_ rules: DropRules) -> AssignmentGroup {
            AssignmentGroup(id: "g1", name: "G", position: 1, weight: nil, rules: rules, assignments: (1...4).map { i in
                Assignment(id: CanvasID("a\(i)"), courseID: "c1", groupID: "g1", name: "A\(i)", dueAt: nil, lockAt: nil,
                           pointsPossible: 10, gradingType: .points, omitFromFinalGrade: false, htmlURL: nil, submission: nil)
            })
        }
        for rules in [DropRules(dropLowest: .max, dropHighest: 1), DropRules(dropLowest: .max, dropHighest: .max)] {
            let huge = group(rules)
            let covering = group(DropRules(dropLowest: 4))
            for (a, b) in zip(huge.assignments, covering.assignments) {
                let weight = PriorityScore.WeightContext(course: course, groups: [huge]).weight(of: a)
                #expect(weight == PriorityScore.WeightContext(course: course, groups: [covering]).weight(of: b))
                #expect(weight == PriorityScore.weight(assignment: a, course: course, groups: [huge]))
            }
        }
    }

    /// The same values arriving the way Canvas would send them, through the real mapper and the
    /// consumers that read drop rules.
    @Test func extremeDropCountsFromCanvasJSONReachEveryConsumerWithoutATrap() throws {
        let json = """
        [{"id": "g1", "name": "Homework", "position": 1, "group_weight": 100,
          "rules": {"drop_lowest": 9223372036854775807, "drop_highest": 9223372036854775807},
          "assignments": [
            {"id": "a1", "name": "One", "points_possible": 10, "due_at": "2026-10-01T12:00:00Z",
             "submission": {"score": 7, "posted_at": "2026-09-20T12:00:00Z", "workflow_state": "graded"}},
            {"id": "a2", "name": "Two", "points_possible": 10, "due_at": "2026-10-02T12:00:00Z"},
            {"id": "a3", "name": "Three", "points_possible": 10, "due_at": "2026-10-03T12:00:00Z"}]}]
        """
        let groups = try AssignmentGroupMapper.map(Data(json.utf8), courseID: "c1").items
        #expect(groups.first?.rules.dropLowest == .max)
        let course = Course(id: "c1", name: "N", courseCode: "N101", term: nil, teachers: [], timeZone: nil,
                            appliesGroupWeights: true, hasGradingPeriods: false, currentGradingPeriodID: nil,
                            gradeVisibility: .visible, scores: nil, currentPeriodScores: nil, htmlURL: nil)
        _ = GradeEngine.scores(course: course, groups: groups, gradingPeriods: [])
        let now = TestClock().now()
        let snapshot = CanvasSnapshot(
            generation: 1, accountKey: AccountKey("drop"), host: "h", fetchedAt: now,
            profile: UserProfile(id: "1", name: "S", shortName: nil, timeZone: nil, calendarFeedURL: nil),
            courses: [course], groups: ["c1": groups], gradingPeriods: [:], planner: [], events: [], announcements: [],
            courseColors: [:], sections: [:])
        #expect(!DashboardBuilder.build(from: snapshot, digest: nil, digestAsOf: nil, now: now).nextUp.isEmpty)
    }
}
