import Foundation
import Testing
@testable import TallyDomain

// Case tags follow tools/canvas-synth/tests/test_gradecalc.py:
// HAND = computed by hand in the comment; JS = canvas-lms ui/shared/grading/__tests__
// (AssignmentGroupGradeCalculator / CourseGradeCalculator); RB = spec/lib/grade_calculator_spec.rb.

/// One assignment with the student's submission (test_gradecalc.py `course()` item).
private struct A {
    var id: Int
    var points: Double?
    var score: Double?
    var excused = false, hidden = false, pending = false, omit = false, noSubmission = false
    var period: String?
    init(_ id: Int, _ points: Double?, _ score: Double?, excused: Bool = false, hidden: Bool = false,
         pending: Bool = false, omit: Bool = false, noSubmission: Bool = false, period: String? = nil) {
        self.id = id; self.points = points; self.score = score; self.excused = excused; self.hidden = hidden
        self.pending = pending; self.omit = omit; self.noSubmission = noSubmission; self.period = period
    }
}

private struct G {
    var id: Int
    var weight: Double
    var rules = DropRules()
    var items: [A]
    init(_ id: Int, _ weight: Double, _ rules: DropRules, _ items: [A]) {
        self.id = id; self.weight = weight; self.rules = rules; self.items = items
    }
    init(_ id: Int, _ weight: Double, _ items: [A]) { self.init(id, weight, DropRules(), items) }
}

private func input(_ groups: [G], _ weighting: GradeInput.Weighting = .points,
                   periods: [GradeInput.Period] = [], weightedPeriods: Bool = false) -> GradeInput {
    GradeInput(
        weighting: weighting,
        groups: groups.map { GradeInput.Group(id: CanvasID("\($0.id)"), weight: $0.weight, rules: $0.rules) },
        items: groups.flatMap { g in
            g.items.map { a in
                GradeInput.Item(
                    id: CanvasID("\(a.id)"), groupID: CanvasID("\(g.id)"), pointsPossible: a.points,
                    omitFromFinalGrade: a.omit, gradingPeriodID: a.period.map { CanvasID($0) },
                    submission: a.noSubmission ? nil : GradeInput.ScoredSubmission(
                        id: CanvasID("\(9000 + a.id)"), score: a.score, excused: a.excused, posted: !a.hidden,
                        workflowState: a.pending ? "pending_review" : "graded"))
            }
        },
        periods: periods, hasWeightedGradingPeriods: weightedPeriods)
}

private func pair(_ i: GradeInput, unposted: Bool = false) -> [Double?] {
    let s = GradeEngine.scoreSet(i, gradingPeriodID: nil, ignoreUnposted: !unposted)
    return [s.currentScore, s.finalScore]
}

private func group(_ i: GradeInput, final: Bool = false, _ index: Int = 0) -> GroupScore {
    let s = GradeEngine.scoreSet(i, gradingPeriodID: nil, ignoreUnposted: true)
    return (final ? s.finalGroups : s.currentGroups)[index]
}

private func sums(_ g: GroupScore) -> [Decimal] { [g.score, g.possible] }

@Suite("GradeEngine numerics: Ruby rounding, shortest decimals, BigInt")
struct GradeNumericsTests {
    @Test func rubyFloatRoundRoundsTheDecimalLiteralHalfUp() {
        // RB "calculates the grade without floating point calculation errors": 93.825 -> 93.83.
        #expect(GradeEngine.rubyFloatRound(93.825) == 93.83)
        // 1.005 * 100 == 100.49999999999999, so the naive Swift rounding gives 1.0; Ruby gives 1.01.
        #expect((1.005 * 100).rounded() / 100 == 1.0)
        #expect(GradeEngine.rubyFloatRound(1.005) == 1.01)
        #expect(GradeEngine.rubyFloatRound(2.675) == 2.68)
        #expect(GradeEngine.rubyFloatRound(60.835) == 60.84)
        #expect(GradeEngine.rubyFloatRound(0.125) == 0.13)
        #expect(GradeEngine.rubyFloatRound(123456.785) == 123456.79)
        #expect(GradeEngine.rubyFloatRound(-93.825) == -93.83)
        #expect(GradeEngine.rubyFloatRound(-2.675) == -2.68)
        #expect(GradeEngine.rubyFloatRound(90.1) == 90.1)
        #expect(GradeEngine.rubyFloatRound(0.0) == 0.0)
        // frexp guards: overflow returns the number, underflow returns 0.0 (positive only).
        #expect(GradeEngine.rubyFloatRound(1e20) == 1e20)
        #expect(GradeEngine.rubyFloatRound(1e-20) == 0.0)
        #expect(GradeEngine.rubyFloatRound(Double.leastNonzeroMagnitude) == 0.0)
        let negativeTiny = GradeEngine.rubyFloatRound(-1e-20)
        #expect(negativeTiny == 0.0 && negativeTiny.sign == .minus)
    }

    @Test func bigDecimalRoundIsHalfUpOnTheExactDecimal() {
        #expect(RubyNumerics.roundHalfUp2(Decimal(string: "34.025")!) == Decimal(string: "34.03")!)
        #expect(RubyNumerics.roundHalfUp2(Decimal(string: "-34.025")!) == Decimal(string: "-34.03")!)
        #expect(RubyNumerics.roundHalfUp2(Decimal(string: "34.0249999")!) == Decimal(string: "34.02")!)
    }

    @Test func shortestDecimalIsTheRoundTripLiteral() {
        func parts(_ x: Double) -> [String] {
            let d = ShortestDecimal(x)
            return ["\(d.negative)", "\(d.significand)", "\(d.exponent)"]
        }
        #expect(parts(136.1) == ["false", "1361", "-1"])
        #expect(parts(1e50) == ["false", "1", "50"])
        #expect(parts(0.1 + 0.2) == ["false", "30000000000000004", "-17"])
        #expect(parts(-2.5e-7) == ["true", "25", "-8"])
        #expect(ShortestDecimal(-0.00001).decimal == Decimal(string: "-0.00001")!)
        #expect(RubyNumerics.decimal(0.0) == 0 && RubyNumerics.decimal(-0.0) == 0)
        #expect(RubyNumerics.double(Decimal(string: "93.40")!) == 93.4)
    }

    @Test func bigIntArithmetic() {
        let two = BigInt(2)
        var p = BigInt(1)
        for _ in 0..<100 { p = p * two }
        #expect(p.description == "1267650600228229401496703205376")
        #expect((BigInt.pow10(30) - BigInt(1)).description == "999999999999999999999999999999")
        #expect((BigInt(-7) * BigInt(6)).description == "-42")
        #expect(BigInt(5) + BigInt(-8) == BigInt(-3))
        #expect(BigInt(-5) - BigInt(-5) == BigInt(0) && BigInt(0).signum == 0)
        #expect(BigInt(-3) < BigInt(2) && BigInt(-3) < BigInt(-2) && !(BigInt(4) < BigInt(4)))
        #expect((BigInt(UInt64.max) + BigInt(1)).description == "18446744073709551616")
    }
}

@Suite("GradeEngine: group sums, weighting, posting")
struct GradeEngineTests {
    @Test func handPointsVersusWeighted() {
        // HAND points: (18 + 9) / (20 + 10) = 90.0
        #expect(pair(input([G(1, 0, [A(1, 20, 18)]), G(2, 0, [A(2, 10, 9)])])) == [90.0, 90.0])
        // HAND G1 18/20 = 90%, G2 3/10 = 30%. points: 21/30 = 70.0; percent 50/50: 45 + 15 = 60.0
        let work = [G(1, 50, [A(1, 20, 18)]), G(2, 50, [A(2, 10, 3)])]
        #expect(pair(input(work, .points)) == [70.0, 70.0])
        #expect(pair(input(work, .percent)) == [60.0, 60.0])
        // HAND weighted with an ungraded group: HW 54.5/60 x 40 + Q 85/100 x 35 = 66.0833 over 75 -> 88.11;
        // final adds 0 x 25 -> 66.08.
        let scaled = input([G(1, 40, [A(1, 20, 18), A(2, 10, 9), A(3, 30, 27.5)]),
                            G(2, 35, [A(4, 50, 41), A(5, 50, 44)]),
                            G(3, 25, [A(6, 100, nil)])], .percent)
        #expect(pair(scaled) == [88.11, 66.08])
    }

    @Test func unpostedIsAbsentForTheStudentAndCountsWhenUnposted() {
        // HAND: 80/100 posted, 40/100 hidden. current 80, final 80/200 = 40; unposted branch 120/200 = 60.
        let i = input([G(1, 0, [A(1, 100, 80), A(2, 100, 40, hidden: true)])])
        #expect(pair(i) == [80.0, 40.0])
        #expect(pair(i, unposted: true) == [60.0, 60.0])
        // HAND: an unposted excused submission is invisible, so final counts it as 0/10.
        #expect(pair(input([G(1, 0, [A(1, 10, 10), A(2, 10, nil, excused: true, hidden: true)])])) == [100.0, 50.0])
    }

    @Test func allExcused() {
        // HAND: every submission excused -> nothing possible -> no grade (never 0%).
        let excused = G(1, 60, [A(1, 10, nil, excused: true), A(2, 20, 5, excused: true)])
        #expect(pair(input([excused], .points)) == [nil, nil])
        #expect(pair(input([excused], .percent)) == [nil, nil])
        #expect(group(input([excused])).grade == nil)
        // HAND: the empty group drops out of the weights: 8/10 in the 40% group scales to 80.0.
        #expect(pair(input([excused, G(2, 40, [A(3, 10, 8)])], .percent)) == [80.0, 80.0])
    }

    @Test func zeroPointsPossible() {
        // JS unpointed scores count: (0 pts, 10) + (10 pts, 10) -> score 20.
        #expect(group(input([G(301, 0, [A(201, 0, 10), A(202, 10, 10)])])).score == 20)
        // HAND points: (5 + 8) / 10 = 130.0 (extra credit), even across groups.
        #expect(pair(input([G(1, 0, [A(1, 0, 5), A(2, 10, 8)])])) == [130.0, 130.0])
        #expect(pair(input([G(1, 50, [A(1, 0, 5)]), G(2, 50, [A(2, 10, 8)])], .points)) == [130.0, 130.0])
        // HAND percent: a group with 0 possible is ignored even with a score: 8/10 -> 80.0.
        let weighted = input([G(1, 50, [A(1, 0, 5)]), G(2, 50, [A(2, 10, 8)])], .percent)
        #expect(pair(weighted) == [80.0, 80.0])
        #expect(group(weighted).grade == nil && group(weighted).possible == 0)
        // HAND: only a 0-point ungraded item -> no grade.
        #expect(pair(input([G(1, 0, [A(1, 0, nil)])])) == [nil, nil])
    }

    @Test func pendingReviewOmittedUnpublishedAndNotGraded() {
        let base = [A(201, 100, 100), A(202, 91, 42), A(203, 55, 14), A(204, 38, 3), A(205, 1000, nil)]
        // JS adds scores and possible: 159/284; final 159/1284.
        #expect(sums(group(input([G(301, 0, base)]))) == [159, 284])
        #expect(sums(group(input([G(301, 0, base)]), final: true)) == [159, 1284])
        var pending = base; pending[1].pending = true
        #expect(sums(group(input([G(301, 0, pending)]))) == [117, 193])
        #expect(sums(group(input([G(301, 0, pending)]), final: true)) == [159, 1284])
        var hidden = base; hidden[1].hidden = true
        #expect(sums(group(input([G(301, 0, hidden)]), final: true)) == [117, 1284])   // Ruby: 0 of 91
        var excused = base; excused[1].excused = true
        #expect(sums(group(input([G(301, 0, excused)]), final: true)) == [117, 1193])
        var omitted = base; omitted[2].omit = true
        #expect(sums(group(input([G(301, 0, omitted)]))) == [145, 229])
        // RB not-graded assignment ignored; unpublished likewise.
        var notGraded = input([G(1, 0, [A(1, 10, 9), A(2, nil, 1)])])
        notGraded.items[1].isGradeable = false
        #expect(pair(notGraded) == [90.0, 90.0])
        var unpublished = input([G(1, 0, [A(1, 10, 9), A(2, 10, 1)])])
        unpublished.items[1].published = false
        #expect(pair(unpublished) == [90.0, 90.0])
    }

    @Test func completedEnrollmentIgnoresWorkWithoutASubmission() {
        // HAND: 8/10 graded, the other assignment has no submission row: final 8/20 = 40 while
        // active, 8/10 = 80 once the enrollment is completed.
        var i = input([G(1, 0, [A(1, 10, 8), A(2, 10, nil, noSubmission: true)])])
        #expect(pair(i) == [80.0, 40.0])
        i.enrollmentCompleted = true
        #expect(pair(i) == [80.0, 80.0])
    }

    @Test(arguments: [
        // JS course weighting variants over two groups (current, final).
        (50, 50, 46.31, 37.95), (5, 5, 46.31, 37.95), (100, 100, 92.63, 75.9),
        (75, 25, 60.33, 56.15), (33.33, 50, 40.7, 30.67),
    ] as [(Double, Double, Double, Double)])
    func jsWeightedVariants(_ w1: Double, _ w2: Double, _ current: Double, _ final: Double) {
        let i = input([G(301, w1, [A(201, 100, 100), A(202, 91, 42)]),
                       G(302, w2, [A(203, 55, 14), A(204, 38, 3), A(205, 1000, nil)])], .percent)
        #expect(pair(i) == [current, final])
    }

    @Test func rubySpecCourseTotals() {
        // RB irrational weights.
        let irrational: [(Double, Double, Double)] = [(12, 12, 11.8), (10, 82, 82), (15, 100, 89.5), (21, 100, 85), (21, 100, 85), (21, 100, 83)]
        let groups = irrational.enumerated().map { G($0.offset + 1, $0.element.0, [A($0.offset + 1, $0.element.1, $0.element.2)]) }
        #expect(pair(input(groups, .percent))[0] == 88.36)
        // RB weights under 100 precision; float errors (percent, points).
        #expect(pair(input([G(1, 9.9, [A(1, 100, 75)]), G(2, 23.1, [A(2, 100, 53.75)])], .percent))[0] == 60.13)
        #expect(pair(input([G(1, 50, [A(1, 200, 267.9)]), G(2, 50, [A(2, 100, 53.7)])], .percent))[0] == 93.83)
        #expect(pair(input([G(1, 0, [A(1, 100, 88.56), A(2, 100, 69.71)])]))[0] == 79.14)
        func two(_ a1: Double?, _ a2: Double?, _ w: (Double, Double) = (50, 50), _ m: GradeInput.Weighting = .percent) -> [Double?] {
            pair(input([G(1, w.0, [A(1, 10, a1)]), G(2, w.1, [A(2, 40, a2)])], m))
        }
        #expect(two(nil, nil, (50, 50), .points) == [nil, 0.0])
        #expect(two(9, nil, (50, 50), .points) == [90.0, 18.0])
        #expect(two(9, nil) == [90.0, 45.0])
        #expect(two(9, 20) == [70.0, 70.0])
        #expect(two(9, 20, (50, 50), .points) == [58.0, 58.0])
        // RB extra credit and total weight under 100.
        #expect(two(10, nil, (50, 60), .points) == [100.0, 20.0])
        #expect(two(10, 40, (50, 60)) == [110.0, 110.0])
        #expect(two(11, 45, (50, 60)) == [122.5, 122.5])
        #expect(two(10, nil, (50, 40)) == [100.0, 55.56])
    }
}

@Suite("GradeEngine: drop rules (Kane-and-Kane bisection)")
struct GradeEngineDropRuleTests {
    @Test func dropLowest() {
        let r = DropRules(dropLowest: 1)
        // JS drop lowest 1: drops 6/10 -> 48/64.
        let g1 = group(input([G(1, 0, r, [A(201, 40, 31), A(202, 24, 17), A(203, 10, 6)])]))
        #expect(sums(g1) == [48, 64] && g1.droppedSubmissionIDs == ["9203"])
        // JS: with 7/10 it drops 17/24 instead -> 38/50.
        #expect(sums(group(input([G(1, 0, r, [A(201, 40, 31), A(202, 24, 17), A(203, 10, 7)])]))) == [38, 50])
        // JS: drops a pointed item over an unpointed one.
        #expect(group(input([G(1, 0, r, [A(201, 0, 31), A(202, 24, 17), A(203, 10, 6)])])).score == 37)
        // JS: ungraded is not dropped from current; final drops the 0/10.
        let ungraded = input([G(1, 0, r, [A(201, 40, 31), A(202, 24, 17), A(203, 10, nil)])])
        #expect(group(ungraded).score == 31 && group(ungraded, final: true).score == 48)
        // JS drop lowest 2 and 4.
        let base = [A(201, 100, 100), A(202, 91, 42), A(203, 55, 14), A(204, 38, 3), A(205, 1000, nil)]
        let two = input([G(301, 0, DropRules(dropLowest: 2), base)])
        #expect(sums(group(two)) == [103, 138] && sums(group(two, final: true)) == [156, 246])
        let four = input([G(301, 0, DropRules(dropLowest: 4), base)])
        #expect(sums(group(four)) == [100, 100] && sums(group(four, final: true)) == [100, 100])
    }

    @Test func dropHighest() {
        let r = DropRules(dropHighest: 1)
        #expect(sums(group(input([G(1, 0, r, [A(201, 40, 31), A(202, 24, 17), A(203, 10, 6)])]))) == [23, 34])
        #expect(sums(group(input([G(1, 0, r, [A(201, 40, 31), A(202, 24, 17), A(203, 10, 10)])]))) == [48, 64])
        let ungraded = input([G(1, 0, r, [A(201, 40, nil), A(202, 24, 17), A(203, 10, 6)])])
        #expect(sums(group(ungraded)) == [6, 10] && group(ungraded, final: true).possible == 50)
    }

    @Test func neverDropWithDropLowestAndHighest() {
        // HAND drop lowest 1 over 4,9,8,10 (each /10), never_drop on the 4 -> drops the 8: 23/30.
        let low = group(input([G(1, 0, DropRules(dropLowest: 1, neverDrop: ["1"]), [A(1, 10, 4), A(2, 10, 9), A(3, 10, 8), A(4, 10, 10)])]))
        #expect(low.score == 23 && low.droppedSubmissionIDs == ["9003"])
        // HAND drop highest 1 over 10,9,8,4 (each /10), never_drop on the 10 -> drops the 9: 22/30 = 73.33.
        let high = group(input([G(1, 0, DropRules(dropHighest: 1, neverDrop: ["1"]), [A(1, 10, 10), A(2, 10, 9), A(3, 10, 8), A(4, 10, 4)])]))
        #expect(sums(high) == [22, 30] && high.grade == 73.33 && high.droppedSubmissionIDs == ["9002"])
        // HAND both, never_drop on the 4/10: keep-highest drops 11/20 (55%); keep-lowest then drops 10/10;
        // (9 + 8 + 4) / 30 = 70.0.
        let both = group(input([G(1, 0, DropRules(dropLowest: 1, dropHighest: 1, neverDrop: ["4"]),
                                   [A(1, 10, 10), A(2, 10, 9), A(3, 10, 8), A(4, 10, 4), A(5, 20, 11)])]))
        #expect(sums(both) == [21, 30] && both.grade == 70.0 && both.droppedSubmissionIDs == ["9001", "9005"])
    }

    @Test func tiesAndUnpointedAndRidiculousTotals() {
        // JS ties drop the highest id (stable sort over ascending ids).
        let tie = group(input([G(1, 0, DropRules(dropLowest: 1), [A(2301, 10, 10), A(2302, 10, 10), A(2303, 10, 10)])]))
        #expect(tie.score == 20 && tie.droppedSubmissionIDs == ["11303"])
        // JS all unpointed: drops the lowest score.
        let unpointed = group(input([G(1, 0, DropRules(dropLowest: 1), [A(2301, 0, 15), A(2302, 0, 5), A(2303, 0, 10)])]))
        #expect(unpointed.score == 25 && unpointed.droppedSubmissionIDs == ["11302"])
        // JS "ridiculous circumstances": a 1e50-point assignment (~340 exact bisection steps).
        let huge = input([G(1, 0, DropRules(dropLowest: 2), [A(201, 20, nil), A(202, 10, 3), A(203, 10, nil), A(204, 1e50, nil), A(205, nil, nil)])])
        #expect(sums(group(huge)) == [3, 10] && sums(group(huge, final: true)) == [3, 20])
    }
}

@Suite("GradeEngine: grading periods")
struct GradeEngineGradingPeriodTests {
    @Test func weightedGradingPeriodsCombineRoundedPeriodScores() {
        // HAND: period a 9/10 = 90; period b current 6/10 = 60, final 6/20 = 30.
        // Weighted 30/70: current 90*.3 + 60*.7 = 69.0; final 27 + 21 = 48.0. Unweighted: 15/20, 15/30.
        var i = input([G(1, 0, [A(1, 10, 9, period: "a"), A(2, 10, 6, period: "b"), A(3, 10, nil, period: "b")])],
                      periods: [GradeInput.Period(id: "a", weight: 30), GradeInput.Period(id: "b", weight: 70)],
                      weightedPeriods: true)
        let weighted = GradeEngine.scores(for: i)
        #expect(weighted.usesWeightedGradingPeriods)
        #expect([weighted.currentScore, weighted.finalScore] == [69.0, 48.0])
        #expect([weighted.period("a")?.posted.currentScore, weighted.period("a")?.posted.finalScore] == [90.0, 90.0])
        #expect([weighted.period("b")?.posted.currentScore, weighted.period("b")?.posted.finalScore] == [60.0, 30.0])
        i.hasWeightedGradingPeriods = false
        let plain = GradeEngine.scores(for: i)
        #expect([plain.currentScore, plain.finalScore] == [75.0, 50.0])
    }

    @Test func combinationScalesCurrentAndUsesRubyRounding() {
        // HAND: only period 1 has a current score -> scaled to 100; final 35.625 -> Float#round -> 35.63.
        let r = GradeEngine.combineWeightedGradingPeriods([(50.0, 71.25, 71.25), (50.0, nil, 0.0)])
        #expect(r.current == 71.25 && r.final == 35.63)
        let none = GradeEngine.combineWeightedGradingPeriods([(50.0, nil, 0.0), (50.0, nil, 0.0)])
        #expect(none.current == nil && none.final == 0.0)
    }

    private func jsPeriodCourse(_ weights: (Double?, Double?), _ weighting: GradeInput.Weighting = .percent) -> GradeInput {
        input([G(301, 60, [A(201, 10, 10, period: "701"), A(202, 10, 5, period: "701")]),
               G(302, 20, [A(203, 20, 12, period: "702")]),
               G(303, 20, [A(204, 40, 16, period: "702")])], weighting,
              periods: [GradeInput.Period(id: "701", weight: weights.0), GradeInput.Period(id: "702", weight: weights.1)],
              weightedPeriods: true)
    }

    @Test(arguments: [(50, 50, 62.5), (5, 5, 62.5), (100, 100, 125.0), (nil, 5, 50.0), (0, 0, 0.0), (25, 75, 56.25)]
          as [(Double?, Double?, Double)])
    func jsWeightedGradingPeriods(_ w1: Double?, _ w2: Double?, _ expected: Double) {
        let s = GradeEngine.scores(for: jsPeriodCourse((w1, w2)))
        #expect([s.currentScore, s.finalScore] == [expected, expected])
    }

    @Test func rubyCombinesRoundedPeriodScores() {
        // JS expects 60.83 (unrounded periods); Ruby combines stored 75.0 and 46.67 -> 60.835 -> 60.84.
        let s = GradeEngine.scores(for: jsPeriodCourse((50, 50), .points))
        #expect([s.currentScore, s.finalScore] == [60.84, 60.84])
    }

    @Test func currentPeriodUsesMinuteTruncatedHalfOpenRange() {
        let start = Date(timeIntervalSince1970: 1_789_999_980)   // a whole minute
        let end = start.addingTimeInterval(86_400 * 30)
        let p = GradingPeriod(id: "1", title: "Q1", startDate: start, endDate: end, closeDate: nil, weight: 50, isClosed: false)
        #expect(GradeEngine.currentGradingPeriod(in: [p], at: start.addingTimeInterval(59)) == nil)   // same minute as start
        #expect(GradeEngine.currentGradingPeriod(in: [p], at: start.addingTimeInterval(60))?.id == "1")
        #expect(GradeEngine.currentGradingPeriod(in: [p], at: end.addingTimeInterval(59))?.id == "1")  // end minute inclusive
        #expect(GradeEngine.currentGradingPeriod(in: [p], at: end.addingTimeInterval(60)) == nil)
    }
}
