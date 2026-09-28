import Foundation
import TallyDomain

/// R-2 (resilience.md): the most expensive `GradeEngine.scores` inputs found inside
/// `GradeSanitizing`'s bounds. Each is one group of 50 items with drop lowest 1 and drop highest 1,
/// holding the largest valid magnitude (1e50) and a value just above the floor with a 17-digit
/// shortest representation (1.0000000000000002e-06), which pushes the exact-rational scale down to
/// 10^-22. The debug hang detector (`BoundedGradeInputTests`) and the release gate
/// (`TallyPerfTests`) time the same inputs.
public enum BoundedGradeWorstCase: String, CaseIterable, Sendable, CustomStringConvertible {
    /// crash-safety-2.md F-5's shape at the bounds: scores 0-9 out of 10, one item worth 1e50
    /// points, one worth the floor.
    case f5Shape
    /// Scores of +1e50 and -1e50 over floor-sized points, and a 1e50-point item: the widest
    /// interval and the most steps the bisection can need at n = 50.
    case extremeRatios
    /// `extremeRatios` inside a grading period: `GradeEngine` computes the period's scores as well
    /// as the course's, so it bisects twice as often.
    case extremeRatiosInAPeriod
    /// 50 items with random 17-digit points and scores across the whole valid range, plus the
    /// extremes.
    case dense
    /// `dense` with ten unpointed items holding large scores, which moves the bisection's upper
    /// bound to canvas-lms's `estimate_q_high`.
    case denseWithUnpointed
    /// 50 items with random 17-digit points and scores between 1e49 and 1e50, plus the extremes:
    /// the largest numbers at every step.
    case nearMaximum

    public var description: String { rawValue }

    public static let itemCount = 50

    public var input: GradeInput {
        let maximum = GradeSanitizing.maximumMagnitude
        let floor = GradeSanitizing.minimumMagnitude.nextUp
        let n = Self.itemCount
        var rows: [(score: Double?, points: Double?)] = (0..<n).map { (Double($0 % 10), 10) }
        var rng = SeededRandom(seed: 42)
        switch self {
        case .f5Shape:
            rows[n - 2] = (5, maximum)
            rows[n - 1] = (floor, floor)
        case .extremeRatios, .extremeRatiosInAPeriod:
            rows[0] = (0, maximum)
            rows[1] = (maximum, floor)
            rows[2] = (-maximum, floor)
        case .dense, .denseWithUnpointed, .nearMaximum:
            let low = self == .nearMaximum ? maximum / 10 : floor
            rows = rows.map { _ in
                let score = Self.longest(Self.logUniform(low, maximum, &rng)) * (rng.next() % 2 == 0 ? 1 : -1)
                return (score, Self.longest(Self.logUniform(low, maximum, &rng)))
            }
            rows[0] = (0, maximum)
            rows[1] = (maximum, floor)
            rows[2] = (-maximum, floor)
            if self == .denseWithUnpointed {
                for i in 3..<13 { rows[i] = (Self.longest(Self.logUniform(floor, maximum, &rng)), 0) }
            }
        }
        let inPeriod = self == .extremeRatiosInAPeriod
        return GradeInput(
            weighting: .points,
            groups: [.init(id: "g1", weight: 100, rules: DropRules(dropLowest: 1, dropHighest: 1))],
            items: rows.enumerated().map { index, row in
                GradeInput.Item(id: CanvasID("w\(1_000 + index)"), groupID: "g1", pointsPossible: row.points,
                                gradingPeriodID: inPeriod ? "p1" : nil, submission: .init(score: row.score))
            },
            periods: inPeriod ? [.init(id: "p1", weight: 100)] : [])
    }

    private static func logUniform(_ low: Double, _ high: Double, _ rng: inout SeededRandom) -> Double {
        let t = Double(rng.next() % 1_000_000) / 1_000_000
        return min(max(pow(10, log10(low) + t * (log10(high) - log10(low))), low), high)
    }

    /// Among `x` and the 31 doubles above it (capped at 1e50), the one whose shortest
    /// representation has the most digits: 17 where that binade has any, else 16.
    private static func longest(_ x: Double) -> Double {
        var best = x
        var candidate = x
        for _ in 0..<32 where candidate <= GradeSanitizing.maximumMagnitude {
            if digits(candidate) > digits(best) { best = candidate }
            candidate = candidate.nextUp
        }
        return best
    }

    private static func digits(_ x: Double) -> Int {
        var text = Substring(x.magnitude.description)
        if let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) { text = text[..<e] }
        return text.filter { $0 != "." }.drop(while: { $0 == "0" }).count
    }
}
