import Foundation

/// A coarse grade bucket, never a raw percentage or letter string, so the widget's `.privacySensitive()`
/// redaction and the "opt-in only" rule (encryption.md D-E3, PMO R10) have one narrow surface to cover.
///
/// PERF-02: moved here from `TallyStore.GlanceProjection` (WP-C03) so `DashboardProjection`'s
/// output types can live in `TallyDomain` too — `TallyDomain` sits below `TallyStore` in the
/// dependency graph (architecture.md §3.1: "TallyDomain <- TallyCanvasAPI, TallyStore <-
/// TallySync"), and a grade-classification enum has no storage/encryption dependency of its
/// own, so this is a pure move, not a new coupling: `TallyStore` already `import`s
/// `TallyDomain` and simply reads `GradeBand` from there now.
public enum GradeBand: String, Codable, Sendable, CaseIterable, Equatable {
    case aRange = "a", bRange = "b", cRange = "c", dRange = "d", fRange = "f"
    case passing, failing, unknown

    public static func fromPercent(_ percent: Double) -> GradeBand {
        switch percent {
        case 90...: return .aRange
        case 80..<90: return .bRange
        case 70..<80: return .cRange
        case 60..<70: return .dRange
        default: return .fRange
        }
    }

    /// Best-effort mapping for courses that only expose a letter or pass/fail string.
    /// UNVERIFIED against every institution's grading scheme; unrecognised text maps to `.unknown`
    /// rather than guessing, so the glance never shows a misleading band.
    public static func from(letterOrPassFail raw: String) -> GradeBand {
        let s = raw.uppercased()
        if s.hasPrefix("A") { return .aRange }
        if s.hasPrefix("B") { return .bRange }
        if s.hasPrefix("C") { return .cRange }
        if s.hasPrefix("D") { return .dRange }
        if s.hasPrefix("F") { return .fRange }
        if s.contains("PASS") || s.contains("COMPLETE") { return .passing }
        if s.contains("FAIL") || s.contains("INCOMPLETE") { return .failing }
        return .unknown
    }
}
