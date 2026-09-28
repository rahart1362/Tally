import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

/// R-2 (resilience.md, PMO ruling D2(a)): grade inputs are bounded before they reach the
/// exact-rational drop-rule bisection. Before R-2, `GradeSanitizing` rejected only non-finite
/// values, so one `GradeEngine.scores` call on one 50-item drop-rule group holding 1e300 and 1e-300
/// took 39.0 s in a debug build and 2.38 s in release (the largest and smallest doubles: 44.0 s and
/// 2.70 s; crash-safety-2.md F-5 measured up to 106 s with its own probe), and `GoalSeek` makes
/// about 62 such calls.
///
/// Now a magnitude above `GradeSanitizing.maximumMagnitude` (1e50) is handled like a non-finite
/// value (`nil`, or 0 for a weight), and a non-zero magnitude below `minimumMagnitude` (1e-6)
/// becomes 0. 1e50 itself is canvas-lms's own "ridiculous circumstances" value and still computes
/// (`GradeEngineTests.tiesAndUnpointedAndRidiculousTotals`, unchanged).
@Suite("Grade inputs are bounded before the drop-rule bisection (R-2)", .timeLimit(.minutes(1)))
struct BoundedGradeInputTests {
    private let maximum = GradeSanitizing.maximumMagnitude
    private let minimum = GradeSanitizing.minimumMagnitude

    /// Group g1 (drop lowest 1 and highest 1, weight `weight`): `n` items of 10 points, scores
    /// 0-9, any of them changed through `edit`. Group g2 (weight 40): one 15/20 item.
    private func input(n: Int = 10, weighting: GradeInput.Weighting = .points, weight: Double = 100,
                       _ edit: (inout [GradeInput.Item]) -> Void = { _ in }) -> GradeInput {
        var items = (0..<n).map { i in
            GradeInput.Item(id: CanvasID("a\(100 + i)"), groupID: "g1", pointsPossible: 10,
                            submission: .init(score: Double(i % 10)))
        }
        edit(&items)
        return GradeInput(weighting: weighting,
                          groups: [.init(id: "g1", weight: weight, rules: DropRules(dropLowest: 1, dropHighest: 1)),
                                   .init(id: "g2", weight: 40)],
                          items: items + [GradeInput.Item(id: "b1", groupID: "g2", pointsPossible: 20, submission: .init(score: 15))])
    }

    // MARK: - The bounds themselves

    @Test func theCeilingIsInclusiveAndTheFloorIsTheSmallestNonZeroMagnitudeKept() {
        #expect(GradeSanitizing.sanePoints(maximum) == maximum)
        #expect(GradeSanitizing.sanePoints(maximum.nextUp) == nil)
        #expect(GradeSanitizing.sanePoints(.greatestFiniteMagnitude) == nil)
        #expect(GradeSanitizing.saneScore(-maximum) == -maximum)
        #expect(GradeSanitizing.saneScore((-maximum).nextDown) == nil)
        #expect(GradeSanitizing.saneScore(1e300) == nil)
        #expect(GradeSanitizing.saneWeight(-1e300) == nil)
        #expect(GradeSanitizing.saneWeightOrZero(1e51) == 0)

        #expect(GradeSanitizing.saneScore(minimum) == minimum)
        #expect(GradeSanitizing.saneScore(-minimum) == -minimum)
        #expect(GradeSanitizing.saneScore(minimum.nextDown) == 0)
        #expect(GradeSanitizing.saneScore(-1e-7) == 0)
        #expect(GradeSanitizing.sanePoints(1e-300) == 0)
        #expect(GradeSanitizing.saneScore(.leastNonzeroMagnitude) == 0)
        #expect(GradeSanitizing.saneWeight(5e-7) == 0)
        #expect(GradeSanitizing.saneWeightOrZero(-5e-7) == 0)
        #expect(GradeSanitizing.saneScore(0) == 0)
        #expect(GradeSanitizing.saneScore(-0.0)?.sign == .minus, "zero is not a magnitude below the floor: left as it is")
    }

    // MARK: - GradeEngine treats them like the values they stand for

    /// A magnitude past the ceiling gives exactly the scores a non-finite value in the same place
    /// gives: the item's points dropped, its score ignored, its group's weight 0.
    @Test(arguments: [1e300, GradeSanitizing.maximumMagnitude.nextUp, Double.greatestFiniteMagnitude])
    func pastTheCeilingIsHandledLikeANonFiniteValue(_ huge: Double) {
        #expect(GradeEngine.scores(for: input { $0[3].pointsPossible = huge })
                == GradeEngine.scores(for: input { $0[3].pointsPossible = .infinity }))
        for signed in [huge, -huge] {
            #expect(GradeEngine.scores(for: input { $0[4].submission?.score = signed })
                    == GradeEngine.scores(for: input { $0[4].submission?.score = .nan }))
        }
        #expect(GradeEngine.scores(for: input(weighting: .percent, weight: huge))
                == GradeEngine.scores(for: input(weighting: .percent, weight: .infinity)))
    }

    /// A non-zero magnitude below the floor gives exactly the scores 0 gives.
    @Test(arguments: [5e-7, 1e-300, Double.leastNonzeroMagnitude])
    func belowTheFloorIsHandledLikeZero(_ tiny: Double) {
        for signed in [tiny, -tiny] {
            #expect(GradeEngine.scores(for: input { $0[4].submission?.score = signed })
                    == GradeEngine.scores(for: input { $0[4].submission?.score = 0 }))
        }
        #expect(GradeEngine.scores(for: input { $0[5].pointsPossible = tiny })
                == GradeEngine.scores(for: input { $0[5].pointsPossible = 0 }))
        #expect(GradeEngine.scores(for: input(weighting: .percent, weight: tiny))
                == GradeEngine.scores(for: input(weighting: .percent, weight: 0)))
    }

    /// The zeroed weight leaves the denominator too: a course whose only weighted group sits
    /// below the floor has no weight at all, so no percent (nil), exactly like weight 0. With the
    /// raw weight in the denominator it read 0.0%.
    @Test(arguments: [5e-7, 1e-300])
    func aWeightBelowTheFloorLeavesTheDenominatorToo(_ tiny: Double) {
        func scores(_ weight: Double) -> EnrollmentScores {
            GradeEngine.scores(for: GradeInput(weighting: .percent, groups: [.init(id: "g1", weight: weight)], items: [
                .init(id: "a1", groupID: "g1", pointsPossible: 10, submission: .init(score: 7)),
            ]))
        }
        #expect(scores(tiny).currentScore == nil)
        #expect(scores(tiny) == scores(0))
    }

    /// 1e50 itself is valid and counted: a perfect score on a 1e50-point item is 100%. One ulp
    /// more and the item is dropped, leaving nothing to grade.
    @Test func theCeilingStillComputes() {
        func scores(_ points: Double) -> EnrollmentScores {
            GradeEngine.scores(for: GradeInput(weighting: .points, groups: [.init(id: "g1", weight: 100)], items: [
                .init(id: "a1", groupID: "g1", pointsPossible: points, submission: .init(score: points)),
            ]))
        }
        #expect(scores(maximum).currentScore == 100)
        #expect(scores(maximum).posted.currentGroups.first?.possible == Decimal(sign: .plus, exponent: 50, significand: 1))
        #expect(scores(maximum.nextUp).currentScore == nil)
    }

    // MARK: - Bounded time (hang detectors: `make core-perf` gates speed, in release)

    /// crash-safety-2.md F-5's inputs, n = 50: they never reach the bisection now. Before R-2 each
    /// call took 39-44 s in this debug build.
    @Test(arguments: [(big: 1e300, small: 1e-300), (big: Double.greatestFiniteMagnitude, small: Double.leastNonzeroMagnitude)])
    func extremeMagnitudesNoLongerReachTheBisection(_ extremes: (big: Double, small: Double)) {
        let extreme = input(n: 50) {
            $0[48].pointsPossible = extremes.big
            $0[49].pointsPossible = extremes.small
            $0[49].submission?.score = extremes.small
        }
        let clock = ContinuousClock()
        var scores: EnrollmentScores?
        let elapsed = clock.measure { scores = GradeEngine.scores(for: extreme) }
        #expect(elapsed < TestTimeBudget.seconds(10), "one GradeEngine.scores call took \(elapsed)")
        #expect(scores == GradeEngine.scores(for: input(n: 50) {
            $0[48].pointsPossible = nil
            $0[49].pointsPossible = 0
            $0[49].submission?.score = 0
        }))
    }
}
