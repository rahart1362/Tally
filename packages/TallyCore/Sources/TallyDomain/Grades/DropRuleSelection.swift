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
///
/// R-2b (resilience.md): the bisection visits exactly the midpoints it always did, but decides
/// each step by comparing the midpoint with big_f's root, found first by Dinkelbach's method, and
/// evaluates big_f (rate and sort every item) once, at the last midpoint, instead of at every one
/// of up to ~530 steps. `DropRuleBisectionDifferentialTests` holds it to the old code index for
/// index; within `GradeSanitizing`'s bounds the worst 50-item group went from 42.8-169.8 ms to
/// 1.8-6.7 ms per `GradeEngine.scores` call in release.
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
        keptIndicesCountingSteps(items, rules: rules).kept
    }

    /// R-5 (resilience.md): the most steps one bisection takes. Inside `GradeSanitizing`'s bounds
    /// (every magnitude at most 1e50, every non-zero total at least 1e-6) a bisection needs at most
    /// about log2(4 n^2 1e156) + 1 steps: 533 at n = 50, and under 650 for any group that fits in
    /// memory, so the cap never changes a result there. It ends the loop for input that bypasses
    /// the sanitizer (this type is internal and `GradeEngine`, its only caller, sanitizes), with
    /// big_f's set at the last midpoint reached, the best estimate so far, instead of running on.
    static let maxBisectionSteps = 1_024

    /// `keptIndices`, and the most steps either of its bisections took. Internal, for tests, which
    /// can also lower `maxBisectionSteps` to drive the cap.
    static func keptIndicesCountingSteps(_ items: [Candidate], rules: DropRules,
                                         maxBisectionSteps: Int = maxBisectionSteps) -> (kept: [Int], steps: Int) {
        // Negative counts are invalid Canvas input; clamping keeps the loop finite.
        var dropLowest = max(0, rules.dropLowest)
        var dropHighest = max(0, rules.dropHighest)
        if dropLowest == 0 && dropHighest == 0 { return (Array(items.indices), 0) }

        let neverDrop = Set(rules.neverDrop)
        let cantDrop = items.indices.filter { neverDrop.contains(items[$0].assignmentID) }
        var subs = items.indices.filter { !neverDrop.contains(items[$0].assignmentID) }
        if subs.isEmpty { return (cantDrop, 0) }

        if dropLowest >= subs.count { dropLowest = subs.count - 1 }
        // CS-07: `dropLowest + dropHighest >= subs.count`, rearranged. `dropHighest` is a raw
        // Canvas integer, so the sum overflowed (and trapped) past Int.max; the difference cannot,
        // since 0 <= dropLowest < subs.count. Same result for every sum that does not overflow.
        if dropHighest >= subs.count - dropLowest { dropHighest = 0 }
        let keepHighest = subs.count - dropLowest
        let keepLowest = keepHighest - dropHighest

        subs = stableSorted(subs) { items[$0].assignmentID < items[$1].assignmentID }

        let kept: [Int]
        var steps = 0
        if (cantDrop + subs).contains(where: { items[$0].total > 0 }) {
            let exact = Exact(items: items, indices: cantDrop + subs)
            // Every index in `subs + cantDrop` was just passed to `Exact.init` above, so
            // `total(_:)` never falls back to its `BigInt(0)` default here; `.max()` is over a
            // provably non-empty array (`subs` was checked non-empty above). Both fallbacks
            // exist only so a future bookkeeping bug degrades instead of crashing (CS-01/CS-06:
            // no force-unwrapping in shipping code).
            let maxTotal = (subs + cantDrop).map { exact.total($0) }.max() ?? BigInt(0)
            let highest = exact.keep(subs, cantDrop: cantDrop, keep: keepHighest, maxTotal: maxTotal, best: true,
                                     maxSteps: maxBisectionSteps)
            let lowest = exact.keep(highest.kept, cantDrop: cantDrop, keep: keepLowest, maxTotal: maxTotal, best: false,
                                    maxSteps: maxBisectionSteps)
            kept = lowest.kept
            steps = max(highest.steps, lowest.steps)
        } else {
            let ordered = stableSorted(subs) { items[$0].score < items[$1].score }
            kept = Array(Array(ordered.suffix(keepHighest)).prefix(keepLowest))
        }
        return (kept + cantDrop, steps)
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

    /// R-2b: Dinkelbach's method converges in a few rounds; past this many, `Exact.keep` falls
    /// back to evaluating big_f at every bisection step, as before R-2b, rather than trust it.
    static let maxRootIterations = 64

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
        /// Also returns how many bisection steps it took (R-5: at most `maxSteps`).
        func keep(_ subs: [Int], cantDrop: [Int], keep: Int, maxTotal: BigInt, best: Bool, maxSteps: Int) -> (kept: [Int], steps: Int) {
            if subs.count <= keep { return (subs, 0) }
            let both = subs + cantDrop
            let unpointed = both.filter { total($0).signum == 0 }
            let pointed = both.filter { total($0).signum != 0 }
            if pointed.isEmpty {
                // Canvas's "really dumb situation": keep_highest removed every pointed item.
                // (Unreachable in "highest" mode: the caller checked some total > 0.)
                let ordered = DropRuleSelection.stableSorted(unpointed) { items[$0].score < items[$1].score }
                return (keep > 0 ? Array(ordered.suffix(keep)) : [], 0)
            }

            let grades = pointed.map { Ratio(score($0), total($0)) }
            // `pointed` is non-empty (just checked above), so first/reduce never falls back to
            // `grades[0]` being wrong — this is `min`/`max` written without a force-unwrap.
            guard let firstGrade = grades.first else { return (subs, 0) } // unreachable; safe fallback
            let lowest = grades.dropFirst().reduce(firstGrade) { $1 < $0 ? $1 : $0 }
            let highestGrade = grades.dropFirst().reduce(firstGrade) { $0 < $1 ? $1 : $0 }
            let highest = estimateQHigh(pointed: pointed, unpointed: unpointed) ?? highestGrade

            // q values over one shared denominator `den`.
            var den = lowest.denominator * highest.denominator
            var qLow = lowest.numerator * highest.denominator
            var qHigh = highest.numerator * lowest.denominator
            var qMid = qLow + qHigh
            qLow = qLow + qLow; qHigh = qHigh + qHigh; den = den + den

            // q_high - q_low < 1 / (2 * keep * max_total^2). q is scale-free but max_total
            // = maxTotal * 10^scale, so: (qHigh - qLow) * 2*keep*maxTotal^2 * 10^(2*scale) < den.
            var lhsFactor = BigInt(2 * keep) * maxTotal * maxTotal
            var rhsFactor = BigInt(1)
            if scale >= 0 { lhsFactor = lhsFactor * BigInt.pow10(2 * scale) } else { rhsFactor = BigInt.pow10(-2 * scale) }
            // R-2b: a step keeps one half of the interval and then doubles qLow, qHigh and den, so
            // qHigh - qLow is the same at every check and den doubles. Both sides of the stopping
            // test are therefore known without multiplying at every step.
            let width = (qHigh - qLow) * lhsFactor
            var resolution = den * rhsFactor

            // R-2b (resilience.md): each step's direction is the sign of big_f at the midpoint, and
            // `root` knows that sign from one comparison. Without a root, big_f is evaluated at
            // every midpoint, as before. Either way the loop visits the same midpoints, and the
            // result is big_f's set at the last midpoint the loop evaluated (`lastMid`/`lastDen`).
            let root = self.root(subs: subs, cantDrop: cantDrop, keep: keep, best: best)
            var (x, kept) = root == nil ? bigF(qMid, den, subs: subs, cantDrop: cantDrop, keep: keep, best: best) : (BigInt(0), [])
            var (lastMid, lastDen) = (qMid, den)
            var steps = 0
            // R-5: `maxSteps` bounds the loop whatever the magnitudes; see `maxBisectionSteps`.
            while !(width < resolution), steps < maxSteps {
                steps += 1
                let atLeastZero = root.map { $0.admits(qMid, over: den) } ?? (x.signum >= 0)
                if atLeastZero { qLow = qMid } else { qHigh = qMid }
                qMid = qLow + qHigh
                qLow = qLow + qLow; qHigh = qHigh + qHigh; den = den + den; resolution = resolution + resolution
                if qMid == qHigh || qMid == qLow { break }
                (lastMid, lastDen) = (qMid, den)
                if root == nil { (x, kept) = bigF(qMid, den, subs: subs, cantDrop: cantDrop, keep: keep, best: best) }
            }
            if root != nil { kept = bigF(lastMid, lastDen, subs: subs, cantDrop: cantDrop, keep: keep, best: best).1 }
            return (kept, steps)
        }

        /// Where big_f changes sign (R-2b). big_f at q is `den` times F(q): the largest (best) or
        /// smallest sum of `score - q * total` over `keep` of `subs`, plus every never-drop item.
        /// Every total is at least 0, so F is continuous and non-increasing, and F(q) >= 0 exactly
        /// when q <= q* = sup { q : F(q) >= 0 }. `below` and `above` are q* = -inf and +inf.
        enum Root {
            case below
            case at(Ratio)
            case above

            /// Whether F(`qNum` / `den`) >= 0, that is `qNum` / `den` <= q*. `den` > 0.
            func admits(_ qNum: BigInt, over den: BigInt) -> Bool {
                switch self {
                case .below: false
                case .above: true
                // qNum / den <= n / d, both denominators positive.
                case .at(let root): !(root.numerator * den < qNum * root.denominator)
                }
            }
        }

        /// q*, by Dinkelbach's method on big_f's own choice of set, or nil when that does not
        /// apply: a negative total (F would not be monotone), or no convergence within
        /// `DropRuleSelection.maxRootIterations` (the caller then evaluates every midpoint).
        ///
        /// Every set S of `keep` subs gives a line L_S(q) = A_S - q * B_S (sums of scores and totals
        /// over S and the never-drop items), and F is the max (best) or min of those lines. Hence
        /// q* is the max (best) or min over S of A_S / B_S, where a set without points (B_S = 0)
        /// counts as +inf when A_S >= 0 and -inf otherwise.
        /// - Sets without points only exist when no never-drop item has points; they are settled
        ///   first: the best of them (for best) with A_S >= 0 makes q* = +inf, the worst (otherwise)
        ///   with A_S < 0 makes q* = -inf.
        /// - Otherwise, from any set with points and q = A/B: big_f's set T at q has
        ///   L_T(q) = F(q), which is 0 exactly when q = q*; if not, T has points and A_T / B_T is
        ///   strictly nearer q*. There are finitely many sets, so this ends, in practice after a
        ///   few rounds.
        private func root(subs: [Int], cantDrop: [Int], keep: Int, best: Bool) -> Root? {
            guard (subs + cantDrop).allSatisfy({ total($0).signum >= 0 }) else { return nil }
            if cantDrop.allSatisfy({ total($0).signum == 0 }) {
                let pointless = subs.filter { total($0).signum == 0 }
                if pointless.count >= keep {
                    let extreme = pointless.map { score($0) }.sorted { best ? $1 < $0 : $0 < $1 }.prefix(keep)
                    let sum = extreme.reduce(cantDrop.reduce(BigInt(0)) { $0 + score($1) }, +)
                    if best && sum.signum >= 0 { return .above }
                    if !best && sum.signum < 0 { return .below }
                }
            }
            // A first set with points: the `keep` subs with the most points.
            let start = Array(DropRuleSelection.stableSorted(subs) { total($1) < total($0) }.prefix(keep))
            var (a, b) = sums(start + cantDrop)
            for _ in 0..<DropRuleSelection.maxRootIterations {
                guard b.signum > 0 else { return nil } // unreachable after the checks above; stay exact
                let q = Ratio(a, b)
                let (x, set) = bigF(q.numerator, q.denominator, subs: subs, cantDrop: cantDrop, keep: keep, best: best)
                if x.signum == 0 { return .at(q) }
                (a, b) = sums(set + cantDrop)
            }
            return nil
        }

        /// The sums of scores and of totals over `indices`.
        private func sums(_ indices: [Int]) -> (score: BigInt, total: BigInt) {
            indices.reduce((BigInt(0), BigInt(0))) { ($0.0 + score($1), $0.1 + total($1)) }
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
