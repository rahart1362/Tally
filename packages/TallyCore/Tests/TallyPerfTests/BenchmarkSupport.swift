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
