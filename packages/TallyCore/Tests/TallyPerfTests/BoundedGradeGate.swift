// R-2 (resilience.md): the release gate on the grade engine's worst case inside
// `GradeSanitizing`'s bounds. An `extension CoreBenchmarks`, for the reason ScalingGateTests.swift
// gives: one suite identity keeps `.serialized` covering every timing-sensitive test here.
#if !DEBUG
import Foundation
import Testing
import TallyDomain
import TallyTestSupport

extension CoreBenchmarks {
    /// R-2: one `GradeEngine.scores` call on any `BoundedGradeWorstCase` (50 items, drop lowest and
    /// highest, 1e50 and a value just above the 1e-6 floor in one group) stays under 50 ms, the
    /// brief's release target, in this container. Measured after R-2b: medians of 1.8-6.7 ms. With
    /// R-2 alone (bounds, but big_f evaluated at every bisection step) the same inputs took
    /// 42.8-169.8 ms and fail it; unbounded, crash-safety-2.md F-5's 1e300 and 1e-300 took 2.4 s.
    /// `GoalSeek` makes about 62 such calls, so this is also what bounds a goal seek.
    static let boundedGradeWorstCaseCeilingMs = 50.0

    @Test("GradeEngine.scores on the bounded worst case stays under its ceiling", arguments: BoundedGradeWorstCase.allCases)
    func boundedGradeWorstCaseCeiling(_ shape: BoundedGradeWorstCase) {
        let input = shape.input
        let result = Bench.time("ceiling/gradeEngineBoundedWorstCase/\(shape)", iterations: 11, warmup: 2) {
            Bench.keep(GradeEngine.scores(for: input).finalScore ?? 0)
        }
        let medianMs = Bench.milliseconds(result.median)
        print("""
            PERF-BUDGET | gradeEngineBoundedWorstCase/\(shape) | median \(String(format: "%.2f", medianMs))ms \
            | ceiling \(String(format: "%.2f", Self.boundedGradeWorstCaseCeilingMs))ms \
            | headroom \(String(format: "%.2f", Self.boundedGradeWorstCaseCeilingMs - medianMs))ms
            """)
        #expect(medianMs <= Self.boundedGradeWorstCaseCeilingMs,
                "\(shape): median \(medianMs)ms exceeds the \(Self.boundedGradeWorstCaseCeilingMs)ms ceiling")
    }
}
#endif
