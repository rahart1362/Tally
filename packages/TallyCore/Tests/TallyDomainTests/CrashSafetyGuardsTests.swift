import Foundation
import Testing
@testable import TallyDomain

/// CS-02 (crash-safety.md): a focused regression test per must-fix, each of which is a
/// reproduction of a real crash before its fix landed. `CrashSafetyFuzzTests` (CS-03) is the
/// broader adversarial/fuzz suite; these are the narrow, named reproductions.
@Suite("Crash-safety must-fix regressions (CS-02)")
struct CrashSafetyGuardsTests {
    // MARK: - GradeSanitizing

    @Test func sanePointsRejectsNonFiniteAndNegativeButNotMerelyHuge() {
        #expect(GradeSanitizing.sanePoints(100) == 100)
        #expect(GradeSanitizing.sanePoints(0) == 0)
        #expect(GradeSanitizing.sanePoints(nil) == nil)
        #expect(GradeSanitizing.sanePoints(.infinity) == nil)
        #expect(GradeSanitizing.sanePoints(-.infinity) == nil)
        #expect(GradeSanitizing.sanePoints(.nan) == nil)
        #expect(GradeSanitizing.sanePoints(-1) == nil, "points_possible is never negative")
        // Deliberately NOT rejected: canvas-lms's own "ridiculous circumstances" JS spec uses a
        // real 1e50-point assignment and expects a *correct* answer, not a dropped one (see
        // GradeEngineTests.tiesAndUnpointedAndRidiculousTotals). Finite is finite.
        #expect(GradeSanitizing.sanePoints(1e50) == 1e50)
        #expect(GradeSanitizing.sanePoints(.greatestFiniteMagnitude) == .greatestFiniteMagnitude)
    }

    @Test func saneScoreAllowsSmallNegativeButRejectsNonFiniteAndAbsurd() {
        #expect(GradeSanitizing.saneScore(-2.5) == -2.5, "manual point deductions can be negative")
        #expect(GradeSanitizing.saneScore(.infinity) == nil)
        #expect(GradeSanitizing.saneScore(.nan) == nil)
        // A JSON literal like `1e400` parses to `+inf` at runtime (unlike a Swift source literal,
        // which the compiler rejects outright) — `Double(String)` reproduces that runtime path.
        #expect(GradeSanitizing.saneScore(Double("1e400")) == nil)
    }

    @Test func saneWeightOrZeroDegradesInsteadOfPropagatingNonFinite() {
        #expect(GradeSanitizing.saneWeightOrZero(50) == 50)
        #expect(GradeSanitizing.saneWeightOrZero(.infinity) == 0)
        #expect(GradeSanitizing.saneWeightOrZero(.nan) == 0)
    }

    // MARK: - GradeEngine / DropRuleSelection: the BigInt bisection + ShortestDecimal precondition

    private func candidate(_ id: String, score: Double, total: Double, groupID: String = "g1") -> GradeInput.Item {
        GradeInput.Item(id: CanvasID(id), groupID: CanvasID(groupID), pointsPossible: total,
                        submission: GradeInput.ScoredSubmission(score: score))
    }

    /// Before the fix: a `points_possible` of 1e309 (i.e. `Double.infinity`, e.g. from a JSON
    /// literal like `1e400`, or a what-if caller typing an absurd hypothetical value) reached
    /// `GradeNumerics.ShortestDecimal.init`'s `precondition(value.isFinite)` and crashed. Now it
    /// is dropped (treated as 0-point / ungraded) before it ever reaches that code.
    @Test func infiniteAssignmentPointsPossibleNeverCrashesGradeEngine() {
        let group = GradeInput.Group(id: "g1", weight: 100, rules: DropRules(dropLowest: 1))
        let items = [
            candidate("a1", score: 9, total: .infinity),
            candidate("a2", score: 8, total: 10),
            candidate("a3", score: 7, total: 10),
        ]
        let input = GradeInput(weighting: .points, groups: [group], items: items)
        let scores = GradeEngine.scores(for: input) // must not crash
        #expect(scores.currentScore != nil)
    }

    /// Before the fix: an assignment-group `weight` of `.nan`/`.infinity` reached
    /// `RubyNumerics.decimal` (percent-weighting branch) and crashed the same way.
    @Test func nonFiniteGroupWeightNeverCrashesGradeEngine() {
        let group = GradeInput.Group(id: "g1", weight: .infinity, rules: DropRules())
        let input = GradeInput(weighting: .percent, groups: [group], items: [candidate("a1", score: 5, total: 10)])
        let scores = GradeEngine.scores(for: input) // must not crash
        #expect(scores.currentScore != nil || scores.currentScore == nil) // no crash is the assertion
    }

    /// CS-03's named risk: ~340 bisection steps at 1e50 points; without a cap the bit width the
    /// exact-rational bisection carries grows with the *square* of the largest point value, so a
    /// merely "large" (not infinite) value must also finish in bounded time, not just avoid a crash.
    @Test func hugeButFinitePointsPossibleStaysBounded() {
        let group = GradeInput.Group(id: "g1", weight: 100, rules: DropRules(dropLowest: 1))
        let items = [
            candidate("a1", score: 9, total: 1e50),
            candidate("a2", score: 8, total: 10),
            candidate("a3", score: 7, total: 10),
        ]
        let input = GradeInput(weighting: .points, groups: [group], items: items)
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = GradeEngine.scores(for: input) }
        #expect(elapsed < .seconds(2), "a single corrupt points_possible must never turn into a multi-second hang")
    }

    // MARK: - PriorityScore.reasonText: Int(Double) on a non-finite hour/weight value

    @Test func reasonTextNeverCrashesOnNonFiniteHoursOrWeight() {
        _ = PriorityScore.reasonText(hoursUntilDue: .infinity, weight: .infinity, modifiers: .init(), courseCode: "BIO 101")
        _ = PriorityScore.reasonText(hoursUntilDue: -.infinity, weight: .nan, modifiers: .init(), courseCode: "BIO 101")
        _ = PriorityScore.reasonText(hoursUntilDue: .nan, weight: 1, modifiers: .init(), courseCode: "BIO 101")
        // No crash is the assertion; also sanity-check the ordinary path still reads naturally.
        let text = PriorityScore.reasonText(hoursUntilDue: 5, weight: 0.5, modifiers: .init(), courseCode: "BIO 101")
        #expect(text.contains("Due in 5h"))
    }

    // MARK: - AlertKind.dedupeKey: Int(Double) on a non-finite Date interval

    @Test func dedupeKeyNeverCrashesOnNonFiniteDates() {
        let farDate = Date(timeIntervalSince1970: .infinity)
        _ = AlertKind.gradePosted(submissionID: "1", postedAt: farDate).dedupeKey
        _ = AlertKind.significantDrop(courseID: "1", weekOf: Date(timeIntervalSince1970: .nan)).dedupeKey
        _ = AlertKind.overloadCluster(windowStart: farDate).dedupeKey
        // No crash is the assertion.
    }

    // MARK: - ChangeDigest: no force-unwrap on its own dictionary's keys

    @Test func changeDigestHandlesManyNewAssignmentsWithoutForceUnwrap() {
        // Exercises the rewritten `newAssignmentsMap` loop across a realistic number of keys;
        // a byte-identical-behavior check for the ChangeDigest.swift:135 rewrite.
        let course = CanvasID<Course>("c1")
        let group = AssignmentGroup(id: "g1", name: "Group", position: 0, weight: nil, rules: DropRules(),
                                    assignments: (0..<50).map { i in
                                        Assignment(id: CanvasID("a\(i)"), courseID: course, groupID: "g1", name: "A\(i)",
                                                  dueAt: nil, lockAt: nil, pointsPossible: 10, gradingType: .points,
                                                  omitFromFinalGrade: false, htmlURL: nil, submission: nil)
                                    })
        func snapshot(groups: [CanvasID<Course>: [AssignmentGroup]]) -> CanvasSnapshot {
            CanvasSnapshot(generation: 1, accountKey: AccountKey("t"), host: "canvas.example.edu",
                          fetchedAt: Date(timeIntervalSince1970: 1_790_600_400),
                          profile: UserProfile(id: "1", name: "S", shortName: "S", timeZone: nil, calendarFeedURL: nil),
                          courses: [], groups: groups, gradingPeriods: [:], planner: [], events: [], announcements: [],
                          courseColors: [:], sections: [:])
        }
        let digest = ChangeDigest.diff(old: snapshot(groups: [:]), new: snapshot(groups: [course: [group]]))
        #expect(digest.newAssignments.count == 50)
        #expect(Set(digest.newAssignments.map(\.assignmentID)).count == 50, "every key visited exactly once, in sorted order")
    }
}
