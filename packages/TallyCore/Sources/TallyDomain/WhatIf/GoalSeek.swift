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
        solveCountingNudges(assignmentID: assignmentID, targetPercent: targetPercent, in: input, branch: branch,
                            precision: precision).result
    }

    /// R-5 (resilience.md): the bisection's fixed number of halvings of `0...pointsPossible`.
    static let bisectionSteps = 60

    /// R-5 (resilience.md): the most nudges `solve` makes after its bisection, each one
    /// `GradeEngine` call. The bisection leaves `high` reaching the target, and the answer rounded
    /// up to `precision` sits at most an ulp below it, so `solve` makes zero or one nudge in
    /// practice. The loop's own exits (the target met, or the progress guard) always come first;
    /// this cap ends it if neither ever does. It is there because `.timeLimit` cannot interrupt
    /// synchronous code: without the progress guard `GoalSeekTerminationTests` did not fail at its
    /// one-minute limit but hung until killed (CS-07 F-4; resilience.md §R-5).
    static let maxNudgeSteps = 64

    /// `solve`, and how many nudges its last step made. Internal, for tests: a stalled nudge must be
    /// ended by the progress guard, never by `maxNudgeSteps`.
    static func solveCountingNudges(
        assignmentID: CanvasID<Assignment>, targetPercent: Double, in input: GradeInput, branch: Branch, precision: Double
    ) -> (result: Result, nudges: Int) {
        guard let item = input.items.first(where: { $0.id == assignmentID }) else {
            return (Result(outcome: .impossible(.assignmentNotFound)), 0)
        }
        guard item.published, item.isGradeable, !item.omitFromFinalGrade else {
            return (Result(outcome: .impossible(.assignmentExcludedFromGrade)), 0)
        }
        guard let possible = item.pointsPossible, possible > 0 else {
            return (Result(outcome: .impossible(.noPointsPossible)), 0)
        }

        func percent(at score: Double) -> Double? {
            let scores = WhatIfSimulator.scores(
                applying: [.init(assignmentID: assignmentID, score: score)], to: input)
            return branch == .current ? scores.currentScore : scores.finalScore
        }

        // A course that hides totals, or has no counted work at all, has no
        // percentage to solve against.
        guard let atZero = percent(at: 0) else {
            return (Result(outcome: .impossible(.noPointsPossible)), 0)
        }
        if atZero >= targetPercent { return (Result(outcome: .reachable(minimumScore: 0)), 0) }
        guard let atMax = percent(at: possible), atMax >= targetPercent else {
            return (Result(outcome: .impossible(.unreachableEvenAtMaxScore)), 0)
        }

        var low = 0.0
        var high = possible
        for _ in 0..<bisectionSteps {
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
        let (score, nudges) = nudge(from: min((high * scale).rounded(.up) / scale, possible), by: precision, upTo: possible,
                                    orElse: high) { candidate in
            percent(at: candidate).map { $0 < targetPercent } ?? false
        }
        return (Result(outcome: .reachable(minimumScore: score)), nudges)
    }

    /// `solve`'s last step: steps `start` up by `precision` (never past `possible`) while
    /// `needsMore` says the target is not yet met, and returns where it stopped and how many
    /// steps it took. Pure, so tests can drive both of its exits that end on `fallback`:
    /// - the progress guard (CS-07): past about 1.4e14 points, `precision` (0.01) is below half an
    ///   ulp of the candidate, so a step changes nothing and the loop never ended; a negative
    ///   `precision` never ended either;
    /// - R-5's `maxNudgeSteps`, if a step always moves but the target is never met.
    /// `fallback` is the bisection's `high`, which reaches the target by construction.
    static func nudge(from start: Double, by precision: Double, upTo possible: Double, orElse fallback: Double,
                      needsMore: (Double) -> Bool) -> (score: Double, steps: Int) {
        var candidate = start
        var steps = 0
        while candidate < possible, needsMore(candidate) {
            guard steps < maxNudgeSteps else { return (fallback, steps) }
            let next = min(candidate + precision, possible)
            guard next > candidate else { return (fallback, steps + 1) }
            candidate = next
            steps += 1
        }
        return (candidate, steps)
    }
}
