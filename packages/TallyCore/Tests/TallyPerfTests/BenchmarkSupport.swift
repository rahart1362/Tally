import Foundation

/// PERF-01: shared timing/memory measurement plumbing for `TallyPerfTests`. Nothing here is
/// itself gated to release builds — it is cheap to type-check and never runs expensive work on
/// its own — only the `@Test` bodies in the other files (behind `#if !DEBUG`) call it.

/// One benchmark's raw samples plus the derived statistics every report line uses.
public struct BenchResult: Sendable {
    public let label: String
    public let samples: [Duration]
    public let iterations: Int

    public var median: Duration {
        let sorted = samples.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
    public var min: Duration { samples.min() ?? .zero }
    public var max: Duration { samples.max() ?? .zero }

    private static func ms(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    /// One tab-separated, grep-able line: `PERF | <label> | median=…ms | n=… | min=…ms | max=…ms`.
    public var reportLine: String {
        let m = Self.ms(median), lo = Self.ms(min), hi = Self.ms(max)
        return "PERF | \(label) | median=\(String(format: "%.4f", m))ms | n=\(iterations) "
            + "| min=\(String(format: "%.4f", lo))ms | max=\(String(format: "%.4f", hi))ms"
    }
}

/// Median-of-N wall-clock timing (implementation brief / charter: "median of >= 5 iterations").
public enum Bench {
    /// Runs `warmup` untimed iterations (JIT/allocator/page-cache warm-up — release-mode Swift
    /// has no JIT, but the first pass still pays one-time lazy-static and allocator costs), then
    /// `iterations` timed ones, and prints+returns the median.
    @discardableResult
    public static func time(_ label: String, iterations: Int = 5, warmup: Int = 1,
                            _ body: () throws -> Void) rethrows -> BenchResult {
        for _ in 0..<warmup { try body() }
        var samples: [Duration] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let clock = ContinuousClock()
            let start = clock.now
            try body()
            samples.append(clock.now - start)
        }
        let result = BenchResult(label: label, samples: samples, iterations: iterations)
        print(result.reportLine)
        return result
    }

    @discardableResult
    public static func timeAsync(_ label: String, iterations: Int = 5, warmup: Int = 1,
                                 _ body: () async throws -> Void) async rethrows -> BenchResult {
        for _ in 0..<warmup { try await body() }
        var samples: [Duration] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let clock = ContinuousClock()
            let start = clock.now
            try await body()
            samples.append(clock.now - start)
        }
        let result = BenchResult(label: label, samples: samples, iterations: iterations)
        print(result.reportLine)
        return result
    }

    /// PERF-05: times two bodies in alternation (`a`, `b`, `a`, `b`, ...) instead of all of `a`
    /// then all of `b`, and prints and returns both medians. A ratio gate compares the two
    /// medians, and this machine is shared with other builds: a burst of outside load that lands
    /// on only one side of a sequential run moves the ratio by itself (observed: a
    /// `ScalingGateTests` ratio of 20.63x for the linear `ChangeDigest.diff` while another
    /// engineer's Swift container was running). Alternating spreads any such burst over both
    /// sides.
    public static func timeInterleaved(_ labelA: String, _ labelB: String, iterations: Int = 5, warmup: Int = 1,
                                       _ a: () throws -> Void, _ b: () throws -> Void) rethrows -> (a: BenchResult, b: BenchResult) {
        for _ in 0..<warmup {
            try a()
            try b()
        }
        var samplesA: [Duration] = [], samplesB: [Duration] = []
        samplesA.reserveCapacity(iterations)
        samplesB.reserveCapacity(iterations)
        let clock = ContinuousClock()
        for _ in 0..<iterations {
            var start = clock.now
            try a()
            samplesA.append(clock.now - start)
            start = clock.now
            try b()
            samplesB.append(clock.now - start)
        }
        let resultA = BenchResult(label: labelA, samples: samplesA, iterations: iterations)
        let resultB = BenchResult(label: labelB, samples: samplesB, iterations: iterations)
        print(resultA.reportLine)
        print(resultB.reportLine)
        return (resultA, resultB)
    }

    /// PERF-05 PA-5: a scaling gate's ratio, `scaled` median over `base` median, measured in
    /// `rounds` separate interleaved rounds (each `timeInterleaved(iterations:warmup:)`), and
    /// the median of the round ratios. Why rounds: after PERF-05 made `DashboardBuilder.build`
    /// cheap, outside load on this shared machine could slow its stress side for a whole
    /// measurement while the 10x-smaller baseline stayed fast, which alternating samples alone
    /// cannot cancel out: one interleaved run read 16.73x for a linear function (stress-side
    /// minimum 8.05 ms against ~4.9 ms in other runs). A real superlinear cost is high in every
    /// round, so the median of three still fails on it; an outside episode has to last through
    /// two of the three rounds to.
    public static func scalingRatio(_ baseLabel: String, _ scaledLabel: String, rounds: Int = 3, iterations: Int = 11,
                                    warmup: Int = 2, base: () throws -> Void, scaled: () throws -> Void) rethrows
        -> (ratio: Double, roundRatios: [Double]) {
        var ratios: [Double] = []
        for round in 1...max(1, rounds) {
            let (b, s) = try timeInterleaved("\(baseLabel)#\(round)", "\(scaledLabel)#\(round)",
                                             iterations: iterations, warmup: warmup, base, scaled)
            ratios.append(milliseconds(s.median) / max(milliseconds(b.median), 0.000_001))
        }
        return (medianOf(ratios), ratios)
    }

    /// The middle value (the mean of the middle two for an even count); 0 for no values.
    public static func medianOf(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    public static func milliseconds(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    /// PERF-05: keeps a benchmark body's result observable, so the optimizer cannot delete the
    /// work that produced it once enough of that work is inlined across modules. The branch is
    /// never taken for a real checksum (every pass sums finite, non-negative terms), but the
    /// compiler cannot prove that, so it must compute `value`.
    @inline(never)
    public static func keep(_ value: Double) {
        if value.isNaN && value.sign == .minus { print("Bench.keep: unreachable checksum \(value)") }
    }
}

/// Peak resident set size, read from `/proc/self/status` (Linux only — the pinned container
/// and CI's `core-linux` job are the only places this needs to run).
public enum MemoryProbe {
    /// Writing "5" resets this **process's own** peak-RSS high-water mark to its current RSS
    /// (Linux >= 4.0, `proc(5)`); harmless and needs no special privilege for one's own process.
    /// Returns whether the reset was accepted, so a caller can tell "this scenario's own peak"
    /// from "cumulative peak since process start" in its report.
    @discardableResult
    public static func resetPeak() -> Bool {
        guard let handle = FileHandle(forWritingAtPath: "/proc/self/clear_refs") else { return false }
        defer { try? handle.close() }
        do { try handle.write(contentsOf: Data("5".utf8)); return true } catch { return false }
    }

    /// `VmHWM` in bytes, or `nil` off Linux or if `/proc/self/status` is unreadable.
    public static func peakResidentSetBytes() -> UInt64? {
        guard let text = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("VmHWM:") {
            let digits = line.split(separator: " ").compactMap { UInt64($0) }
            if let kib = digits.first { return kib * 1024 }
        }
        return nil
    }

    /// Resets the peak, runs `body` once, and reports the peak RSS reached during it. When the
    /// reset is refused (sandboxed/unprivileged container), `resetSucceeded` is `false` and the
    /// reported bytes are the cumulative process peak up to and including `body` — still a valid
    /// (if less precise) upper bound, per the work package's documented fallback.
    @discardableResult
    public static func measurePeak(_ label: String, _ body: () throws -> Void) rethrows -> (bytes: UInt64?, resetSucceeded: Bool) {
        let resetOK = resetPeak()
        try body()
        let bytes = peakResidentSetBytes()
        let mb = bytes.map { Double($0) / 1_048_576 } ?? .nan
        print("PERF-MEM | \(label) | peakRSS=\(String(format: "%.3f", mb))MiB | reset=\(resetOK)")
        return (bytes, resetOK)
    }

    @discardableResult
    public static func measurePeakAsync(_ label: String, _ body: () async throws -> Void) async rethrows
        -> (bytes: UInt64?, resetSucceeded: Bool) {
        let resetOK = resetPeak()
        try await body()
        let bytes = peakResidentSetBytes()
        let mb = bytes.map { Double($0) / 1_048_576 } ?? .nan
        print("PERF-MEM | \(label) | peakRSS=\(String(format: "%.3f", mb))MiB | reset=\(resetOK)")
        return (bytes, resetOK)
    }
}
