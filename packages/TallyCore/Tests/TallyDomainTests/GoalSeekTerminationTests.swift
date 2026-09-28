import Foundation
import Testing
@testable import TallyDomain

/// CS-07 (crash-safety-2.md, CS7-4): `GoalSeek.solve` always returns. Its last step nudges the
/// rounded answer up by `precision` until the target is met. Past about 1.4e14 points, 0.01 is
/// below half an ulp of the candidate, so `candidate + precision == candidate`: when the rounded
/// candidate landed one ulp under the target, the loop spun forever. The seeded pipeline fuzz
/// found it; before the fix, `points_possible` 480406972144315 never returned (a runner under
/// `timeout 60` was killed, exit 124), while 100 points returned in 6 ms.
@Suite("GoalSeek always returns, whatever the magnitude (CS-07)", .timeLimit(.minutes(1)))
struct GoalSeekTerminationTests {
    private func input(points: Double) -> GradeInput {
        GradeInput(weighting: .points, groups: [.init(id: "g1", weight: 100)], items: [
            .init(id: "target", groupID: "g1", pointsPossible: points, submission: nil),
            .init(id: "other", groupID: "g1", pointsPossible: 10, submission: .init(score: 10)),
        ])
    }

    private func percent(_ score: Double, _ input: GradeInput) -> Double? {
        WhatIfSimulator.scores(applying: [.init(assignmentID: "target", score: score)], to: input).currentScore
    }

    /// The first two stalled before the fix; the rest are other magnitudes where 0.01 is below one ulp.
    @Test(arguments: [480_406_972_144_315.0, 480_406_972_144_314.06, 1e15, 7.3e16, 1e20, 3.3e25, 1e50])
    func aHugePointsPossibleStillReturnsAScoreThatReachesTheTarget(_ points: Double) {
        let input = input(points: points)
        let result = GoalSeek.solve(assignmentID: "target", targetPercent: 90, in: input)
        guard case .reachable(let minimum) = result.outcome else {
            Issue.record("expected a reachable score, got \(result)")
            return
        }
        #expect(minimum <= points)
        #expect((percent(minimum, input) ?? 0) >= 90, "the reported score really reaches the target")
    }

    /// A non-positive `precision` is a caller's mistake, not data, but it spun the same loop
    /// (each step moved the candidate down, never up).
    @Test(arguments: [-0.01, -1.0])
    func aNegativePrecisionStillReturns(_ precision: Double) {
        let input = input(points: 100)
        let result = GoalSeek.solve(assignmentID: "target", targetPercent: 90, in: input, precision: precision)
        guard case .reachable(let minimum) = result.outcome else {
            Issue.record("expected a reachable score, got \(result)")
            return
        }
        #expect((percent(minimum, input) ?? 0) >= 90)
    }

    /// Ordinary magnitudes are unchanged: the answer is still rounded up to `precision`.
    @Test func ordinaryMagnitudesKeepTheirRoundedAnswer() {
        let result = GoalSeek.solve(assignmentID: "target", targetPercent: 90, in: input(points: 100))
        #expect(result.outcome == .reachable(minimumScore: 89))
    }
}
