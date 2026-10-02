import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

/// Plan 08 XG-06: the what-if for a course whose grades are kept outside Canvas. The estimate is
/// the engine's (`GradeEngine` through `WhatIfSimulator`) over an input that holds only the
/// student's scores, weighted by Canvas's own rule or by the categories' weights the student set.
/// Hand-built inputs, so every expected value is worked out by hand in the comments.
@Suite("XG-06: the estimate for a course whose grades are kept outside Canvas")
struct OutsideCanvasEstimateTests {
    /// Two categories counted by points (Canvas's rule when groups are not weighted): Homework (two
    /// 10-point items, one graded 8 in Canvas) and Tests (one 100-point item, graded 90 in Canvas),
    /// plus an empty category, a category of zero-point items, an unpublished and an omitted item,
    /// and two grading periods.
    static func pointsCourse(weighting: GradeInput.Weighting = .points,
                             weights: (homework: Double, tests: Double, empty: Double, zero: Double) = (0, 0, 0, 0))
        -> GradeInput {
        GradeInput(
            weighting: weighting,
            groups: [
                .init(id: "hw", weight: weights.homework, rules: DropRules(dropLowest: 0)),
                .init(id: "tests", weight: weights.tests),
                .init(id: "empty", weight: weights.empty),
                .init(id: "zero", weight: weights.zero),
            ],
            items: [
                .init(id: "hw1", groupID: "hw", pointsPossible: 10, gradingPeriodID: "p1",
                      submission: .init(id: "s1", score: 8, posted: true, workflowState: "graded")),
                .init(id: "hw2", groupID: "hw", pointsPossible: 10, submission: nil),
                .init(id: "t1", groupID: "tests", pointsPossible: 100, gradingPeriodID: "p2",
                      submission: .init(id: "s2", score: 90, posted: true, workflowState: "graded")),
                .init(id: "z1", groupID: "zero", pointsPossible: 0, submission: nil),
                .init(id: "draft", groupID: "tests", pointsPossible: 500, published: false, submission: nil),
                .init(id: "omitted", groupID: "tests", pointsPossible: 500, omitFromFinalGrade: true, submission: nil),
            ],
            periods: [.init(id: "p1", weight: 50), .init(id: "p2", weight: 50)],
            hasWeightedGradingPeriods: true)
    }

    static func estimate(_ input: GradeInput, scores: [CanvasID<Assignment>: Double]) -> Double? {
        let overrides = scores.sorted { $0.key < $1.key }.map { WhatIfSimulator.Override(assignmentID: $0.key, score: $0.value) }
        return WhatIfSimulator.scores(applying: overrides, to: input).currentScore
    }

    @Test("Only the student's scores count: every Canvas submission and the grading periods are left out")
    func estimateInputHoldsOnlyTheStudentsScores() {
        let canvas = Self.pointsCourse()
        #expect(GradeEngine.scores(for: canvas).currentScore != nil, "Canvas's own data has graded work")
        let estimate = OutsideCanvasEstimate.estimateInput(from: canvas)
        #expect(estimate.items.allSatisfy { $0.submission == nil })
        #expect(estimate.periods.isEmpty && !estimate.hasWeightedGradingPeriods)
        #expect(estimate.groups == canvas.groups && estimate.weighting == canvas.weighting)
        #expect(estimate.items.map(\.id) == canvas.items.map(\.id))
        #expect(estimate.items.map(\.pointsPossible) == canvas.items.map(\.pointsPossible))
        #expect(GradeEngine.scores(for: estimate).currentScore == nil, "no score before the student types one")
        // hw2 = 10/10 and t1 = 50/100, by points: 60 / 110 = 54.55%. Canvas's 8 on hw1 is not counted,
        // and hw2 (no grading period) counts although the periods were weighted.
        #expect(Self.estimate(estimate, scores: ["hw2": 10, "t1": 50]) == 54.55)
    }

    @Test("The categories to weigh: those with an item that counts, in Canvas's order")
    func weighableGroups() {
        let input = OutsideCanvasEstimate.estimateInput(from: Self.pointsCourse())
        #expect(OutsideCanvasEstimate.weighableGroups(in: input) == ["hw", "tests"])
    }

    @Test("Defaults: Canvas's group weights when it weighs groups, else each category's share of the points")
    func defaults() throws {
        let points = OutsideCanvasEstimate.estimateInput(from: Self.pointsCourse())
        let shares = OutsideCanvasEstimate.defaultWeights(for: points)
        #expect(Set(shares.keys) == ["hw", "tests"])
        // 20 of 120 points and 100 of 120 (the unpublished and omitted items do not count).
        #expect(abs(try #require(shares["hw"]) - 100.0 / 6) < 1e-9)
        #expect(abs(try #require(shares["tests"]) - 500.0 / 6) < 1e-9)

        let weighted = OutsideCanvasEstimate.estimateInput(
            from: Self.pointsCourse(weighting: .percent, weights: (homework: 40, tests: 60, empty: 25, zero: 5)))
        #expect(OutsideCanvasEstimate.defaultWeights(for: weighted) == ["hw": 40, "tests": 60])
        let invalid = OutsideCanvasEstimate.estimateInput(
            from: Self.pointsCourse(weighting: .percent, weights: (homework: -10, tests: .nan, empty: 0, zero: 0)))
        #expect(OutsideCanvasEstimate.defaultWeights(for: invalid) == ["hw": 0, "tests": 0],
                "a negative or NaN Canvas weight defaults to 0")
    }

    @Test("A weight is a finite number from 0 to 100; anything else is refused, never clamped",
          arguments: [(0.0, true), (100, true), (37.5, true), (-0.0, true), (-1, false), (-0.001, false),
                      (100.001, false), (1e300, false), (.nan, false), (.infinity, false), (-.infinity, false)])
    func validWeights(weight: Double, valid: Bool) {
        #expect(OutsideCanvasEstimate.isValidWeight(weight) == valid)
    }

    @Test("No weight set: Canvas's own rule, exactly the input")
    func noWeightKeepsCanvasRule() {
        let input = OutsideCanvasEstimate.estimateInput(from: Self.pointsCourse())
        for weights: [CanvasID<AssignmentGroup>: Double] in [[:], ["hw": .nan], ["hw": -5], ["tests": 101], ["empty": 50], ["nope": 20]] {
            let (applied, outcome) = OutsideCanvasEstimate.applying(weights, to: input)
            #expect(outcome == .canvasSetting, "\(weights)")
            #expect(applied == input, "\(weights)")
        }
    }

    @Test("The student's weights feed the engine (percent weighting); a blank category keeps its default")
    func customWeights() throws {
        let input = OutsideCanvasEstimate.estimateInput(from: Self.pointsCourse())
        let scores: [CanvasID<Assignment>: Double] = ["hw2": 10, "t1": 50]
        let (both, outcome) = OutsideCanvasEstimate.applying(["hw": 40, "tests": 60], to: input)
        #expect(outcome == .custom)
        #expect(both.weighting == .percent)
        #expect(both.groups.map(\.weight) == [40, 60, 0, 0], "the empty and zero-point categories keep theirs")
        #expect(both.groups.map(\.rules) == input.groups.map(\.rules) && both.items == input.items)
        // Homework 10/10 = 100% × 40 + Tests 50/100 = 50% × 60 = 70%.
        #expect(Self.estimate(both, scores: scores) == 70)
        #expect(Self.estimate(input, scores: scores) == 54.55, "by points without weights")

        // Only Tests set: Homework keeps its points share, 16.67%; the total is 76.67, under 100, so
        // Canvas's rule scales it: (100 × 16.67 + 50 × 60) / 76.67 = 60.87%.
        let (one, _) = OutsideCanvasEstimate.applying(["tests": 60, "hw": .nan], to: input)
        #expect(abs(one.groups[0].weight - 100.0 / 6) < 1e-9 && one.groups[1].weight == 60)
        #expect(Self.estimate(one, scores: scores) == 60.87)
        let resolved = OutsideCanvasEstimate.resolvedWeights(["tests": 60, "hw": .nan], in: input)
        #expect(Set(resolved.keys) == ["hw", "tests"] && resolved["tests"] == 60)

        // Over 100 is used as given (Canvas's rule): 100% × 70 + 50% × 60 = 100%.
        let (over, _) = OutsideCanvasEstimate.applying(["hw": 70, "tests": 60], to: input)
        #expect(Self.estimate(over, scores: scores) == 100)
        // A zero weight is allowed while another category weighs something: Tests alone, 50%.
        let (zeroHomework, zeroOutcome) = OutsideCanvasEstimate.applying(["hw": 0], to: input)
        #expect(zeroOutcome == .custom && Self.estimate(zeroHomework, scores: scores) == 50)
    }

    @Test("All zero: no grade to estimate, so the weights are not applied and the outcome says so")
    func allZero() {
        let input = OutsideCanvasEstimate.estimateInput(from: Self.pointsCourse())
        let (applied, outcome) = OutsideCanvasEstimate.applying(["hw": 0, "tests": 0], to: input)
        #expect(outcome == .allZero)
        #expect(applied == input)
        #expect(Self.estimate(applied, scores: ["hw2": 10, "t1": 50]) == 54.55, "Canvas's rule still gives an estimate")
        // A weighted course whose blank category's Canvas weight is 0: one zero entry is all zero too.
        let weighted = OutsideCanvasEstimate.estimateInput(
            from: Self.pointsCourse(weighting: .percent, weights: (homework: 100, tests: 0, empty: 0, zero: 0)))
        #expect(OutsideCanvasEstimate.applying(["hw": 0], to: weighted).outcome == .allZero)
        #expect(OutsideCanvasEstimate.applying(["hw": 0, "empty": 50], to: weighted).outcome == .allZero,
                "a category with nothing to count does not rescue it")
    }

    @Test("A weighted course: blank categories keep Canvas's weights")
    func weightedCourseDefaults() {
        let input = OutsideCanvasEstimate.estimateInput(
            from: Self.pointsCourse(weighting: .percent, weights: (homework: 30, tests: 70, empty: 0, zero: 0)))
        let scores: [CanvasID<Assignment>: Double] = ["hw2": 10, "t1": 50]
        // Canvas's weights: 100% × 30 + 50% × 70 = 65%.
        #expect(Self.estimate(input, scores: scores) == 65)
        let (applied, outcome) = OutsideCanvasEstimate.applying(["hw": 50], to: input)
        #expect(outcome == .custom && applied.groups.map(\.weight) == [50, 70, 0, 0])
        // 100% × 50 + 50% × 70 = 85% (a total of 120, used as given).
        #expect(Self.estimate(applied, scores: scores) == 85)
    }
}
