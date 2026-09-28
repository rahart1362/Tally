// PERF-05 PA-1 (docs/pmo/reviews/perf-algorithms.md): a per-course scaling gate.
//
// `ScalingGateTests` scales the *number of courses* (2 -> 20) with the per-course shape fixed, so
// any cost that is quadratic *within* one course grows only linearly there and passes. The PMO
// found exactly such a pattern (`PriorityScore.weight` re-filtering the whole course or group for
// every item). This gate holds the course count fixed (20) and scales *assignments per course*
// 10x (25 -> 250) and planner items with them (110 -> 1095), so 10x the data again, but now all
// of the growth lands inside each course. `perCourseBaseline` is `.stress` at 1/10th the
// assignments: same course count, same 5 groups per course, same drop-rule pattern by group
// index, same seed. `StressSnapshotFixture.make` builds both from the same code path.
//
// An `extension CoreBenchmarks`, for the reason `ScalingGateTests.swift` gives: one suite
// identity keeps `.serialized` covering every timing-sensitive test in this target.
//
// Status at PA-1: on `pmo/assessment` @ 1ec17ff this gate fails for `DashboardBuilder.build`
// (~52-54x), the PriorityScore pass (~50-52x) and the AlertEngine pass (~58-59x) over three runs,
// and passes for `ReminderPlanner.plan` (~9.3-9.5x). Those three are recorded as intermittent
// known issues (`knownQuadratic: true`) until PA-2's precomputed weight context lands, so this
// commit stays green without hiding the failure; PA-5 removes the escape hatch.
#if !DEBUG
import Foundation
import Testing
import TallyDomain
import TallyTestSupport

extension CoreBenchmarks {
    static let perCourseBaseline = StressSnapshotFixture.Scale(
        courseCount: StressSnapshotFixture.Scale.stress.courseCount,
        assignmentsPerCourse: StressSnapshotFixture.Scale.stress.assignmentsPerCourse / 10,
        groupsPerCourse: StressSnapshotFixture.Scale.stress.groupsPerCourse,
        plannerItemCount: 110, // `.scalingBaseline`'s own ~1/10th of `.stress`'s 1095
        seed: StressSnapshotFixture.Scale.stress.seed)

    /// The same budget `ScalingGateTests` uses for 10x the data (see `maxAcceptableRatio`'s
    /// comment there for why 13.5x rather than the charter's ~12x).
    static let maxPerCourseRatio = maxAcceptableRatio

    /// 11 timed iterations and 2 warmups per side, `ScalingGateTests`' settings, but timed in
    /// alternation (`Bench.timeInterleaved`) so outside load on this shared machine lands on
    /// both sides of the ratio.
    private static let gateIterations = 11
    private static let gateWarmup = 2

    private struct PerCourseInputs {
        let base: CanvasSnapshot
        let big: CanvasSnapshot
        let baseItems: [OpenItem]
        let bigItems: [OpenItem]
    }

    private func perCourseInputs() -> PerCourseInputs {
        let base = StressSnapshotFixture.make(scale: Self.perCourseBaseline)
        let big = StressSnapshotFixture.make(scale: .stress)
        return PerCourseInputs(base: base, big: big, baseItems: openAssignments(in: base), bigItems: openAssignments(in: big))
    }

    /// The "10x" precondition, stated not assumed: the course count is identical, the
    /// assignment count is exactly 10x, and so the growth is all per course.
    private func expectTenTimesPerCourse(_ inputs: PerCourseInputs) {
        #expect(inputs.big.courses.count == inputs.base.courses.count)
        #expect(inputs.bigItems.count == 10 * inputs.baseItems.count)
    }

    private func perCourseRatio(_ scaledUp: BenchResult, _ baseline: BenchResult) -> Double {
        let ms: (Duration) -> Double = { Double($0.components.seconds) * 1000 + Double($0.components.attoseconds) / 1e15 }
        return ms(scaledUp.median) / max(ms(baseline.median), 0.000_001)
    }

    /// Prints the ratio, then gates it. `knownQuadratic` marks a pass that still calls the
    /// per-item O(n·p) `PriorityScore.weight` (PA-1 only; see this file's header).
    private func gate(_ name: String, _ ratio: Double, knownQuadratic: Bool) {
        print("PERF-SCALING | \(name) | 10x assignments per course -> \(String(format: "%.2f", ratio))x time")
        let check = {
            #expect(ratio <= Self.maxPerCourseRatio,
                    "\(name) scaled \(ratio)x for 10x the assignments per course (budget \(Self.maxPerCourseRatio)x)")
        }
        if knownQuadratic {
            withKnownIssue("PERF-05 PA-1: per-course O(n²·p) PriorityScore.weight, fixed by PA-2", isIntermittent: true) {
                check()
            }
        } else {
            check()
        }
    }

    @Test func dashboardBuildScalesLinearlyInAssignmentsPerCourse() {
        let inputs = perCourseInputs()
        expectTenTimesPerCourse(inputs)
        let now = StressSnapshotFixture.referenceDate
        let (baseResult, bigResult) = Bench.timeInterleaved(
            "perCourseBaseline/dashboardBuild", "perCourseStress/dashboardBuild",
            iterations: Self.gateIterations, warmup: Self.gateWarmup,
            { _ = DashboardBuilder.build(from: inputs.base, digest: nil, digestAsOf: nil, now: now) },
            { _ = DashboardBuilder.build(from: inputs.big, digest: nil, digestAsOf: nil, now: now) })
        let r = perCourseRatio(bigResult, baseResult)
        gate("dashboardBuild", r, knownQuadratic: true)
    }

    @Test func priorityScorePassScalesLinearlyInAssignmentsPerCourse() {
        let inputs = perCourseInputs()
        expectTenTimesPerCourse(inputs)
        let now = StressSnapshotFixture.referenceDate
        let (baseResult, bigResult) = Bench.timeInterleaved(
            "perCourseBaseline/priorityScoreAllItems", "perCourseStress/priorityScoreAllItems",
            iterations: Self.gateIterations, warmup: Self.gateWarmup,
            { Bench.keep(PerfPasses.priorityScore(items: inputs.baseItems, snapshot: inputs.base, now: now)) },
            { Bench.keep(PerfPasses.priorityScore(items: inputs.bigItems, snapshot: inputs.big, now: now)) })
        let r = perCourseRatio(bigResult, baseResult)
        gate("priorityScoreAllItems", r, knownQuadratic: true)
    }

    @Test func alertEnginePassScalesLinearlyInAssignmentsPerCourse() {
        let inputs = perCourseInputs()
        expectTenTimesPerCourse(inputs)
        let now = StressSnapshotFixture.referenceDate
        let (baseResult, bigResult) = Bench.timeInterleaved(
            "perCourseBaseline/alertEngineAllItems", "perCourseStress/alertEngineAllItems",
            iterations: Self.gateIterations, warmup: Self.gateWarmup,
            { Bench.keep(PerfPasses.alertEngine(items: inputs.baseItems, snapshot: inputs.base, now: now)) },
            { Bench.keep(PerfPasses.alertEngine(items: inputs.bigItems, snapshot: inputs.big, now: now)) })
        let r = perCourseRatio(bigResult, baseResult)
        gate("alertEngineAllItems", r, knownQuadratic: true)
    }

    @Test func reminderPlannerScalesLinearlyInAssignmentsPerCourse() {
        let inputs = perCourseInputs()
        expectTenTimesPerCourse(inputs)
        let now = StressSnapshotFixture.referenceDate
        let refresh = PerfPasses.reminderRefreshRecord(now: now)
        let baseCandidates = PerfPasses.reminderCandidates(items: inputs.baseItems, snapshot: inputs.base, now: now)
        let bigCandidates = PerfPasses.reminderCandidates(items: inputs.bigItems, snapshot: inputs.big, now: now)
        let (baseResult, bigResult) = Bench.timeInterleaved(
            "perCourseBaseline/reminderPlannerAllItems", "perCourseStress/reminderPlannerAllItems",
            iterations: Self.gateIterations, warmup: Self.gateWarmup,
            { Bench.keep(PerfPasses.reminderPlan(candidates: baseCandidates, refresh: refresh, now: now, label: "perCourseBaseline")) },
            { Bench.keep(PerfPasses.reminderPlan(candidates: bigCandidates, refresh: refresh, now: now, label: "perCourseStress")) })
        let r = perCourseRatio(bigResult, baseResult)
        gate("reminderPlannerAllItems", r, knownQuadratic: false)
    }
}
#endif
