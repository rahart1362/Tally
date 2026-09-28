import Foundation

/// Wall-clock budgets for the hang detectors in the crash-safety tests (CS-02, CS-03). A budget
/// catches a runaway loop; it does not measure speed. `make core-perf` gates speed, in release
/// builds.
///
/// The same debug build runs much slower on some machines. In CI run 36368653168 the
/// greatest-finite-magnitude grade case took 47.8 s on the macOS runner (Xcode 26.6, debug),
/// against about 2.5 s for all eight cases on Linux. It was already at 44 s in the green run
/// before. Sanitizer builds are 5-15x slower again. So every budget is multiplied by
/// `TALLY_TEST_TIME_SCALE`: the default is 1 (local runs and the Linux CI job), the Makefile's
/// sanitizer targets set 10, and CI's macOS TallyCore step sets 4.
public enum TestTimeBudget {
    /// The multiplier from `TALLY_TEST_TIME_SCALE`. Values below 1 or unparsable values are
    /// ignored, so a budget can never be made tighter than the one written in the test.
    public static var scale: Double {
        guard let raw = ProcessInfo.processInfo.environment["TALLY_TEST_TIME_SCALE"],
              let value = Double(raw), value.isFinite, value >= 1 else { return 1 }
        return value
    }

    /// `base` seconds, times `scale`.
    public static func seconds(_ base: Double) -> Duration {
        .milliseconds(Int64((base * scale * 1_000).rounded()))
    }
}
