import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyFeatures

/// Plan 08 XG-06 (owner decision, 2026-10-01): the what-if for a course whose grades are kept
/// outside Canvas. The student types their real scores, sees an estimate over the course's Canvas
/// categories, and may set each category's weight; scores and weights are for the session only.
/// Synthetic personas only (`external-grades`, `flagship`).
///
/// Pure values (projections and `WhatIfModel`, no SwiftUI), so the file also builds in a Linux
/// scratch harness against the sources (the XG-04/06 report). The views' checks are in
/// `GradeControlsViewTests`.
@Suite("XG-06: the what-if for a course whose grades are kept outside Canvas (projection)")
struct OutsideCanvasWhatIfProjectionTests {
    static func details(_ snapshot: CanvasSnapshot, index: GradeAvailabilityIndex? = nil) -> [String: CourseDetailProjection] {
        GradeNotInCanvasDetailTests.details(snapshot, index: index)
    }

    @Test("Kept outside Canvas: an estimate from every item worth points, with none of Canvas's scores")
    func keptOutsideOffersTheEstimate() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let details = Self.details(snapshot)
        for code in ExternalGrades.keptOutside {
            let detail = try #require(details[code])
            let whatIf = try #require(detail.whatIf, "\(code)")
            let estimate = try #require(whatIf.estimate, "\(code)")
            #expect(detail.whatIfUnavailable == nil)
            #expect(whatIf.input.items.allSatisfy { $0.submission == nil }, "\(code): no Canvas score in the estimate")
            #expect(whatIf.input.periods.isEmpty && !whatIf.input.hasWeightedGradingPeriods)
            #expect(estimate.categories.map(\.id) == whatIf.groups.map(\.id))
            #expect(estimate.categories.map(\.name) == whatIf.groups.map(\.name))
            // Every published, gradeable, counted item worth points is a row, submitted or not.
            let course = try #require(snapshot.courses.first { $0.courseCode == code })
            let counted = (snapshot.groups[course.id] ?? []).flatMap(\.assignments).filter(CourseDetailBuilder.counts)
            #expect(Set(whatIf.groups.flatMap(\.items).map(\.id)) == Set(counted.map(\.id)), "\(code)")
        }
        // ENG-10: one category, all of the points. ALG2: Homework 160 and Tests 200 of 360 points.
        #expect(details["ENG-10"]?.whatIf?.estimate?.categories.map(\.defaultText) == ["100"])
        let algebra = try #require(details["ALG2"]?.whatIf?.estimate)
        #expect(algebra.categories.map(\.name) == ["Homework", "Tests"])
        #expect(algebra.categories.map(\.defaultText) == ["44.44", "55.56"])
        #expect(abs(algebra.categories.map(\.defaultWeight).reduce(0, +) - 100) < 1e-9)
    }

    @Test("Not graded in Canvas stays disabled; courses graded in Canvas keep today's what-if; nothing worth points: why")
    func otherCoursesUnchanged() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let details = Self.details(snapshot)
        let advisory = try #require(details["ADVISORY"])
        #expect(advisory.whatIf == nil && advisory.whatIfUnavailable == .notGradedInCanvas)
        for code in ["SPAN-2", "ART-1"] {
            let whatIf = try #require(details[code]?.whatIf, "\(code)")
            #expect(whatIf.estimate == nil, "\(code): no disclaimer, no weights")
        }
        let spanish = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
        #expect(details["SPAN-2"]?.whatIf?.input == GradeInput(course: spanish, groups: snapshot.groups[spanish.id] ?? [],
                                                                 gradingPeriods: snapshot.gradingPeriods[spanish.id] ?? []))

        // The student says ADVISORY's grades are kept outside Canvas, but nothing in it is worth
        // points: there is nothing to estimate, so the button stays disabled with its explanation.
        let course = try #require(snapshot.courses.first { $0.courseCode == "ADVISORY" })
        let yes = GradeAvailabilityIndex(snapshot: snapshot, overrides: [course.id: .keptOutsideCanvas], now: ExternalGrades.anchor)
        let overridden = try #require(Self.details(snapshot, index: yes)["ADVISORY"])
        #expect(overridden.whatIf == nil && overridden.whatIfUnavailable == .notInCanvas)
    }

    @Test("The flagship is unchanged: no course has the estimate, every what-if as before", arguments: [0.0, 3.0, 30.0])
    func flagshipUnchanged(days: Double) async throws {
        let snapshot = try await PersonaSnapshotHarness.fetchSnapshot(persona: "flagship", now: ExternalGrades.anchor)
        let screens = ScreenProjections.build(from: snapshot,
                                              formatter: ExternalGrades.formatter(now: ExternalGrades.anchor.addingTimeInterval(days * 86_400)))
        for detail in screens.courseDetails.values {
            #expect(detail.whatIf?.estimate == nil, "\(detail.code)")
            if let whatIf = detail.whatIf { #expect(whatIf.input == detail.gradeInput, "\(detail.code)") }
        }
    }

    @Test("A weighted course the student says is kept outside Canvas: its categories default to Canvas's weights")
    func weightedCourseDefaults() async throws {
        let snapshot = try await PersonaSnapshotHarness.fetchSnapshot(persona: "flagship", now: ExternalGrades.anchor)
        let math = try #require(snapshot.courses.first { $0.courseCode == "MATH 122" })
        let yes = GradeAvailabilityIndex(snapshot: snapshot, overrides: [math.id: .keptOutsideCanvas], now: ExternalGrades.anchor)
        let detail = try #require(CourseDetailBuilder.details(from: snapshot, formatter: ExternalGrades.formatter(),
                                                              gradeAvailability: yes)[math.id])
        let estimate = try #require(detail.whatIf?.estimate)
        // Every counted item is a row, the graded ones too: the student types the school's scores.
        let counted = (snapshot.groups[math.id] ?? []).flatMap(\.assignments).filter(CourseDetailBuilder.counts)
        #expect(counted.contains { $0.submission?.score != nil && $0.submission?.postedAt != nil })
        #expect(detail.whatIf?.groups.flatMap(\.items).map(\.id).sorted() == counted.map(\.id).sorted())
        #expect(estimate.categories.map(\.name) == ["Problem Sets", "Quizzes", "Exams"])
        #expect(estimate.categories.map(\.defaultWeight) == [30, 20, 50])
        #expect(detail.whatIf?.input.weighting == .percent)
        #expect(detail.whatIf?.input.items.allSatisfy { $0.submission == nil } == true,
                "MATH 122's 90.1% is in Canvas, but the student said its grades are kept elsewhere")
    }
}

/// XG-06 through `WhatIfModel`: the estimate is `GradeWork` over the adjusted `GradeInput`
/// (`OutsideCanvasEstimate.applying`), invalid weights are refused and say so, and nothing outlives
/// the sheet.
@Suite("XG-06: the estimate and its weights (WhatIfModel, GradeWork only)", .serialized)
@MainActor
struct OutsideCanvasWhatIfModelTests {
    static func setup(_ code: String) async throws -> WhatIfSetup {
        let details = GradeNotInCanvasDetailTests.details(try await ExternalGrades.snapshot())
        return try #require(details[code]?.whatIf)
    }

    static func group(_ setup: WhatIfSetup, _ name: String) throws -> WhatIfGroup {
        try #require(setup.groups.first { $0.name == name })
    }

    @Test("No score typed: no estimate (a dash, not 'working it out'); then the estimate is GradeWork's, by points")
    func estimateByCanvasRule() async throws {
        let setup = try await Self.setup("ALG2")
        let model = WhatIfModel(setup: setup)
        #expect(!model.hasNoGrade, "before the first answer lands, the summary says it is working it out")
        await model.start()
        #expect(model.baseline == nil && model.projected == nil, "nothing of Canvas's is counted")
        #expect(model.hasNoGrade)
        #expect(model.weightsOutcome == .canvasSetting && abs(model.weightTotal - 100) < 1e-9)
        #expect(!model.weightTotalIsOverHundred, "the points shares add up to 100, up to rounding")

        let homework = try #require(Self.group(setup, "Homework").items.first)
        let test = try #require(Self.group(setup, "Tests").items.first)
        model.setScore(homework.pointsPossible, for: homework.id)
        model.setScore(test.pointsPossible * 0.8, for: test.id)
        await model.settle()
        #expect(!model.hasNoGrade)
        let overrides = [WhatIfSimulator.Override(assignmentID: homework.id, score: homework.pointsPossible),
                         .init(assignmentID: test.id, score: test.pointsPossible * 0.8)].sorted { $0.assignmentID < $1.assignmentID }
        let byPoints = try await GradeWork.scores(applying: overrides, to: setup.input).currentScore
        #expect(model.projected == byPoints)
        // 10 + 80 of 10 + 100 points.
        #expect(byPoints == 81.82)
        #expect(model.delta == nil, "an estimate has no 'current grade' to compare with")
    }

    @Test("Custom weights: the estimate equals GradeWork over the adjusted GradeInput, and the goal uses it too")
    func customWeights() async throws {
        let setup = try await Self.setup("ALG2")
        let homeworkGroup = try Self.group(setup, "Homework")
        let testsGroup = try Self.group(setup, "Tests")
        let homework = try #require(homeworkGroup.items.first)
        let test = try #require(testsGroup.items.first)
        let model = WhatIfModel(setup: setup)
        await model.start()
        model.setScore(homework.pointsPossible, for: homework.id)
        model.setScore(test.pointsPossible * 0.8, for: test.id)
        model.setWeight(.number(20), for: homeworkGroup.id)
        model.setWeight(.number(80), for: testsGroup.id)
        model.setGoal(assignment: test.id)
        model.setGoal(percent: 90)
        await model.settle()

        let weights: [CanvasID<AssignmentGroup>: Double] = [homeworkGroup.id: 20, testsGroup.id: 80]
        let adjusted = OutsideCanvasEstimate.applying(weights, to: setup.input)
        #expect(adjusted.outcome == .custom && model.weightsOutcome == .custom)
        #expect(model.estimateInput == adjusted.input)
        #expect(model.weights == weights && model.invalidWeights.isEmpty)
        let overrides = [WhatIfSimulator.Override(assignmentID: homework.id, score: homework.pointsPossible),
                         .init(assignmentID: test.id, score: test.pointsPossible * 0.8)].sorted { $0.assignmentID < $1.assignmentID }
        let expected = try await GradeWork.scores(applying: overrides, to: adjusted.input).currentScore
        #expect(model.projected == expected)
        // 100% × 20 + 80% × 80.
        #expect(expected == 84)
        #expect(model.weightTotal == 100 && !model.weightTotalIsOverHundred)

        let goalInput = WhatIfSimulator.apply(overrides.filter { $0.assignmentID != test.id }, to: adjusted.input)
        let goal = try await GradeWork.goalSeek(assignmentID: test.id, targetPercent: 90, in: goalInput)
        #expect(model.goalOutcome == goal.outcome)

        // One category blank: Tests keeps its share of the points (55.56); the total is 75.56.
        model.setWeight(.blank, for: testsGroup.id)
        await model.settle()
        let oneSet = OutsideCanvasEstimate.applying([homeworkGroup.id: 20], to: setup.input).input
        #expect(model.projected == (try await GradeWork.scores(applying: overrides, to: oneSet).currentScore))
        #expect(abs(model.weightTotal - (20 + 2_000.0 / 36)) < 1e-9)
    }

    @Test("Invalid weights are refused and flagged, never applied; all zero and over 100 say so",
          arguments: [WhatIfModel.WeightEntry.number(-5), .number(-0.001), .number(100.5), .number(.nan),
                      .number(.infinity), .unreadable])
    func invalidWeights(entry: WhatIfModel.WeightEntry) async throws {
        let setup = try await Self.setup("ALG2")
        let homeworkGroup = try Self.group(setup, "Homework")
        let testsGroup = try Self.group(setup, "Tests")
        let homework = try #require(homeworkGroup.items.first)
        let model = WhatIfModel(setup: setup)
        await model.start()
        model.setScore(homework.pointsPossible / 2, for: homework.id)
        await model.settle()
        let byPoints = model.projected

        model.setWeight(.number(30), for: homeworkGroup.id)
        model.setWeight(entry, for: homeworkGroup.id)
        await model.settle()
        #expect(model.invalidWeights == [homeworkGroup.id], "\(entry): flagged")
        #expect(model.weights.isEmpty, "\(entry): never applied, and the earlier 30 is not kept")
        #expect(model.weightsOutcome == .canvasSetting && model.estimateInput == setup.input)
        #expect(model.projected == byPoints)

        model.setWeight(.number(0), for: homeworkGroup.id)
        model.setWeight(.number(0), for: testsGroup.id)
        await model.settle()
        #expect(model.invalidWeights.isEmpty)
        #expect(model.weightsOutcome == .allZero, "every category at 0: Canvas's setting, and the sheet says so")
        #expect(model.estimateInput == setup.input && model.projected == byPoints)
        #expect(!model.weightTotalIsOverHundred)

        model.setWeight(.number(70), for: homeworkGroup.id)
        model.setWeight(.number(60), for: testsGroup.id)
        #expect(model.weightTotal == 130 && model.weightTotalIsOverHundred)
        model.setWeight(.number(30), for: testsGroup.id)
        #expect(model.weightTotal == 100 && !model.weightTotalIsOverHundred)
    }

    @Test("Nine equal categories: defaults that add up to 100 up to rounding are not 'over 100'")
    func roundingIsNotOverHundred() {
        let ids = (1...9).map { CanvasID<AssignmentGroup>("g\($0)") }
        let input = GradeInput(weighting: .points, groups: ids.map { .init(id: $0, weight: 0) },
                               items: ids.enumerated().map { index, group in
                                   .init(id: CanvasID("a\(index)"), groupID: group, pointsPossible: 1, submission: nil)
                               })
        let categories = ids.map { WhatIfWeightCategory(id: $0, name: $0.rawValue, defaultWeight: 100.0 / 9, defaultText: "11.11") }
        let model = WhatIfModel(setup: WhatIfSetup(courseName: "Synthetic", input: input, groups: [],
                                                   estimate: WhatIfEstimateSetup(categories: categories)))
        #expect(model.weightTotal > 100, "the premise: nine shares of 100/9 add up to just over 100 in binary")
        #expect(!model.weightTotalIsOverHundred)
    }

    @Test("What a weight field's text means, in the student's locale")
    func weightEntry() {
        let us = Locale(identifier: "en_US")
        #expect(WhatIfModel.weightEntry("", locale: us) == .blank)
        #expect(WhatIfModel.weightEntry("   ", locale: us) == .blank)
        #expect(WhatIfModel.weightEntry("40", locale: us) == .number(40))
        #expect(WhatIfModel.weightEntry(" 12.5 ", locale: us) == .number(12.5))
        #expect(WhatIfModel.weightEntry("-3", locale: us) == .number(-3), "a number, which the model then refuses")
        #expect(WhatIfModel.weightEntry("abc", locale: us) == .unreadable)
        #expect(WhatIfModel.weightEntry("12,5", locale: Locale(identifier: "de_DE")) == .number(12.5))
    }

    @Test("Session only: Reset clears scores and weights; a new sheet starts from Canvas's setting, with nothing typed")
    func sessionOnly() async throws {
        let setup = try await Self.setup("ALG2")
        let homeworkGroup = try Self.group(setup, "Homework")
        let homework = try #require(homeworkGroup.items.first)
        let model = WhatIfModel(setup: setup)
        await model.start()
        #expect(!model.canReset)
        model.setWeight(.unreadable, for: homeworkGroup.id)
        #expect(model.canReset, "an invalid entry can be reset too")
        model.setScore(homework.pointsPossible, for: homework.id)
        model.setWeight(.number(25), for: homeworkGroup.id)
        await model.settle()
        model.reset()
        await model.settle()
        #expect(model.scores.isEmpty && model.weights.isEmpty && model.invalidWeights.isEmpty)
        #expect(model.resetCount == 1 && model.weightsOutcome == .canvasSetting && model.estimateInput == setup.input)
        #expect(model.projected == nil && model.hasNoGrade)

        // Closing the sheet drops its model (Course Detail's `whatIf = nil`); the next one is new.
        let reopened = WhatIfModel(setup: setup)
        #expect(reopened.scores.isEmpty && reopened.weights.isEmpty && reopened.estimateInput == setup.input)
    }

    @Test("A course graded in Canvas: today's what-if, with no weights to set")
    func canvasCourseHasNoWeights() async throws {
        let setup = try await Self.setup("SPAN-2")
        let model = WhatIfModel(setup: setup)
        await model.start()
        #expect(abs((model.baseline ?? 0) - 91.39) < 0.01, "Canvas's current score, as before")
        let group = try #require(setup.groups.first)
        model.setWeight(.number(10), for: group.id)
        #expect(model.weights.isEmpty && model.invalidWeights.isEmpty && model.estimateInput == setup.input)
    }
}
