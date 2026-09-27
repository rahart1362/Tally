import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

/// The key check (architecture 3.3, fixtures/canvas/README.md "Grades"): computed only
/// from the client's responses (courses, assignment_groups, grading_periods) through the
/// production mappers, every course score matches expected/grades within the file's
/// tolerance. As a stricter self-check (like tools/canvas-synth/tests/test_fixture_parity.py)
/// the largest deviation must be exactly 0.
@Suite("GradeEngine parity with expected/grades")
struct GradeParityTests {
    /// Canvas withholds unposted scores from the student (`score` and `posted_at` are null),
    /// so these expected `unposted_*` values, which the generator took from its own model,
    /// cannot be computed from the fixture responses. gradecalc.py's own client path
    /// (`course_input_from_api`) gives the same values as this engine. Reported to the PMO;
    /// `withKnownIssue` fails if the fixtures are regenerated so that they match.
    static let unpostedNotClientVisible: Set<String> = ["flagship/51847", "scenario/unposted-and-omitted"]

    @Test(arguments: Fixtures.personas)
    func everyPersonaCourseMatches(_ persona: String) throws {
        let expected = try GradeFixtures.expected(persona: persona)
        let fixtures = try GradeFixtures.courses(persona: persona)
        #expect(Set(fixtures.map(\.course.id.rawValue)) == Set(expected.courses.map(\.courseId)))
        var maxDelta = 0.0
        for want in expected.courses {
            let fixture = try #require(fixtures.first { $0.course.id.rawValue == want.courseId })
            maxDelta = max(maxDelta, check(fixture, want, tolerance: expected.tolerance, at: expected.capturedAt))
        }
        #expect(maxDelta == 0, "\(persona): largest deviation \(maxDelta)")
    }

    /// The grade scenarios in expected/grades/scenarios.json (checked below, so none is skipped).
    static let scenarios = [
        "concluded-course", "drop-highest", "drop-lowest", "excused", "hidden-final-grades", "large-ids",
        "late-and-missing", "letter-grades", "multiple-enrollments", "never-drop", "no-due-date", "pass-fail",
        "unposted-and-omitted", "unweighted-grading-periods", "unweighted-groups", "weighted-grading-periods",
        "weighted-groups",
    ]

    @Test func scenarioListCoversTheExpectedFile() throws {
        #expect(try GradeFixtures.expectedScenarios().scenarios.keys.sorted() == Self.scenarios)
    }

    @Test(arguments: GradeParityTests.scenarios)
    func everyGradeScenarioMatches(_ name: String) throws {
        let expected = try GradeFixtures.expectedScenarios()
        let want = try #require(expected.scenarios[name])
        let fixture = try GradeFixtures.scenario(name)
        #expect(fixture.course.id.rawValue == want.courseId)
        let maxDelta = check(fixture, want, tolerance: expected.tolerance, at: expected.capturedAt)
        #expect(maxDelta == 0, "\(name): largest deviation \(maxDelta)")
    }

    /// Returns the largest absolute deviation seen (excluding known issues).
    private func check(_ fixture: GradeFixtureCourse, _ want: ExpectedCourseGrades, tolerance: Double, at now: Date) -> Double {
        let label = fixture.label
        #expect(fixture.unmapped == 0, "\(label): mapper dropped items")
        let got = GradeEngine.scores(course: fixture.course, groups: fixture.groups, gradingPeriods: fixture.gradingPeriods)
        var maxDelta = 0.0
        func compare(_ field: String, _ value: Double?, _ target: Double?, track: Bool = true) {
            guard let value, let target else {
                #expect(value == target, "\(label) \(field): got \(String(describing: value)), want \(String(describing: target))")
                return
            }
            if track { maxDelta = max(maxDelta, abs(value - target)) }
            #expect(abs(value - target) <= tolerance, "\(label) \(field): got \(value), want \(target)")
        }

        compare("current_score", got.currentScore, want.currentScore)
        compare("final_score", got.finalScore, want.finalScore)
        #expect(got.usesWeightedGradingPeriods == want.weightedGradingPeriods, "\(label) weighted_grading_periods")
        if Self.unpostedNotClientVisible.contains(label) {
            // The client sees nothing more of unposted work than the student does.
            #expect(got.unpostedCurrentScore == got.currentScore && got.unpostedFinalScore == got.finalScore, "\(label)")
            withKnownIssue("\(label): expected unposted_* uses scores Canvas withholds from the student") {
                compare("unposted_current_score", got.unpostedCurrentScore, want.unpostedCurrentScore, track: false)
                compare("unposted_final_score", got.unpostedFinalScore, want.unpostedFinalScore, track: false)
            }
        } else {
            compare("unposted_current_score", got.unpostedCurrentScore, want.unpostedCurrentScore)
            compare("unposted_final_score", got.unpostedFinalScore, want.unpostedFinalScore)
        }

        #expect(got.gradingPeriods.map(\.periodID.rawValue) == want.gradingPeriods.map(\.id), "\(label) periods")
        for period in want.gradingPeriods {
            let scores = got.period(CanvasID(period.id))?.posted
            compare("period \(period.id) current_score", scores?.currentScore, period.currentScore)
            compare("period \(period.id) final_score", scores?.finalScore, period.finalScore)
        }
        #expect(GradeEngine.currentGradingPeriod(in: fixture.gradingPeriods, at: now)?.id.rawValue == want.currentGradingPeriodId,
                "\(label) current_grading_period_id")

        #expect(got.posted.currentGroups.map(\.groupID.rawValue) == want.assignmentGroups.map(\.id), "\(label) groups")
        for group in want.assignmentGroups {
            for (branch, wantBranch, gotGroups) in [("current", group.current, got.posted.currentGroups),
                                                    ("final", group.final, got.posted.finalGroups)] {
                guard let g = gotGroups.first(where: { $0.groupID.rawValue == group.id }) else { continue }
                let field = "group \(group.id) \(branch)"
                compare("\(field) score", RubyNumerics.double(g.score), wantBranch.score)
                compare("\(field) possible", RubyNumerics.double(g.possible), wantBranch.possible)
                compare("\(field) grade", g.grade, wantBranch.grade)
                #expect(g.droppedSubmissionIDs.map(\.rawValue) == wantBranch.droppedSubmissionIds, "\(label) \(field) dropped")
            }
        }
        return maxDelta
    }
}
