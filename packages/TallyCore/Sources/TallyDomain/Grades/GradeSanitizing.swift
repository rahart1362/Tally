import Foundation

/// CS-03/CS-05 (crash-safety.md): the one place Canvas-provided numeric grade inputs are
/// sanitized before they can reach `GradeNumerics`/`DropRuleSelection`/`GradeEngine`/
/// `PriorityScore`. Applied both at the DTO-to-domain-model mapping boundary and again at
/// `GradeEngine`'s own entry point (which "what-if" callers can also reach directly, bypassing
/// any mapper — see `GradeInput`'s doc comment), so every consumer sees only bounded values
/// without each having to re-check the invariant itself.
///
/// Why this exists: `GradeNumerics.ShortestDecimal.init` has a documented
/// `precondition(value.isFinite)`, reachable from a Canvas `points_possible`/`score`/`weight`
/// of `.infinity` (a real decode result: a JSON literal like `1e400` overflows to `+inf`, not a
/// decode error) or `.nan`.
///
/// R-2 (resilience.md, PMO ruling D2(a)): magnitudes are bounded too. `DropRuleSelection`
/// bisects with exact rationals whose step count and size grow with the spread of magnitudes in
/// a drop-rule group, so one `GradeEngine.scores` call on one 50-item group with 1e300 and
/// 1e-300 in it took 39 s in a debug build and 2.4 s in release (crash-safety-2.md F-5 measured
/// up to 106 s), and `GoalSeek` makes about 62 such calls. Within the bounds, and with R-2b's
/// root-first bisection, the worst such call measured 58 ms in debug and 6.7 ms in release. So:
/// - a magnitude above `maximumMagnitude` (1e50) is invalid and handled like a non-finite value:
///   dropped (`nil`), or 0 for a weight;
/// - a non-zero magnitude below `minimumMagnitude` becomes 0.
///
/// 1e50 itself stays valid: it is canvas-lms's own "ridiculous circumstances" spec value, and
/// `GradeEngineTests.tiesAndUnpointedAndRidiculousTotals` asserts a correct answer for it. Both
/// bounds also keep every value inside Foundation `Decimal`'s exponent range (-128...127), which
/// the Ruby-parity rounding in `RubyNumerics` goes through.
public enum GradeSanitizing {
    /// R-2: the largest valid magnitude of a grade input: canvas-lms's "ridiculous
    /// circumstances" spec value, which must still compute correctly.
    public static let maximumMagnitude: Double = 1e50

    /// R-2: the smallest non-zero magnitude a grade input keeps; a smaller one becomes 0.
    ///
    /// Why 1e-6 (resilience.md §R-2): it is far below any real Canvas score, points or weight,
    /// and a larger floor buys almost nothing. The drop-rule bisection's cost is set by the 1e50
    /// ceiling (its square alone is about 332 bits of the step count): on the same 50-item worst
    /// cases, a floor of 1 instead of 1e-6 saved only 9-15% of the time before R-2b and 6-9% after
    /// it. A floor at 1e-6 still bounds the decimal exponent of every value at -22, and keeps a
    /// residue such as 1e-17 from dragging the exact-rational scale down to it.
    public static let minimumMagnitude: Double = 1e-6

    /// `points_possible`: never negative, finite and at most `maximumMagnitude`. Returns `nil`
    /// (dropped) otherwise, exactly like an absent value — every caller here already treats a
    /// `nil` `pointsPossible` as "not counted" or "0". A non-zero value below `minimumMagnitude`
    /// becomes 0.
    public static func sanePoints(_ value: Double?) -> Double? {
        guard let value, value >= 0, let bounded = bounded(value) else { return nil }
        return bounded
    }

    /// A submission `score`: finite and at most `maximumMagnitude` either way (Canvas allows small
    /// negative scores from manual point adjustments, so unlike `sanePoints` this does not floor
    /// at 0). A non-zero magnitude below `minimumMagnitude` becomes 0.
    public static func saneScore(_ value: Double?) -> Double? {
        value.flatMap(bounded)
    }

    /// An assignment-group or grading-period `weight` (a percent, nominally 0...100, but read
    /// defensively since Canvas does not itself bound it in the response schema). Bounded like a
    /// score.
    public static func saneWeight(_ value: Double?) -> Double? {
        value.flatMap(bounded)
    }

    /// Like `saneWeight`, but for call sites that store a non-optional `Double` (`GradeInput.Group.weight`):
    /// an invalid weight degrades to "unweighted" (0) rather than being droppable.
    public static func saneWeightOrZero(_ value: Double) -> Double {
        bounded(value) ?? 0
    }

    /// `nil` for a non-finite value or a magnitude past `maximumMagnitude`; 0 for a non-zero
    /// magnitude below `minimumMagnitude`; otherwise `value` unchanged (so `-0.0` stays `-0.0`).
    private static func bounded(_ value: Double) -> Double? {
        guard value.isFinite, value.magnitude <= maximumMagnitude else { return nil }
        return value != 0 && value.magnitude < minimumMagnitude ? 0 : value
    }
}
