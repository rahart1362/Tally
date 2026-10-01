// XG-01 (docs/pmo/08-localization-and-external-grades.md §4.3 "Perf"): the grade-availability
// classifier is one pass over the assignments and must stay inside the perf budgets. An `extension
// CoreBenchmarks`, same reasoning as ScalingGateTests.swift: one suite identity keeps `.serialized`
// covering every timing-sensitive test in this target.
#if !DEBUG
import Foundation
import Testing
import TallyDomain
import TallyTestSupport

extension CoreBenchmarks {
    /// The whole-snapshot index (every course classified, plus the school summary) over the `large`
    /// persona (12 courses, 153 assignments), release mode, median of 21, measured twice:
    /// - as the app builds it: every `large` course has a Canvas score, so rule 2 answers before any
    ///   assignment is read;
    /// - the worst case, which is gated: the kept-outside override on every course forces the one
    ///   pass over every assignment (the override needs the evidence counts).
    /// Gated like `snapshotDecodeDeviceBudget`: the median times `deviceToCIFactor` (an estimate, see
    /// RegressionGates.swift) must stay under `deviceSafetyMargin` of the charter's 50 ms budget for
    /// synchronous work (`TallyConfig.mainActorStallBudget`). The index is built off the main actor
    /// (plan 08 §4.3), so this is the strictest budget it could ever be held to.
    @Test("GradeAvailabilityIndex over the large persona stays inside the 50 ms budget")
    func gradeAvailabilityIndexLarge() async throws {
        let context = try await PerfFixtures.context(for: .large)
        let snapshot = context.snapshot
        let everyCourseScanned = Dictionary(snapshot.courses.map { ($0.id, GradeAvailabilityOverride.keptOutsideCanvas) },
                                            uniquingKeysWith: { first, _ in first })
        Bench.time("gradeAvailabilityIndex/large", iterations: 21, warmup: 3) {
            let index = GradeAvailabilityIndex(snapshot: snapshot, overrides: [:], now: PerfFixtures.anchor)
            Bench.keep(Double(index.byCourse.count))
        }
        let result = Bench.time("gradeAvailabilityIndex/large-fullScan", iterations: 21, warmup: 3) {
            let index = GradeAvailabilityIndex(snapshot: snapshot, overrides: everyCourseScanned, now: PerfFixtures.anchor)
            var items = 0
            for case .keptOutsideCanvas(let evidence) in index.byCourse.values { items += evidence.pastDueItems }
            Bench.keep(Double(items))
        }
        #expect(GradeAvailabilityIndex(snapshot: snapshot, overrides: [:], now: PerfFixtures.anchor).school == .allInCanvas,
                "the fast path: every large course has a Canvas score")
        let scanned = GradeAvailabilityIndex(snapshot: snapshot, overrides: everyCourseScanned, now: PerfFixtures.anchor)
        #expect(scanned.byCourse.count == snapshot.courses.count, "every course classified")
        #expect(scanned.school == .noneInCanvas, "every course went through the kept-outside path")

        let ciMs = Bench.milliseconds(result.median)
        let projectedDeviceMs = ciMs * Self.deviceToCIFactor
        let gatedCeilingMs = TallyConfig.mainActorStallBudget.timeInterval * 1000 * Self.deviceSafetyMargin
        print("""
            PERF-BUDGET | gradeAvailabilityIndex/large-fullScan | CI=\(String(format: "%.4f", ciMs))ms \
            x factor \(Self.deviceToCIFactor) = projected \(String(format: "%.4f", projectedDeviceMs))ms \
            | gated ceiling \(String(format: "%.2f", gatedCeilingMs))ms \
            (80% of \(TallyConfig.mainActorStallBudget.timeInterval * 1000)ms) \
            | headroom \(String(format: "%.2f", gatedCeilingMs - projectedDeviceMs))ms
            """)
        #expect(projectedDeviceMs <= gatedCeilingMs,
                "gradeAvailabilityIndex/large-fullScan: projected \(projectedDeviceMs)ms exceeds the \(gatedCeilingMs)ms gated ceiling")
    }
}
#endif
