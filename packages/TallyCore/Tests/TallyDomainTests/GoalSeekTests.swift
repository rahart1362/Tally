import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

/// WP-A06. Uses the real synthetic fixtures so "weighted groups, drop rules
/// and grading periods" (per the brief) are all exercised against the
/// production `CourseMapper`/`AssignmentGroupMapper` output, not a hand-built
/// approximation.
@Suite("GoalSeek: minimum score to reach a target percentage")
struct GoalSeekTests {
    private func input(scenario name: String) throws -> GradeInput {
        let fixture = try GradeFixtures.scenario(name)
        return GradeInput(course: fixture.course, groups: fixture.groups, gradingPeriods: fixture.gradingPeriods)
    }

    /// An independent reference implementation: steps the what-if score up by
    /// `precision` from 0 and returns the first value that reaches `target`.
    /// `GoalSeek`'s bisection is checked against this rather than a
    /// hand-derived number, because the drop-rule bisection inside
    /// `GradeEngine` is not simple enough to hand-verify reliably once totals
    /// are as lopsided as the drop-lowest fixture's 1000-point item mixed
    /// with ~100-point ones (confirmed while writing this suite: "drop the
    /// lowest individual ratio" reasoning gives the wrong subset there).
    private func bruteForceMinimum(
        _ assignmentID: CanvasID<Assignment>, target: Double, in input: GradeInput, possible: Double,
        precision: Double = 0.01
    ) -> Double? {
        var score = 0.0
        while score <= possible + precision / 2 {
            let clamped = min(score, possible)
            let scores = WhatIfSimulator.scores(applying: [.init(assignmentID: assignmentID, score: clamped)], to: input)
            if let p = scores.currentScore, p >= target { return clamped }
            score += precision
        }
        return nil
    }

    private func assertMatchesBruteForce(
        _ assignmentID: CanvasID<Assignment>, target: Double, in input: GradeInput, possible: Double,
        precision: Double = 0.01
    ) {
        let want = bruteForceMinimum(assignmentID, target: target, in: input, possible: possible, precision: precision)
        let got = GoalSeek.solve(assignmentID: assignmentID, targetPercent: target, in: input, precision: precision)
        switch (want, got.outcome) {
        case let (w?, .reachable(minimumScore: g)):
            #expect(abs(w - g) <= precision * 1.5, "target \(target): brute force \(w), goal seek \(g)")
        case (nil, .impossible):
            break
        default:
            Issue.record("target \(target): brute force \(String(describing: want)), goal seek \(got.outcome)")
        }
    }

    // MARK: - weighted-groups (percent weighting, no drop rules)

    @Test(arguments: [50.0, 66.08, 90.0, 91.0])
    func weightedGroupsFinalExamMatchesBruteForce(_ target: Double) throws {
        let course = try input(scenario: "weighted-groups")
        assertMatchesBruteForce("1290006", target: target, in: course, possible: 100)
    }

    @Test func weightedGroupsUnreachableBeyondTheCeiling() throws {
        let course = try input(scenario: "weighted-groups")
        let got = GoalSeek.solve(assignmentID: "1290006", targetPercent: 92, in: course)
        #expect(got.outcome == .impossible(.unreachableEvenAtMaxScore))
    }

    @Test func alreadyMetAtZeroReturnsZero() throws {
        let course = try input(scenario: "weighted-groups")
        let got = GoalSeek.solve(assignmentID: "1290006", targetPercent: 10, in: course)
        #expect(got.outcome == .reachable(minimumScore: 0))
    }

    // MARK: - drop-lowest (points weighting; a 1000-point unsubmitted item vs ~100-point ones)

    @Test(arguments: [50.0, 70.0, 75.0])
    func dropLowestHandlesTheDroppedAssignmentChanging(_ target: Double) throws {
        let course = try input(scenario: "drop-lowest")
        assertMatchesBruteForce("1290004", target: target, in: course, possible: 1000, precision: 2)
    }

    /// A rising what-if score on the dropped-rule-affected item must never
    /// lower the grade (monotonicity is what makes bisection valid here).
    @Test func dropLowestScoreIsMonotonic() throws {
        let course = try input(scenario: "drop-lowest")
        var previous = -Double.infinity
        for score in stride(from: 0.0, through: 1000.0, by: 25.0) {
            let scores = WhatIfSimulator.scores(applying: [.init(assignmentID: "1290004", score: score)], to: course)
            let percent = try #require(scores.currentScore)
            #expect(percent >= previous - 1e-9, "score \(score): \(percent) < previous \(previous)")
            previous = percent
        }
    }

    // MARK: - never-drop

    @Test func neverDropItemIsAlwaysReachable() throws {
        let course = try input(scenario: "never-drop")
        let got = GoalSeek.solve(assignmentID: "1290000", targetPercent: 1, in: course)
        guard case .reachable = got.outcome else {
            Issue.record("never_drop item should be reachable, got \(got.outcome)")
            return
        }
    }

    @Test func neverDropMatchesBruteForce() throws {
        let course = try input(scenario: "never-drop")
        assertMatchesBruteForce("1290000", target: 80, in: course, possible: 10, precision: 0.5)
    }

    // MARK: - weighted grading periods (grading-periods persona)

    @Test func weightedGradingPeriodsGoalSeekIsSelfConsistent() throws {
        let courses = try GradeFixtures.courses(persona: "grading-periods")
        let algebra = try #require(courses.first { $0.course.id.rawValue == "90411" })
        #expect(algebra.course.hasWeightedGradingPeriods)
        let course = GradeInput(course: algebra.course, groups: algebra.groups, gradingPeriods: algebra.gradingPeriods)

        // "Unit 2 Test" (3400123): unsubmitted, filed under Quarter 1 (period 2201).
        let unitTest = CanvasID<Assignment>("3400123")
        let target = 85.0
        let got = GoalSeek.solve(assignmentID: unitTest, targetPercent: target, in: course)
        guard case .reachable(let minimum) = got.outcome else {
            Issue.record("expected a reachable score, got \(got.outcome)")
            return
        }
        let met = WhatIfSimulator.scores(applying: [.init(assignmentID: unitTest, score: minimum)], to: course)
        #expect(met.currentScore! >= target - 0.01)
        if minimum > 0 {
            let justBelow = WhatIfSimulator.scores(
                applying: [.init(assignmentID: unitTest, score: max(0, minimum - 0.5))], to: course)
            #expect((justBelow.currentScore ?? -1) < target)
        }
    }

    // MARK: - exclusion reasons (hand-built; no fixture needed)

    @Test func assignmentNotFoundIsReported() throws {
        let course = try input(scenario: "weighted-groups")
        #expect(GoalSeek.solve(assignmentID: "does-not-exist", targetPercent: 50, in: course).outcome
            == .impossible(.assignmentNotFound))
    }

    @Test func zeroPointAssignmentIsImpossible() {
        let input = GradeInput(
            weighting: .points, groups: [.init(id: "g1", weight: 100)],
            items: [.init(id: "a1", groupID: "g1", pointsPossible: 0, submission: nil)])
        #expect(GoalSeek.solve(assignmentID: "a1", targetPercent: 50, in: input).outcome
            == .impossible(.noPointsPossible))
    }

    @Test func nilPointsPossibleIsImpossible() {
        let input = GradeInput(
            weighting: .points, groups: [.init(id: "g1", weight: 100)],
            items: [.init(id: "a1", groupID: "g1", pointsPossible: nil, submission: nil)])
        #expect(GoalSeek.solve(assignmentID: "a1", targetPercent: 50, in: input).outcome
            == .impossible(.noPointsPossible))
    }

    @Test func omittedAssignmentIsImpossible() {
        let input = GradeInput(
            weighting: .points, groups: [.init(id: "g1", weight: 100)],
            items: [.init(id: "a1", groupID: "g1", pointsPossible: 100, omitFromFinalGrade: true, submission: nil)])
        #expect(GoalSeek.solve(assignmentID: "a1", targetPercent: 50, in: input).outcome
            == .impossible(.assignmentExcludedFromGrade))
    }

    @Test func unpublishedAssignmentIsImpossible() {
        let input = GradeInput(
            weighting: .points, groups: [.init(id: "g1", weight: 100)],
            items: [.init(id: "a1", groupID: "g1", pointsPossible: 100, published: false, submission: nil)])
        #expect(GoalSeek.solve(assignmentID: "a1", targetPercent: 50, in: input).outcome
            == .impossible(.assignmentExcludedFromGrade))
    }

    @Test func notGradeableAssignmentIsImpossible() {
        let input = GradeInput(
            weighting: .points, groups: [.init(id: "g1", weight: 100)],
            items: [.init(id: "a1", groupID: "g1", pointsPossible: 100, isGradeable: false, submission: nil)])
        #expect(GoalSeek.solve(assignmentID: "a1", targetPercent: 50, in: input).outcome
            == .impossible(.assignmentExcludedFromGrade))
    }
}
