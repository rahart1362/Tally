// PERF-04 (docs/pmo/05-perf-crash-charter.md): "10x the data must cost about 10x the time,
// never superlinear." `StressSnapshotFixture.Scale.scalingBaseline` and `.stress` are generated
// by the exact same function or (`StressSnapshotFixture.make`) with identical per-course shape
// (same assignments-per-course, same drop-rule pattern by group index, same seed) and differ
// only in course count (2 vs 20, a clean 10x) -- so any ratio far from 10x here is the
// algorithm's own behavior, not a difference in what the two inputs contain.
//
// An `extension CoreBenchmarks` on purpose, not its own `@Suite`: swift-testing schedules
// different suites' tests concurrently by default regardless of one suite's own `.serialized`
// trait (only tests *within* a serialized suite are guaranteed not to overlap each other) --
// confirmed directly, by running this file as a standalone suite alongside `CoreBenchmarks` and
// seeing the exact same cross-run noise (2-5x outliers) that motivated `.serialized` in the
// first place. Extending the same type keeps every timing-sensitive test in this target under
// one suite identity, so `.serialized` on `CoreBenchmarks`'s primary declaration covers these too.
//
// PERF-05 PA-5: each ratio is now `Bench.scalingRatio`: three rounds, each timing the two sides
// in alternation (11 iterations, 2 warmups, as before), gated on the median round. PERF-05's
// weight context cut the stress-side `DashboardBuilder.build` from ~70 ms to ~5 ms, and at that
// size outside load on this shared machine moved a single sequential ratio by itself: twelve
// sequential runs read 7.8x to 17.3x (one over budget), and one interleaved run 16.73x. Same
// 13.5x budget.
#if !DEBUG
import Testing
import TallyDomain
import TallyTestSupport

extension CoreBenchmarks {
    /// Safety margin over the charter's "~10x" wording (work package: "10x the data costs no
    /// more than ~12x the time"), widened from 12.0 to 13.5 after measuring this container's own
    /// noise floor: 4 repeated runs of a genuinely linear function (`changeDigestDiff`, confirmed
    /// by reading it — no nested per-item scan) swung between 9.3x and 12.14x on nothing but
    /// scheduling/allocator noise, with 11 iterations and 2 warmups already. 13.5x keeps real
    /// headroom above that observed ceiling while staying far below the 19.42x this gate actually
    /// caught (`AlertEngine.overloadClusters`'s O(n^2) window scan, fixed in this work package) --
    /// i.e. it still distinguishes "basically linear" from "superlinear", it just doesn't fire on
    /// this container's ordinary jitter for an algorithm that was never the problem.
    static let maxAcceptableRatio = 13.5

    /// `(rounds 9.81x 10.02x 10.40x)`: every round's ratio, printed next to the gated median.
    func roundsText(_ rounds: [Double]) -> String {
        "(rounds " + rounds.map { String(format: "%.2fx", $0) }.joined(separator: " ") + ")"
    }

    @Test func gradeEngineScalesLinearlyNotSuperlinearly() {
        let base = StressSnapshotFixture.make(scale: .scalingBaseline)
        let big = StressSnapshotFixture.make(scale: .stress)
        #expect(big.courses.count == 10 * base.courses.count) // the "10x" precondition, stated not assumed

        let (r, rounds) = Bench.scalingRatio(
            "scalingBaseline/gradeEngineAllCourses", "stress/gradeEngineAllCourses",
            base: {
                for course in base.courses {
                    _ = GradeEngine.scores(course: course, groups: base.groups[course.id] ?? [], gradingPeriods: base.gradingPeriods[course.id] ?? [])
                }
            },
            scaled: {
                for course in big.courses {
                    _ = GradeEngine.scores(course: course, groups: big.groups[course.id] ?? [], gradingPeriods: big.gradingPeriods[course.id] ?? [])
                }
            })
        print("PERF-SCALING | gradeEngineAllCourses | 10x courses -> \(String(format: "%.2f", r))x time \(roundsText(rounds))")
        #expect(r <= Self.maxAcceptableRatio, "GradeEngine scaled \(r)x for 10x the courses (budget \(Self.maxAcceptableRatio)x)")
    }

    @Test func dashboardBuildScalesLinearlyNotSuperlinearly() {
        let base = StressSnapshotFixture.make(scale: .scalingBaseline)
        let big = StressSnapshotFixture.make(scale: .stress)
        #expect(big.courses.count == 10 * base.courses.count)

        let (r, rounds) = Bench.scalingRatio(
            "scalingBaseline/dashboardBuild", "stress/dashboardBuild",
            base: { _ = DashboardBuilder.build(from: base, digest: nil, digestAsOf: nil, now: StressSnapshotFixture.referenceDate) },
            scaled: { _ = DashboardBuilder.build(from: big, digest: nil, digestAsOf: nil, now: StressSnapshotFixture.referenceDate) })
        print("PERF-SCALING | dashboardBuild | 10x courses -> \(String(format: "%.2f", r))x time \(roundsText(rounds))")
        #expect(r <= Self.maxAcceptableRatio, "DashboardBuilder.build scaled \(r)x for 10x the courses (budget \(Self.maxAcceptableRatio)x)")
    }

    @Test func changeDigestDiffScalesLinearlyNotSuperlinearly() {
        let base = StressSnapshotFixture.make(scale: .scalingBaseline)
        let big = StressSnapshotFixture.make(scale: .stress)

        let (r, rounds) = Bench.scalingRatio(
            "scalingBaseline/changeDigestDiff", "stress/changeDigestDiff",
            base: { _ = ChangeDigest.diff(old: base, new: base) }, scaled: { _ = ChangeDigest.diff(old: big, new: big) })
        print("PERF-SCALING | changeDigestDiff | 10x courses -> \(String(format: "%.2f", r))x time \(roundsText(rounds))")
        #expect(r <= Self.maxAcceptableRatio, "ChangeDigest.diff scaled \(r)x for 10x the courses (budget \(Self.maxAcceptableRatio)x)")
    }
}
#endif
