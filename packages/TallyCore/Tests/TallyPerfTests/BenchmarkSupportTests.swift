import Testing

/// PERF-01: correctness tests for the harness's own math (median-of-N, memory probe), not for
/// app performance. Deliberately **not** gated behind `#if !DEBUG` — unlike the benchmarks
/// themselves, these are fast, deterministic and belong in `make core-test`'s always-run set,
/// so a broken median calculation is caught long before anyone reads a `make core-perf` number
/// off it. `BenchResult`/`Bench`/`MemoryProbe` live in `BenchmarkSupport.swift`, the same
/// target, so no import beyond `Testing` is needed to see them.
@Suite("BenchResult median-of-N")
struct BenchmarkSupportTests {
    @Test func medianOfOddSampleCountIsTheMiddleValue() {
        let result = BenchResult(label: "t", samples: [.milliseconds(5), .milliseconds(1), .milliseconds(3)], iterations: 3)
        #expect(result.median == .milliseconds(3))
        #expect(result.min == .milliseconds(1))
        #expect(result.max == .milliseconds(5))
    }

    @Test func medianOfEvenSampleCountAveragesTheMiddleTwo() {
        let result = BenchResult(label: "t", samples: [.milliseconds(10), .milliseconds(2), .milliseconds(6), .milliseconds(4)], iterations: 4)
        // sorted: 2, 4, 6, 10 -> (4 + 6) / 2 = 5
        #expect(result.median == .milliseconds(5))
    }

    /// The charter/implementation brief require "median of >= 5 iterations": this guards the
    /// harness itself always reports that many raw samples, not a truncated or padded set.
    @Test func iterationsMatchesSampleCountForTheDefaultBenchRun() {
        var calls = 0
        let result = Bench.time("meta-test", iterations: 5, warmup: 1) { calls += 1 }
        #expect(result.samples.count == 5)
        #expect(result.iterations == 5)
        #expect(calls == 6) // 1 warmup + 5 timed
    }

    /// PERF-05: the interleaved timer runs both bodies the same number of times, strictly
    /// alternating (warmups included), and reports one full sample set per body.
    @Test func interleavedTimingAlternatesAndCountsBothBodies() {
        var order: [Character] = []
        let (a, b) = Bench.timeInterleaved("meta-a", "meta-b", iterations: 5, warmup: 2, { order.append("a") }, { order.append("b") })
        #expect(a.samples.count == 5 && b.samples.count == 5)
        #expect(a.iterations == 5 && b.iterations == 5)
        #expect(String(order) == String(repeating: "ab", count: 7)) // 2 warmups + 5 timed, alternating
    }

    @Test func reportLineNamesTheLabelAndSampleCount() {
        let result = BenchResult(label: "widget/flagship", samples: [.milliseconds(1)], iterations: 1)
        #expect(result.reportLine.contains("widget/flagship"))
        #expect(result.reportLine.contains("n=1"))
    }

    /// Linux-only (the pinned container and CI's `core-linux` job): a plausible non-zero peak.
    @Test func peakResidentSetIsReadableOnLinux() {
        #if os(Linux)
        let bytes = MemoryProbe.peakResidentSetBytes()
        #expect(bytes != nil)
        if let bytes { #expect(bytes > 0) }
        #endif
    }
}
