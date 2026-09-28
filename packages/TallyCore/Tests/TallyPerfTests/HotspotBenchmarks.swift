// PERF-05 PA-3 (docs/pmo/reviews/perf-algorithms.md): finer benchmarks that attribute the
// remaining stress-scale cost of `ReminderPlanner.plan` and `GradeEngine` to one cause each,
// through public API only (this target deliberately has no `@testable` access). Each pairs the
// real workload with the same workload minus one feature, timed in alternation, so the
// difference is that feature's cost. Informational: they print, they do not gate. The one gate
// here is `scheduleConflictsScalesLinearlyAtConstantDensity`, for the PA-3 sweep.
//
// An `extension CoreBenchmarks`, for the reason `ScalingGateTests.swift` gives.
#if !DEBUG
import Foundation
import Testing
import TallyDomain
import TallyTestSupport

extension CoreBenchmarks {
    private func share(_ part: BenchResult, of whole: BenchResult) -> String {
        let ms: (Duration) -> Double = { Double($0.components.seconds) * 1000 + Double($0.components.attoseconds) / 1e15 }
        let delta = ms(whole.median) - ms(part.median)
        return String(format: "%.2fms of %.2fms (%.0f%%)", delta, ms(whole.median), 100 * delta / max(ms(whole.median), 0.000_001))
    }

    /// `ReminderPlanner.plan` with the default quiet hours (23:00-07:00) against the same plan with
    /// quiet hours that never match (start == end). The difference is what shifting fire dates
    /// out of quiet hours costs: `shiftOutOfQuietHours` calls
    /// `Calendar.date(bySettingHour:minute:second:of:)` for every fire date inside quiet hours.
    @Test func reminderPlannerQuietHoursShare() {
        let snapshot = StressSnapshotFixture.make(scale: .stress)
        let now = StressSnapshotFixture.referenceDate
        let candidates = PerfPasses.reminderCandidates(items: openAssignments(in: snapshot), snapshot: snapshot, now: now)
        let refresh = PerfPasses.reminderRefreshRecord(now: now)
        let neverQuiet = ReminderSettings(quietHours: QuietHours(startHour: 0, startMinute: 0, endHour: 0, endMinute: 0))
        let (withoutShift, withShift) = Bench.timeInterleaved(
            "hotspot/reminderPlanner/stress/noQuietHours", "hotspot/reminderPlanner/stress/defaultQuietHours",
            iterations: 11, warmup: 2,
            {
                let plan = ReminderPlanner.plan(accountKey: AccountKey("perf"), candidates: candidates, settings: neverQuiet,
                                                now: now, timeZone: PerfPasses.reminderTimeZone, refresh: refresh)
                Bench.keep(Double(plan.count))
            },
            { Bench.keep(PerfPasses.reminderPlan(candidates: candidates, refresh: refresh, now: now, label: "stress")) })
        print("PERF-SHARE | reminderPlanner/stress | quiet-hours shifting = \(share(withoutShift, of: withShift))")
    }

    /// `GradeEngine` over every stress course against the same courses with every group's drop
    /// rules removed. With no rules, `DropRuleSelection.keptIndices` returns at its first line,
    /// so the difference is what the exact-rational drop-rule bisection costs (its algorithm is
    /// Canvas-parity-critical and is not changed by PERF-05; this only reports its share).
    @Test func gradeEngineDropRuleShare() {
        let snapshot = StressSnapshotFixture.make(scale: .stress)
        let withoutRules = snapshot.groups.mapValues { groups in
            groups.map { AssignmentGroup(id: $0.id, name: $0.name, position: $0.position, weight: $0.weight,
                                         rules: DropRules(), assignments: $0.assignments) }
        }
        let (noRules, rules) = Bench.timeInterleaved(
            "hotspot/gradeEngineAllCourses/stress/noDropRules", "hotspot/gradeEngineAllCourses/stress/dropRules",
            iterations: 11, warmup: 2,
            {
                for course in snapshot.courses {
                    Bench.keep(GradeEngine.scores(course: course, groups: withoutRules[course.id] ?? [],
                                                  gradingPeriods: snapshot.gradingPeriods[course.id] ?? []).currentScore ?? 0)
                }
            },
            {
                for course in snapshot.courses {
                    Bench.keep(GradeEngine.scores(course: course, groups: snapshot.groups[course.id] ?? [],
                                                  gradingPeriods: snapshot.gradingPeriods[course.id] ?? []).currentScore ?? 0)
                }
            })
        print("PERF-SHARE | gradeEngineAllCourses/stress | DropRuleSelection = \(share(noRules, of: rules))")
    }

    /// `AlertEngine.scheduleConflicts` over 10x the schedule items spread over 10x the time, so
    /// the density (and so the number of real conflicts per item) stays the same. The all-pairs
    /// loop PA-3 replaced measured 100.7-101.5x here (1.0 -> 100 ms). The sweep sorts, so its
    /// natural ratio is n log n's, 10 x log(5000)/log(500) = 13.7x (measured 13.7-14.1x), not
    /// 10x: `scheduleConflictsMaxRatio` applies `maxAcceptableRatio`'s own 35% headroom over 10x
    /// to that, ~18.5x. That still fails the quadratic loop by more than 5x.
    static let scheduleConflictsMaxRatio = maxAcceptableRatio / 10 * (10 * log(5000.0) / log(500.0))

    @Test func scheduleConflictsScalesLinearlyAtConstantDensity() {
        func schedule(_ count: Int, days: Double) -> [AlertEngine.ScheduleItem] {
            var rng = SeededRandom(seed: 0x5C4E_D01E)
            return (0..<count).map { i in
                let start = StressSnapshotFixture.referenceDate.addingTimeInterval(Double.random(in: 0..<(days * 86_400), using: &rng))
                return i.isMultiple(of: 3)
                    ? AlertEngine.ScheduleItem(id: "class-\(i)", start: start, end: start.addingTimeInterval(3000), isExam: i.isMultiple(of: 9))
                    : AlertEngine.ScheduleItem(id: "due-\(i)", start: start)
            }
        }
        let base = schedule(500, days: 12)
        let big = schedule(5000, days: 120)
        let (baseResult, bigResult) = Bench.timeInterleaved(
            "scheduleConflicts/500-items-12-days", "scheduleConflicts/5000-items-120-days", iterations: 11, warmup: 2,
            { Bench.keep(Double(AlertEngine.scheduleConflicts(base).count)) },
            { Bench.keep(Double(AlertEngine.scheduleConflicts(big).count)) })
        let ms: (Duration) -> Double = { Double($0.components.seconds) * 1000 + Double($0.components.attoseconds) / 1e15 }
        let ratio = ms(bigResult.median) / max(ms(baseResult.median), 0.000_001)
        print("PERF-SCALING | scheduleConflicts | 10x items at constant density -> \(String(format: "%.2f", ratio))x time "
            + "(budget \(String(format: "%.2f", Self.scheduleConflictsMaxRatio))x)")
        #expect(ratio <= Self.scheduleConflictsMaxRatio,
                "scheduleConflicts scaled \(ratio)x for 10x the items at constant density (budget \(Self.scheduleConflictsMaxRatio)x)")
    }

    /// `GradeEngine` under the per-course scaling of `PerCourseScalingGateTests` (25 -> 250
    /// assignments per course). Reported, not gated: the drop-rule bisection sorts each drop-rule
    /// group once per bisection step, so its cost grows faster than linearly with group size by
    /// design, and it is out of this work package's scope to change.
    @Test func gradeEnginePerCourseScalingIsReported() {
        let base = StressSnapshotFixture.make(scale: Self.perCourseBaseline)
        let big = StressSnapshotFixture.make(scale: .stress)
        let (baseResult, bigResult) = Bench.timeInterleaved(
            "perCourseBaseline/gradeEngineAllCourses", "perCourseStress/gradeEngineAllCourses",
            iterations: 11, warmup: 2,
            {
                for course in base.courses {
                    Bench.keep(GradeEngine.scores(course: course, groups: base.groups[course.id] ?? [],
                                                  gradingPeriods: base.gradingPeriods[course.id] ?? []).currentScore ?? 0)
                }
            },
            {
                for course in big.courses {
                    Bench.keep(GradeEngine.scores(course: course, groups: big.groups[course.id] ?? [],
                                                  gradingPeriods: big.gradingPeriods[course.id] ?? []).currentScore ?? 0)
                }
            })
        let ms: (Duration) -> Double = { Double($0.components.seconds) * 1000 + Double($0.components.attoseconds) / 1e15 }
        let ratio = ms(bigResult.median) / max(ms(baseResult.median), 0.000_001)
        print("PERF-SCALING | gradeEngineAllCourses | 10x assignments per course -> \(String(format: "%.2f", ratio))x time (reported, not gated)")
    }
}
#endif
