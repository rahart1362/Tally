// PERF-05 PA-1/PA-5 (docs/pmo/reviews/perf-algorithms.md): a per-course scaling gate.
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
// A permanent, hard gate since PA-5. On `pmo/assessment` @ 1ec17ff (before PA-2's precomputed
// weight context) it fails for `DashboardBuilder.build`, the PriorityScore pass and the
// AlertEngine pass at roughly 38-59x, and passes for `ReminderPlanner.plan` at ~9.4x; after PA-2
// all four sit at about 6.5-9.5x. The report has the runs.
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

    // Each ratio is `Bench.scalingRatio`'s median of three interleaved rounds of 11 iterations and
    // 2 warmups per side, the same measurement `ScalingGateTests` uses.

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

    /// Prints the ratio (and each round's), then gates it.
    private func gate(_ name: String, _ ratio: Double, rounds: [Double]) {
        print("PERF-SCALING | \(name) | 10x assignments per course -> \(String(format: "%.2f", ratio))x time \(roundsText(rounds))")
        #expect(ratio <= Self.maxPerCourseRatio,
                "\(name) scaled \(ratio)x for 10x the assignments per course (budget \(Self.maxPerCourseRatio)x)")
    }

    @Test func dashboardBuildScalesLinearlyInAssignmentsPerCourse() {
        let inputs = perCourseInputs()
        expectTenTimesPerCourse(inputs)
        let now = StressSnapshotFixture.referenceDate
        let (r, rounds) = Bench.scalingRatio(
            "perCourseBaseline/dashboardBuild", "perCourseStress/dashboardBuild",
            base: { _ = DashboardBuilder.build(from: inputs.base, digest: nil, digestAsOf: nil, now: now) },
            scaled: { _ = DashboardBuilder.build(from: inputs.big, digest: nil, digestAsOf: nil, now: now) })
        gate("dashboardBuild", r, rounds: rounds)
    }

    @Test func priorityScorePassScalesLinearlyInAssignmentsPerCourse() {
        let inputs = perCourseInputs()
        expectTenTimesPerCourse(inputs)
        let now = StressSnapshotFixture.referenceDate
        let (r, rounds) = Bench.scalingRatio(
            "perCourseBaseline/priorityScoreAllItems", "perCourseStress/priorityScoreAllItems",
            base: { Bench.keep(PerfPasses.priorityScore(items: inputs.baseItems, snapshot: inputs.base, now: now)) },
            scaled: { Bench.keep(PerfPasses.priorityScore(items: inputs.bigItems, snapshot: inputs.big, now: now)) })
        gate("priorityScoreAllItems", r, rounds: rounds)
    }

    @Test func alertEnginePassScalesLinearlyInAssignmentsPerCourse() {
        let inputs = perCourseInputs()
        expectTenTimesPerCourse(inputs)
        let now = StressSnapshotFixture.referenceDate
        let (r, rounds) = Bench.scalingRatio(
            "perCourseBaseline/alertEngineAllItems", "perCourseStress/alertEngineAllItems",
            base: { Bench.keep(PerfPasses.alertEngine(items: inputs.baseItems, snapshot: inputs.base, now: now)) },
            scaled: { Bench.keep(PerfPasses.alertEngine(items: inputs.bigItems, snapshot: inputs.big, now: now)) })
        gate("alertEngineAllItems", r, rounds: rounds)
    }

    @Test func reminderPlannerScalesLinearlyInAssignmentsPerCourse() {
        let inputs = perCourseInputs()
        expectTenTimesPerCourse(inputs)
        let now = StressSnapshotFixture.referenceDate
        let refresh = PerfPasses.reminderRefreshRecord(now: now)
        let baseCandidates = PerfPasses.reminderCandidates(items: inputs.baseItems, snapshot: inputs.base, now: now)
        let bigCandidates = PerfPasses.reminderCandidates(items: inputs.bigItems, snapshot: inputs.big, now: now)
        let (r, rounds) = Bench.scalingRatio(
            "perCourseBaseline/reminderPlannerAllItems", "perCourseStress/reminderPlannerAllItems",
            base: { Bench.keep(PerfPasses.reminderPlan(candidates: baseCandidates, refresh: refresh, now: now, label: "perCourseBaseline")) },
            scaled: { Bench.keep(PerfPasses.reminderPlan(candidates: bigCandidates, refresh: refresh, now: now, label: "perCourseStress")) })
        gate("reminderPlannerAllItems", r, rounds: rounds)
    }
}
#endif
