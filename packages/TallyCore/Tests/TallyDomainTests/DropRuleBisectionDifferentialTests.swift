import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

/// R-2b (resilience.md): `DropRuleSelection` finds the root of big_f first and then walks the
/// bisection by comparisons, where it used to evaluate big_f (rate and sort every item) at each of
/// up to ~530 steps. The result must be the same, index for index, in the same order. This compares
/// it with `LegacyDropRuleSelection`, the pre-R-2b code kept verbatim, over:
/// - every assignment group of every grade fixture (personas and scenarios), under its own rules and
///   under added drop rules;
/// - a seeded random corpus built for ties, zero and negative scores, unpointed items, never-drop
///   items and fractional 17-digit values;
/// - groups at `GradeSanitizing`'s bounds (1e50 and 1e-6).
@Suite("DropRuleSelection: the root-first bisection matches the old one exactly (R-2b)", .timeLimit(.minutes(1)))
struct DropRuleBisectionDifferentialTests {
    typealias Candidate = DropRuleSelection.Candidate

    /// Every case in `core-test`; every `TestTimeBudget.scale`-th case on the sanitizer lanes, where
    /// the reference (big_f at every step) runs about 100x slower and the full corpora pass the
    /// suite's one-minute limit under ThreadSanitizer. The sample still spans every corpus and shape.
    private func mismatches(_ cases: [(items: [Candidate], rules: DropRules)]) -> [String] {
        let stride = max(1, Int(TestTimeBudget.scale.rounded()))
        return cases.enumerated().compactMap { index, testCase in
            guard index % stride == 0 else { return nil }
            let new = DropRuleSelection.keptIndices(testCase.items, rules: testCase.rules)
            let old = LegacyDropRuleSelection.keptIndices(testCase.items, rules: testCase.rules)
            guard new != old else { return nil }
            return "case \(index): new \(new), old \(old), rules \(testCase.rules), items \(testCase.items.map { ($0.score, $0.total) })"
        }
    }

    // MARK: - Fixtures

    private static func fixtureGroups() throws -> [[Candidate]] {
        var courses: [GradeFixtureCourse] = []
        for persona in Fixtures.personas { courses += try GradeFixtures.courses(persona: persona) }
        for name in GradeParityTests.scenarios { courses.append(try GradeFixtures.scenario(name)) }
        return courses.flatMap(\.groups).map { group in
            group.assignments.map { a in
                Candidate(assignmentID: a.id, score: GradeSanitizing.saneScore(a.submission?.score) ?? 0,
                          total: GradeSanitizing.sanePoints(a.pointsPossible) ?? 0)
            }
        }.filter { !$0.isEmpty }
    }

    @Test func everyFixtureGroupKeepsTheSameItems() throws {
        var cases: [(items: [Candidate], rules: DropRules)] = []
        for items in try Self.fixtureGroups() {
            for rules in [DropRules(dropLowest: 1), DropRules(dropHighest: 1), DropRules(dropLowest: 1, dropHighest: 1),
                          DropRules(dropLowest: 2, dropHighest: 1, neverDrop: [items[0].assignmentID])] {
                cases.append((items, rules))
            }
        }
        #expect(cases.count > 100)
        let bad = mismatches(cases)
        #expect(bad.isEmpty, "\(bad.count) of \(cases.count) differ, first: \(bad.first ?? "")")
    }

    // MARK: - Random corpus

    /// Values chosen for ties and sign changes: integers, halves, a few repeating decimals, zero,
    /// negative scores, and unpointed items.
    private static func randomCases(count: Int, seed: UInt64) -> [(items: [Candidate], rules: DropRules)] {
        var rng = SeededRandom(seed: seed)
        func pick<T>(_ values: [T]) -> T { values[Int(rng.next() % UInt64(values.count))] }
        let totals: [Double] = [0, 0, 1, 2, 4, 5, 10, 10, 10, 20, 25, 100, 0.5, 3.3333333333333335, 7.25, 1000]
        let scores: [Double] = [0, 0, 1, 2, 3, 5, 7.5, 8, 9, 10, 10, 12, 20, -1, -2.5, 0.1, 2.3333333333333335, 99.99, 1000]
        return (0..<count).map { _ in
            let n = 1 + Int(rng.next() % 24)
            // One in four groups repeats a few (score, total) pairs, which makes ties at the root.
            let palette = (0..<3).map { _ in (pick(scores), pick(totals)) }
            let items = (0..<n).map { i -> Candidate in
                let (score, total) = rng.next() % 4 == 0 ? pick(palette) : (pick(scores), pick(totals))
                return Candidate(assignmentID: CanvasID("a\(1_000 + i)"), score: score, total: total)
            }
            let neverDrop = items.filter { _ in rng.next() % 6 == 0 }.map(\.assignmentID)
            let rules = DropRules(dropLowest: Int(rng.next() % 4), dropHighest: Int(rng.next() % 3), neverDrop: neverDrop)
            return (items, rules)
        }
    }

    @Test(arguments: [1 as UInt64, 2, 3, 4])
    func aRandomCorpusKeepsTheSameItems(_ seed: UInt64) {
        let cases = Self.randomCases(count: 750, seed: seed)
        let bad = mismatches(cases)
        #expect(bad.isEmpty, "\(bad.count) of \(cases.count) differ, first: \(bad.first ?? "")")
    }

    // MARK: - At the bounds

    @Test func groupsAtTheSanitizedBoundsKeepTheSameItems() {
        let maximum = GradeSanitizing.maximumMagnitude
        let floor = GradeSanitizing.minimumMagnitude.nextUp // 1.0000000000000002e-06: 17 digits, scale -22
        var rng = SeededRandom(seed: 7)
        var cases: [(items: [Candidate], rules: DropRules)] = []
        for shape in 0..<24 {
            let n = 4 + shape % 9
            var items = (0..<n).map { i in
                Candidate(assignmentID: CanvasID("b\(i)"), score: Double(i % 10), total: 10)
            }
            switch shape % 4 {
            case 0: // crash-safety-2.md F-5's shape at the bounds
                items[0] = Candidate(assignmentID: "b0", score: 5, total: maximum)
                items[1] = Candidate(assignmentID: "b1", score: floor, total: floor)
            case 1: // the extreme ratios
                items[0] = Candidate(assignmentID: "b0", score: 0, total: maximum)
                items[1] = Candidate(assignmentID: "b1", score: maximum, total: floor)
                items[2] = Candidate(assignmentID: "b2", score: -maximum, total: floor)
            case 2: // unpointed items with large scores
                items[0] = Candidate(assignmentID: "b0", score: maximum, total: 0)
                items[1] = Candidate(assignmentID: "b1", score: 3, total: maximum)
            default: // random magnitudes across the whole range
                items = items.map { item in
                    let exponent = Double(rng.next() % 56) - 6
                    return Candidate(assignmentID: item.assignmentID, score: pow(10, exponent) * (rng.next() % 2 == 0 ? 1 : -1),
                                     total: rng.next() % 5 == 0 ? 0 : pow(10, Double(rng.next() % 56) - 6))
                }
            }
            cases.append((items, DropRules(dropLowest: 1, dropHighest: 1)))
            cases.append((items, DropRules(dropLowest: 2, neverDrop: [items[n - 1].assignmentID])))
        }
        let bad = mismatches(cases)
        #expect(bad.isEmpty, "\(bad.count) of \(cases.count) differ, first: \(bad.first ?? "")")
    }

    /// A negative total never reaches `DropRuleSelection` from `GradeEngine` (`sanePoints` drops
    /// it), and with one, big_f need not be monotone, so there is no root to find: the selection
    /// evaluates big_f at every step, exactly as before.
    @Test func negativeTotalsFallBackToTheOldBisection() {
        var rng = SeededRandom(seed: 11)
        let totals: [Double] = [-10, -1, 0, 5, 10, 20]
        let scores: [Double] = [-3, 0, 2, 5, 8, 10]
        let cases: [(items: [Candidate], rules: DropRules)] = (0..<200).map { _ in
            let n = 2 + Int(rng.next() % 10)
            let items = (0..<n).map { i in
                Candidate(assignmentID: CanvasID("n\(i)"), score: scores[Int(rng.next() % 6)], total: totals[Int(rng.next() % 6)])
            }
            return (items, DropRules(dropLowest: 1 + Int(rng.next() % 2), dropHighest: Int(rng.next() % 2)))
        }
        let bad = mismatches(cases)
        #expect(bad.isEmpty, "\(bad.count) of \(cases.count) differ, first: \(bad.first ?? "")")
    }

    /// Ties at the root decide by input order (a stable sort), and must still match: equal grades
    /// with different totals, equal items, and a never-drop item sharing the tie.
    @Test func tiesAtTheRootKeepTheSameItems() {
        let shapes: [[(Double, Double)]] = [
            [(1, 2), (2, 4), (3, 6), (4, 8), (1, 2)],
            [(10, 10), (10, 10), (10, 10), (5, 10)],
            [(0, 10), (0, 10), (0, 0), (0, 0), (10, 10)],
            [(5, 10), (10, 20), (0, 0), (5, 0), (2.5, 5)],
            [(-1, 10), (-2, 20), (0, 10), (1, 10), (-1, 10)],
        ]
        var cases: [(items: [Candidate], rules: DropRules)] = []
        for shape in shapes {
            let items = shape.enumerated().map { Candidate(assignmentID: CanvasID("t\($0.offset)"), score: $0.element.0, total: $0.element.1) }
            for rules in [DropRules(dropLowest: 1), DropRules(dropHighest: 1), DropRules(dropLowest: 1, dropHighest: 1),
                          DropRules(dropLowest: 2), DropRules(dropLowest: 1, neverDrop: [items[0].assignmentID])] {
                cases.append((items, rules))
            }
        }
        let bad = mismatches(cases)
        #expect(bad.isEmpty, "\(bad.count) of \(cases.count) differ, first: \(bad.first ?? "")")
    }

    /// A midpoint exactly on the root. 10/10, 0/10 and 5/20, drop lowest 1: grades span 0 to 1, so
    /// the first midpoint is 1/2, and the best two items give exactly 1/2 either way ({10/10, 0/10}
    /// or {10/10, 5/20}). big_f is 0 there, which the old loop treats as "not negative" and so moves
    /// q_low up, converging from above, where 0/10 outranks 5/20 (the smaller total loses less).
    /// Converging from below would keep 5/20 instead.
    @Test func aMidpointExactlyOnTheRootGoesTheSameWay() {
        let items = [(10.0, 10.0), (0, 10), (5, 20)].enumerated().map {
            Candidate(assignmentID: CanvasID("m\($0.offset)"), score: $0.element.0, total: $0.element.1)
        }
        let kept = DropRuleSelection.keptIndices(items, rules: DropRules(dropLowest: 1))
        #expect(kept == LegacyDropRuleSelection.keptIndices(items, rules: DropRules(dropLowest: 1)))
        #expect(kept == [0, 1], "10/10 and 0/10, the set just above the root")
    }
}
