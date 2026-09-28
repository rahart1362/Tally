import Foundation

/// Canvas's drop-rule selection (GradeCalculator#drop_assignments, keep_helper,
/// big_f, estimate_q_high: the Kane-and-Kane bisection), ported from
/// gradecalc.py `drop_assignments` and helpers.
///
/// Numeric choice: **exact rationals over `BigInt`**, as the Python port uses
/// `Fraction`. Every score and total is its exact shortest decimal, scaled by a
/// common power of ten to an integer, so `score - q * total` and every comparison
/// is exact integer arithmetic. The bisection keeps q_low, q_high and q_mid over
/// one shared denominator that doubles each step (numerators grow one bit per
/// step), so no division or gcd is needed. `Double` was rejected because the
/// selection is a sign/ordering decision near ties, and `Int64`/`Int128` because
/// the threshold 1/(2*keep*max_total^2) needs ~340 steps for a 1e50-point
/// assignment (canvas-lms JS spec "ridiculous circumstances").
///
/// Ties: Ruby's `Array#sort` is unstable; like the Python port, every sort here is
/// stable (equal keys keep their input order), which matches the canvas-lms JS specs.
enum DropRuleSelection {
    struct Candidate: Sendable {
        let assignmentID: CanvasID<Assignment>
        /// The submission score, 0 when ungraded (final grade).
        let score: Double
        /// `points_possible`, 0 when absent.
        let total: Double
    }

    /// Indices of the candidates that count, in gradecalc.py order (kept, then
    /// never-drop). An index can repeat in Canvas's all-unpointed corner case;
    /// the caller sums over this list exactly as the Ruby code does.
    static func keptIndices(_ items: [Candidate], rules: DropRules) -> [Int] {
        // Negative counts are invalid Canvas input; clamping keeps the loop finite.
        var dropLowest = max(0, rules.dropLowest)
        var dropHighest = max(0, rules.dropHighest)
        if dropLowest == 0 && dropHighest == 0 { return Array(items.indices) }

        let neverDrop = Set(rules.neverDrop)
        let cantDrop = items.indices.filter { neverDrop.contains(items[$0].assignmentID) }
        var subs = items.indices.filter { !neverDrop.contains(items[$0].assignmentID) }
        if subs.isEmpty { return cantDrop }

        if dropLowest >= subs.count { dropLowest = subs.count - 1 }
        if dropLowest + dropHighest >= subs.count { dropHighest = 0 }
        let keepHighest = subs.count - dropLowest
        let keepLowest = keepHighest - dropHighest

        subs = stableSorted(subs) { items[$0].assignmentID < items[$1].assignmentID }

        let kept: [Int]
        if (cantDrop + subs).contains(where: { items[$0].total > 0 }) {
            let exact = Exact(items: items, indices: cantDrop + subs)
            // Every index in `subs + cantDrop` was just passed to `Exact.init` above, so
            // `total(_:)` never falls back to its `BigInt(0)` default here; `.max()` is over a
            // provably non-empty array (`subs` was checked non-empty above). Both fallbacks
            // exist only so a future bookkeeping bug degrades instead of crashing (CS-01/CS-06:
            // no force-unwrapping in shipping code).
            let maxTotal = (subs + cantDrop).map { exact.total($0) }.max() ?? BigInt(0)
            let highest = exact.keep(subs, cantDrop: cantDrop, keep: keepHighest, maxTotal: maxTotal, best: true)
            kept = exact.keep(highest, cantDrop: cantDrop, keep: keepLowest, maxTotal: maxTotal, best: false)
        } else {
            let ordered = stableSorted(subs) { items[$0].score < items[$1].score }
            kept = Array(Array(ordered.suffix(keepHighest)).prefix(keepLowest))
        }
        return kept + cantDrop
    }

    /// Python `sorted(key=...)`: equal keys keep their input order.
    static func stableSorted(_ indices: [Int], by less: (Int, Int) -> Bool) -> [Int] {
        indices.enumerated()
            .sorted { a, b in
                if less(a.element, b.element) { return true }
                if less(b.element, a.element) { return false }
                return a.offset < b.offset
            }
            .map(\.element)
    }

    /// A non-negative-denominator fraction of `BigInt`s (never reduced).
    private struct Ratio {
        let numerator: BigInt
        let denominator: BigInt   // > 0

        init(_ numerator: BigInt, _ denominator: BigInt) {
            if denominator.signum < 0 { self.numerator = -numerator; self.denominator = -denominator }
            else { self.numerator = numerator; self.denominator = denominator }
        }

        static func < (a: Ratio, b: Ratio) -> Bool { a.numerator * b.denominator < b.numerator * a.denominator }
    }

    /// Candidates' scores and totals as exact integers sharing one power-of-ten scale.
    private struct Exact {
        let items: [Candidate]
        /// Every value below is its exact decimal x 10^(-scale).
        let scale: Int
        let score: [Int: BigInt]
        let total: [Int: BigInt]

        init(items: [Candidate], indices: [Int]) {
            self.items = items
            let parsed = indices.map { (i: $0, score: ShortestDecimal(items[$0].score), total: ShortestDecimal(items[$0].total)) }
            let scale = parsed.flatMap { [$0.score, $0.total] }.filter { $0.significand != 0 }.map(\.exponent).min() ?? 0
            self.scale = scale
            var score: [Int: BigInt] = [:], total: [Int: BigInt] = [:]
            for p in parsed {
                score[p.i] = p.score.scaled(to: scale)
                total[p.i] = p.total.scaled(to: scale)
            }
            self.score = score
            self.total = total
        }

        /// Safe accessors for `score`/`total`: every real call site only ever indexes a set of
        /// indices this `Exact` was itself built from (CS-01/CS-06: no force-unwrapping in
        /// shipping code). `BigInt(0)` is a neutral, never-crashing fallback if that invariant
        /// is ever violated by a future change — covered by the CS-03 fuzz suite.
        func score(_ i: Int) -> BigInt { score[i] ?? BigInt(0) }
        func total(_ i: Int) -> BigInt { total[i] ?? BigInt(0) }

        /// gradecalc.py `_keep_helper`: keeps `keep` of `subs` (best: highest), never-drop items fixed.
        func keep(_ subs: [Int], cantDrop: [Int], keep: Int, maxTotal: BigInt, best: Bool) -> [Int] {
            if subs.count <= keep { return subs }
            let both = subs + cantDrop
            let unpointed = both.filter { total($0).signum == 0 }
            let pointed = both.filter { total($0).signum != 0 }
            if pointed.isEmpty {
                // Canvas's "really dumb situation": keep_highest removed every pointed item.
                // (Unreachable in "highest" mode: the caller checked some total > 0.)
                let ordered = DropRuleSelection.stableSorted(unpointed) { items[$0].score < items[$1].score }
                return keep > 0 ? Array(ordered.suffix(keep)) : []
            }

            let grades = pointed.map { Ratio(score($0), total($0)) }
            // `pointed` is non-empty (just checked above), so first/reduce never falls back to
            // `grades[0]` being wrong — this is `min`/`max` written without a force-unwrap.
            guard let firstGrade = grades.first else { return subs } // unreachable; safe fallback
            let lowest = grades.dropFirst().reduce(firstGrade) { $1 < $0 ? $1 : $0 }
            let highestGrade = grades.dropFirst().reduce(firstGrade) { $0 < $1 ? $1 : $0 }
            let highest = estimateQHigh(pointed: pointed, unpointed: unpointed) ?? highestGrade

            // q values over one shared denominator `den`.
            var den = lowest.denominator * highest.denominator
            var qLow = lowest.numerator * highest.denominator
            var qHigh = highest.numerator * lowest.denominator
            var qMid = qLow + qHigh
            qLow = qLow + qLow; qHigh = qHigh + qHigh; den = den + den
            var (x, kept) = bigF(qMid, den, subs: subs, cantDrop: cantDrop, keep: keep, best: best)

            // q_high - q_low < 1 / (2 * keep * max_total^2). q is scale-free but max_total
            // = maxTotal * 10^scale, so: (qHigh - qLow) * 2*keep*maxTotal^2 * 10^(2*scale) < den.
            var lhsFactor = BigInt(2 * keep) * maxTotal * maxTotal
            var rhsFactor = BigInt(1)
            if scale >= 0 { lhsFactor = lhsFactor * BigInt.pow10(2 * scale) } else { rhsFactor = BigInt.pow10(-2 * scale) }
            while !((qHigh - qLow) * lhsFactor < den * rhsFactor) {
                if x.signum < 0 { qHigh = qMid } else { qLow = qMid }
                qMid = qLow + qHigh
                qLow = qLow + qLow; qHigh = qHigh + qHigh; den = den + den
                if qMid == qHigh || qMid == qLow { break }
                (x, kept) = bigF(qMid, den, subs: subs, cantDrop: cantDrop, keep: keep, best: best)
            }
            return kept
        }

        /// gradecalc.py `_estimate_q_high` for the unpointed case; nil means "use the highest grade".
        private func estimateQHigh(pointed: [Int], unpointed: [Int]) -> Ratio? {
            guard !unpointed.isEmpty else { return nil }
            let pointsPossible = pointed.reduce(BigInt(0)) { $0 + total($1) }
            let pointedScore = pointed.reduce(BigInt(0)) { $0 + score($1) }
            let unpointedScore = unpointed.reduce(BigInt(0)) { $0 + score($1) }
            guard pointsPossible.signum != 0 else { return nil }   // only with negative totals
            return Ratio(max(pointsPossible, pointedScore) + unpointedScore, pointsPossible)
        }

        /// gradecalc.py `_big_f` at q = qNum/den. Ratings `score - q*total` share the
        /// positive factor 10^scale/den, so their numerators order and sum exactly.
        private func bigF(_ qNum: BigInt, _ den: BigInt, subs: [Int], cantDrop: [Int], keep: Int, best: Bool)
            -> (BigInt, [Int]) {
            func rating(_ i: Int) -> BigInt { score(i) * den - qNum * total(i) }
            let rated = subs.map(rating)
            let order = DropRuleSelection.stableSorted(Array(subs.indices)) { a, b in
                best ? rated[b] < rated[a] : rated[a] < rated[b]
            }.prefix(keep)
            let x = order.reduce(BigInt(0)) { $0 + rated[$1] } + cantDrop.reduce(BigInt(0)) { $0 + rating($1) }
            return (x, order.map { subs[$0] })
        }
    }
}
