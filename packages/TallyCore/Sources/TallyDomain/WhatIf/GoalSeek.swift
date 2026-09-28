import Foundation

/// WP-A06: "what score do I need on assignment X to reach Y%?" (UX review
/// §3.7.3 goal mode; Exam mode's "need-on-final" line, insights-at-a-glance
/// §5.4). Pure and synchronous, built entirely on `WhatIfSimulator` and the
/// verified `GradeEngine`, so it inherits Canvas-parity drop-rule and
/// grading-period behaviour instead of re-deriving it.
public enum GoalSeek {
    /// Which `GradeEngine` branch the goal is measured against.
    /// `.current` (graded work only) is what "What do I need on the Final for
    /// an A-?" means in the UX review: everything else keeps its real score,
    /// and only the target assignment is assumed graded.
    public enum Branch: Sendable, Equatable {
        case current
        case final
    }

    public struct Result: Sendable, Equatable {
        public enum Outcome: Sendable, Equatable {
            /// The minimum score in `0...pointsPossible` that reaches the
            /// target, rounded up to the caller's `precision` so the reported
            /// number always actually clears the goal.
            case reachable(minimumScore: Double)
            case impossible(Reason)
        }
        public enum Reason: Sendable, Equatable {
            /// No assignment with that ID in this course's input.
            case assignmentNotFound
            /// Unpublished, not gradeable (`not_graded`/`wiki_page`), or
            /// `omit_from_final_grade`: no score on this item can move the
            /// grade, because `GradeEngine` excludes it unconditionally.
            case assignmentExcludedFromGrade
            /// `pointsPossible` is nil or 0: "score out of X" is undefined.
            case noPointsPossible
            /// Even a perfect score does not reach the target. Canvas's own
            /// drop-lowest/highest rules are re-evaluated by `GradeEngine` at
            /// every candidate score (a rising score can change which
            /// assignment a drop rule removes instead), so this reflects the
            /// true achievable ceiling, not a naive per-item estimate.
            case unreachableEvenAtMaxScore
        }
        public let outcome: Outcome
    }

    /// Solves for the minimum score on `assignmentID` that brings `input`'s
    /// `branch` percentage to at least `targetPercent`. Every other item keeps
    /// its real (or already-what-if'd) value.
    ///
    /// Precondition assumed, not independently re-derived: raising one item's
    /// score can only weakly raise the course's optimal drop-rule total
    /// (`GradeEngineDropRuleMonotonicityTests` checks this against the
    /// fixture courses used here). That monotonicity is what makes bisection
    /// valid; `GoalSeekTests` cross-checks every result against `GradeEngine`
    /// directly rather than an independent hand-derivation, since the
    /// drop-rule bisection is not simple enough to hand-verify reliably.
    public static func solve(
        assignmentID: CanvasID<Assignment>,
        targetPercent: Double,
        in input: GradeInput,
        branch: Branch = .current,
        precision: Double = 0.01
    ) -> Result {
        guard let item = input.items.first(where: { $0.id == assignmentID }) else {
            return Result(outcome: .impossible(.assignmentNotFound))
        }
        guard item.published, item.isGradeable, !item.omitFromFinalGrade else {
            return Result(outcome: .impossible(.assignmentExcludedFromGrade))
        }
        guard let possible = item.pointsPossible, possible > 0 else {
            return Result(outcome: .impossible(.noPointsPossible))
        }

        func percent(at score: Double) -> Double? {
            let scores = WhatIfSimulator.scores(
                applying: [.init(assignmentID: assignmentID, score: score)], to: input)
            return branch == .current ? scores.currentScore : scores.finalScore
        }

        // A course that hides totals, or has no counted work at all, has no
        // percentage to solve against.
        guard let atZero = percent(at: 0) else {
            return Result(outcome: .impossible(.noPointsPossible))
        }
        if atZero >= targetPercent { return Result(outcome: .reachable(minimumScore: 0)) }
        guard let atMax = percent(at: possible), atMax >= targetPercent else {
            return Result(outcome: .impossible(.unreachableEvenAtMaxScore))
        }

        var low = 0.0
        var high = possible
        for _ in 0..<60 {
            let mid = (low + high) / 2
            if let p = percent(at: mid), p >= targetPercent {
                high = mid
            } else {
                low = mid
            }
        }

        // Round UP to `precision` (Canvas's own rounding can otherwise nudge a
        // bisection-converged value just under the target), then nudge
        // upward in `precision` steps until the target is actually met.
        let scale = 1 / precision
        var candidate = min((high * scale).rounded(.up) / scale, possible)
        while candidate < possible, let p = percent(at: candidate), p < targetPercent {
            let next = min(candidate + precision, possible)
            // CS-07: past about 1.4e14 points, `precision` (0.01) is below half an ulp of
            // `candidate`, so adding it changes nothing and this loop never ended; a negative
            // `precision` never ended either. `high` reaches the target by construction.
            guard next > candidate else {
                candidate = high
                break
            }
            candidate = next
        }
        return Result(outcome: .reachable(minimumScore: candidate))
    }
}
