import Foundation

/// CS-03/CS-05 (crash-safety.md): the one place Canvas-provided numeric grade inputs are
/// sanitized before they can reach `GradeNumerics`/`DropRuleSelection`/`GradeEngine`/
/// `PriorityScore`. Applied both at the DTO-to-domain-model mapping boundary and again at
/// `GradeEngine`'s own entry point (which "what-if" callers can also reach directly, bypassing
/// any mapper — see `GradeInput`'s doc comment), so every consumer sees only finite values
/// without each having to re-check the invariant itself.
///
/// Why this exists: `GradeNumerics.ShortestDecimal.init` has a documented
/// `precondition(value.isFinite)`, reachable from a Canvas `points_possible`/`score`/`weight`
/// of `.infinity` (a real decode result: a JSON literal like `1e400` overflows to `+inf`, not a
/// decode error) or `.nan`. This guard rejects exactly that and nothing else.
///
/// Deliberately **not** a magnitude cap. `DropRuleSelection`'s exact-rational bisection needs
/// roughly one more step per doubling of the largest `points_possible` (~340 steps at 1e50
/// points, per its own doc comment, and canvas-lms's own "ridiculous circumstances" JS spec
/// value — see `GradeEngineTests.tiesAndUnpointedAndRidiculousTotals`, which asserts a
/// *correct*, not just crash-free, answer at 1e50). A magnitude cap would have to sit below
/// that to matter, which would silently make a spec-compliant input wrong. But the step count
/// is bounded by `Double`'s own exponent range regardless: even at `Double.greatestFiniteMagnitude`
/// (~1.8e308) it tops out around ~2046 steps (confirmed fast in
/// `CrashSafetyGuardsTests.hugeButFinitePointsPossibleStaysBounded`) — so no finite value is
/// actually a time bomb. Only non-finite input is.
public enum GradeSanitizing {
    /// `points_possible`: never negative, always finite. Returns `nil` (dropped) otherwise,
    /// exactly like an absent value — every caller here already treats a `nil` `pointsPossible`
    /// as "not counted" or "0".
    public static func sanePoints(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// A submission `score`: finite (Canvas allows small negative scores from manual point
    /// adjustments, so unlike `sanePoints` this does not floor at 0).
    public static func saneScore(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    /// An assignment-group or grading-period `weight` (a percent, nominally 0...100, but read
    /// defensively since Canvas does not itself bound it in the response schema).
    public static func saneWeight(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    /// Like `saneWeight`, but for call sites that store a non-optional `Double` (`GradeInput.Group.weight`):
    /// a non-finite weight degrades to "unweighted" (0) rather than being droppable.
    public static func saneWeightOrZero(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }
}
