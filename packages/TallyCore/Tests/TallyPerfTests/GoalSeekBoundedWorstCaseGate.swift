// PERF-FIX-1 item 2 (perf1/report.md S4 opportunity 1; docs/pmo/05-perf-crash-charter.md R-2):
// a regression gate for `GoalSeek`'s worst case. The owner's rule is "measurement tests never
// gate required jobs" (pmo-perffix1-prompt.md item 2), so this lives in `TallyPerfTests`
// alongside `BoundedGradeGate.swift` -- both run only from `core-perf`/`core-perf-apple`
// (ci.yml), which are already non-blocking (`continue-on-error: true`), never a required job.
// An `extension CoreBenchmarks` for the same reason `BoundedGradeGate.swift` and
// `ScalingGateTests.swift` give: one suite identity keeps `.serialized` covering every
// timing-sensitive test here.
#if !DEBUG
import Foundation
import Testing
import TallyDomain
import TallyTestSupport

extension CoreBenchmarks {
    /// `WhatIfModel.swift:9` documents a 144-268 ms worst case for one `GoalSeek.solve` call, and
    /// `BoundedGradeGate.swift:16` ties it to ~62 `GradeEngine.scores` calls (60 bisection steps
    /// plus the `atZero`/`atMax` checks and at most one nudge). perf1/report.md S2.5 projects
    /// 154-681 ms for that many calls from this run's own `gradeEngineBoundedWorstCase` medians
    /// (S1.1), but found no `GoalSeek`-specific benchmark. This closes that gap: one end-to-end
    /// `GoalSeek.solve` call on each `BoundedGradeWorstCase` shape, so a future regression (a
    /// per-call cost creeping up, or an extra bisection step) is caught here instead of only
    /// showing up as a stutter in the What-If sheet.
    static let goalSeekBoundedWorstCaseCeilingMs = 600.0

    @Test("GoalSeek.solve on the bounded worst case stays under its ceiling", arguments: BoundedGradeWorstCase.allCases)
    func goalSeekBoundedWorstCaseCeiling(_ shape: BoundedGradeWorstCase) {
        let input = shape.input
        guard let item = input.items.first else {
            Issue.record("\(shape): BoundedGradeWorstCase.input has no items to seek against")
            return
        }
        guard let possible = item.pointsPossible, possible > 0 else {
            Issue.record("\(shape): item \(item.id) has no points possible, so there is nothing to bisect")
            return
        }
        // A target strictly between the current-score percentage and the max-score percentage
        // always lands in the bisection branch (GoalSeek.swift:110-119), the actual worst case --
        // a target at or outside either extreme short-circuits for free (GoalSeek.swift:102-108)
        // and would silently measure the cheap path instead of the one BoundedGradeGate.swift:16
        // bounds. Computed per shape, not hardcoded, because each shape's achievable range at
        // this item differs (scores up to 1e50, per BoundedGradeWorstCase's doc comment).
        let atZero = WhatIfSimulator.scores(applying: [.init(assignmentID: item.id, score: 0)], to: input).currentScore
        let atMax = WhatIfSimulator.scores(applying: [.init(assignmentID: item.id, score: possible)], to: input).currentScore
        guard let atZero, let atMax, atMax > atZero else {
            let detail = "\(shape): no percentage range to bisect (atZero \(atZero.debugDescription), atMax \(atMax.debugDescription))"
            Issue.record("\(detail)")
            return
        }
        let target = (atZero + atMax) / 2
        let result = Bench.time("ceiling/goalSeekBoundedWorstCase/\(shape)", iterations: 11, warmup: 2) {
            let outcome = GoalSeek.solve(assignmentID: item.id, targetPercent: target, in: input).outcome
            switch outcome {
            case .reachable(let minimumScore):
                Bench.keep(minimumScore)
            case .impossible:
                // The per-shape target is chosen to land strictly inside [atZero, atMax], so this
                // would mean the chosen target was not actually reachable -- a correctness bug in
                // this gate, not a GoalSeek defect, but still reported so it is never silent.
                let detail = "\(shape): target \(target) between atZero \(atZero) and atMax \(atMax) was unexpectedly impossible"
                Issue.record("\(detail)")
                Bench.keep(0)
            }
        }
        let medianMs = Bench.milliseconds(result.median)
        print("""
            PERF-BUDGET | goalSeekBoundedWorstCase/\(shape) | median \(String(format: "%.2f", medianMs))ms \
            | ceiling \(String(format: "%.2f", Self.goalSeekBoundedWorstCaseCeilingMs))ms \
            | headroom \(String(format: "%.2f", Self.goalSeekBoundedWorstCaseCeilingMs - medianMs))ms
            """)
        #expect(medianMs <= Self.goalSeekBoundedWorstCaseCeilingMs,
                "\(shape): median \(medianMs)ms exceeds the \(Self.goalSeekBoundedWorstCaseCeilingMs)ms ceiling")
    }
}
#endif
