import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

/// WP-A06. Hand-built two-group, percent-weighted course (one group carries a
/// drop rule so overlay + drop-rule interaction is covered without needing a
/// fixture load); `GoalSeekTests` exercises the real fixture courses
/// (weighted groups, drop rules, weighted grading periods) end to end.
@Suite("WhatIfSimulator: hypothetical scores overlay without mutation")
struct WhatIfSimulatorTests {
    private func course(dropLowest: Int = 0, neverDrop: [CanvasID<Assignment>] = []) -> GradeInput {
        GradeInput(
            weighting: .percent,
            groups: [
                .init(id: "g1", weight: 60, rules: DropRules(dropLowest: dropLowest, neverDrop: neverDrop)),
                .init(id: "g2", weight: 40),
            ],
            items: [
                .init(id: "a1", groupID: "g1", pointsPossible: 100,
                      submission: .init(id: "s1", score: 80, posted: true, workflowState: "graded")),
                .init(id: "a2", groupID: "g1", pointsPossible: 100,
                      submission: .init(id: "s2", score: 60, posted: true, workflowState: "graded")),
                .init(id: "a3", groupID: "g1", pointsPossible: 50, submission: nil),
                .init(id: "a4", groupID: "g2", pointsPossible: 100,
                      submission: .init(id: "s4", score: 90, posted: true, workflowState: "graded")),
            ])
    }

    @Test func emptyOverrideIsExactlyTheCurrentGrade() {
        let input = course()
        let base = GradeEngine.scores(for: input)
        let overlaid = WhatIfSimulator.scores(applying: [], to: input)
        #expect(overlaid.currentScore == base.currentScore)
        #expect(overlaid.finalScore == base.finalScore)
        #expect(WhatIfSimulator.apply([], to: input) == input)
    }

    @Test func reGradingAnItemWithItsOwnRealScoreIsIdentity() {
        let input = course()
        let base = GradeEngine.scores(for: input)
        let overlaid = WhatIfSimulator.scores(applying: [.init(assignmentID: "a1", score: 80)], to: input)
        #expect(overlaid.currentScore == base.currentScore)
        #expect(overlaid.finalScore == base.finalScore)
    }

    @Test func overridingAnUngradedItemMovesBothBranches() {
        let input = course()
        let before = GradeEngine.scores(for: input)
        let after = WhatIfSimulator.scores(applying: [.init(assignmentID: "a3", score: 45)], to: input)
        // a3 was excluded from "current" before (ungraded); the what-if now counts it.
        #expect(before.currentScore != after.currentScore)
        // a3 already counted as 0 in "final" (ungraded counts as zero there), so a
        // 45/50 what-if score must raise "final" too.
        #expect(after.finalScore! > before.finalScore!)
    }

    @Test func overlayNeverMutatesTheOriginalInput() {
        let input = course()
        let untouched = input
        _ = WhatIfSimulator.apply([.init(assignmentID: "a1", score: 0)], to: input)
        #expect(input == untouched)
    }

    @Test func overlayNeverMutatesTheOriginalSnapshotShapedInput() throws {
        // Build from the real course->GradeInput path (Model layer), not the
        // hand-built DSL, to cover the `GradeInput(course:groups:gradingPeriods:)`
        // convenience initializer the app actually calls.
        let fixture = try GradeFixtures.scenario("weighted-groups")
        let input = GradeInput(course: fixture.course, groups: fixture.groups, gradingPeriods: fixture.gradingPeriods)
        let before = input
        _ = WhatIfSimulator.scores(applying: [.init(assignmentID: "1290006", score: 10)], to: input)
        #expect(input == before)
    }

    /// A rising what-if score must never lower the grade, even when it changes
    /// *which* assignment a drop-lowest rule removes (WP-A06: "handle dropped
    /// assignments correctly").
    @Test func dropRulesAreReEvaluatedUnderTheOverlay() {
        let input = course(dropLowest: 1)
        let low = WhatIfSimulator.scores(applying: [.init(assignmentID: "a3", score: 5)], to: input)
        let high = WhatIfSimulator.scores(applying: [.init(assignmentID: "a3", score: 50)], to: input)
        #expect(high.currentScore! > low.currentScore!, "a higher what-if score must not lower the grade")
    }

    @Test func neverDropOverlayItemStillCannotBeDropped() {
        // a2 is never_drop; even a rock-bottom what-if score keeps it counted,
        // so the group score reflects it rather than silently excluding it.
        let input = course(dropLowest: 1, neverDrop: ["a2"])
        let scores = WhatIfSimulator.scores(applying: [.init(assignmentID: "a2", score: 0)], to: input)
        // g1 kept set is exactly {a1, a2} (a3 has no submission and is excluded
        // from "current" regardless): (80+0)/200 = 40%, weighted 60 -> 24;
        // g2 is 90%, weighted 40 -> 36. Total 60%, fullWeight 100.
        #expect(scores.currentScore == 60.0)
    }
}
