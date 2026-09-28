import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

/// R-5 (resilience.md): every loop whose trip count depends on external magnitudes has an explicit,
/// named cap, and on reaching it returns its best bound so far, never a trap. `.timeLimit` cannot
/// interrupt synchronous code, so a loop that runs away is a hung process, not a failed test.
/// - `GoalSeek.nudge`, capped at `GoalSeek.maxNudgeSteps`, returns the bisection's `high`, which
///   reaches the target by construction.
/// - `DropRuleSelection`'s bisection, capped at `DropRuleSelection.maxBisectionSteps`, returns
///   big_f's set at the last midpoint it reached.
@Suite("Loops with a magnitude-dependent trip count stop at a named cap (R-5)", .timeLimit(.minutes(1)))
struct BoundedLoopTests {
    // MARK: - GoalSeek.nudge

    /// A step that always moves, towards a target that is never met: 1,000 steps of 0.001 would be
    /// needed to reach `possible`; the cap stops it and returns the fallback.
    @Test func aNudgeThatNeverMeetsTheTargetStopsAtTheCap() {
        let (score, steps) = GoalSeek.nudge(from: 0, by: 0.001, upTo: 1, orElse: 0.75) { _ in true }
        #expect(steps == GoalSeek.maxNudgeSteps)
        #expect(score == 0.75)
    }

    /// CS-07's stall: past about 1.4e14, adding 0.01 changes nothing. The progress guard stops it
    /// at the first step, long before the cap.
    @Test func aNudgeThatCannotMoveStopsAtOnce() {
        let (score, steps) = GoalSeek.nudge(from: 480_406_972_144_314.06, by: 0.01, upTo: 1e15, orElse: 7) { _ in true }
        #expect(steps == 1)
        #expect(score == 7)
    }

    /// The loop's own exit: stop once the target is met.
    @Test func aNudgeStopsWhereTheTargetIsMet() {
        let (score, steps) = GoalSeek.nudge(from: 89.97, by: 0.01, upTo: 100, orElse: 100) { $0 < 89.995 }
        #expect(steps == 3)
        #expect(abs(score - 90) < 1e-9)
    }

    // MARK: - DropRuleSelection's bisection

    private typealias Candidate = DropRuleSelection.Candidate

    private func candidates(_ input: GradeInput) -> [Candidate] {
        input.items.map { item in
            Candidate(assignmentID: item.id, score: GradeSanitizing.saneScore(item.submission?.score) ?? 0,
                      total: GradeSanitizing.sanePoints(item.pointsPossible) ?? 0)
        }
    }

    /// Inside the bounds the cap never binds, so it changes no result: the most steps any bounded
    /// worst case takes stays well under it (533 is the n = 50 bound).
    @Test(arguments: BoundedGradeWorstCase.allCases)
    func theBisectionCapNeverBindsInsideTheBounds(_ shape: BoundedGradeWorstCase) {
        let (_, steps) = DropRuleSelection.keptIndicesCountingSteps(candidates(shape.input), rules: DropRules(dropLowest: 1, dropHighest: 1))
        #expect(steps > 300, "\(shape): \(steps) steps; the shape is meant to need hundreds")
        #expect(steps <= 533, "\(shape): \(steps) steps, past the n = 50 bound")
        #expect(steps < DropRuleSelection.maxBisectionSteps)
    }

    /// Input that bypasses `GradeSanitizing` (1e100 over 1e-10) needs more steps than the cap
    /// (about 1,030): the bisection stops at the cap and returns a well-formed selection.
    @Test func aBisectionPastTheBoundsStopsAtTheCap() {
        let items = [(0.0, 1e100), (1e100, 1e-10), (-1e100, 1e-10), (3, 10), (7, 10)].enumerated().map {
            Candidate(assignmentID: CanvasID("x\($0.offset)"), score: $0.element.0, total: $0.element.1)
        }
        let (kept, steps) = DropRuleSelection.keptIndicesCountingSteps(items, rules: DropRules(dropLowest: 1, dropHighest: 1))
        #expect(steps == DropRuleSelection.maxBisectionSteps)
        #expect(kept.count == 3)
        #expect(Set(kept).count == 3 && kept.allSatisfy(items.indices.contains))
    }

    /// With the cap lowered to 8, the result is big_f's set at the eighth midpoint: a well-formed
    /// selection of the right size, the same every time.
    @Test func aCappedBisectionReturnsItsBestEstimate() {
        let items = candidates(BoundedGradeWorstCase.f5Shape.input)
        let rules = DropRules(dropLowest: 1, dropHighest: 1)
        let (kept, steps) = DropRuleSelection.keptIndicesCountingSteps(items, rules: rules, maxBisectionSteps: 8)
        #expect(steps == 8)
        #expect(kept.count == items.count - 2)
        #expect(Set(kept).count == kept.count)
        #expect(DropRuleSelection.keptIndicesCountingSteps(items, rules: rules, maxBisectionSteps: 8).kept == kept)
    }
}
