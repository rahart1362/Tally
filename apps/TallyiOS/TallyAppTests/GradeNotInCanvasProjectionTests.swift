import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyFeatures

/// Plan 08 XG-03, §4.4 rows 3-10: what the screens' projections say for a course whose grades are
/// not in Canvas, driven by the synthetic `external-grades` persona (six courses, one per branch:
/// ENG-10, ALG2 and BIO-H kept outside Canvas, ART-1 not yet posted, ADVISORY not graded in
/// Canvas, SPAN-2 graded in Canvas). Synthetic fixtures only (`fixtures/canvas/personas`).
///
/// Pure values: no SwiftUI here, so the file also builds in a Linux scratch harness against the
/// projection sources (the XG-03 report, §5). The views' own checks are in
/// `GradeNotInCanvasViewTests`.
enum ExternalGrades {
    /// The fixtures' anchor, 2026-09-28T13:00:00Z.
    static let anchor = Date(timeIntervalSince1970: 1_790_600_400)
    static let keptOutside: Set<String> = ["ENG-10", "ALG2", "BIO-H"]
    /// `.noneInCanvas`: the persona without SPAN-2, its only course graded in Canvas.
    static let noneInCanvas: Set<String> = ["ENG-10", "ALG2", "BIO-H", "ART-1", "ADVISORY"]

    static func formatter(now: Date = anchor) -> ScreenFormatter {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt
        calendar.locale = Locale(identifier: "en_US")
        return ScreenFormatter(now: now, calendar: calendar, locale: Locale(identifier: "en_US"))
    }

    static func snapshot(_ persona: String = "external-grades") async throws -> CanvasSnapshot {
        try await PersonaSnapshotHarness.fetchSnapshot(persona: persona, now: anchor)
    }

    /// `snapshot` with only the courses whose code is in `codes`.
    static func trimmed(_ snapshot: CanvasSnapshot, keeping codes: Set<String>) -> CanvasSnapshot {
        let courses = snapshot.courses.filter { codes.contains($0.courseCode) }
        let ids = Set(courses.map(\.id))
        return CanvasSnapshot(
            generation: snapshot.generation, accountKey: snapshot.accountKey, host: snapshot.host,
            fetchedAt: snapshot.fetchedAt, profile: snapshot.profile, courses: courses,
            groups: snapshot.groups.filter { ids.contains($0.key) },
            gradingPeriods: snapshot.gradingPeriods.filter { ids.contains($0.key) }, planner: snapshot.planner,
            events: snapshot.events, announcements: snapshot.announcements, courseColors: snapshot.courseColors,
            sections: snapshot.sections)
    }

    /// The index with the student's override "kept outside Canvas" on SPAN-2 (plan 08 G-3): a
    /// course whose Canvas grades exist, which must show none of them.
    static func spanishOverridden(_ snapshot: CanvasSnapshot) throws -> (Course, GradeAvailabilityIndex) {
        let spanish = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
        return (spanish, GradeAvailabilityIndex(snapshot: snapshot, overrides: [spanish.id: .keptOutsideCanvas], now: anchor))
    }

    static func byCode<T>(_ cards: [CourseCard], _ value: (CourseCard) -> T) -> [String: T] {
        Dictionary(uniqueKeysWithValues: cards.map { ($0.code, value($0)) })
    }
}

@Suite("XG-03 rows 3-4: Courses cards and the health chip (external-grades)")
struct GradeNotInCanvasCardTests {
    @Test("Row 3: kept outside Canvas is a dash, 'Not in Canvas', an ⓘ, and VoiceOver hears 'Grade not in Canvas'")
    func keptOutsideCards() async throws {
        let cards = CourseCardBuilder.cards(from: try await ExternalGrades.snapshot(), formatter: ExternalGrades.formatter())
        for card in cards where ExternalGrades.keptOutside.contains(card.code) {
            #expect(card.letter == nil && card.percentText == nil, "\(card.code)")
            #expect(card.notInCanvas == .keptOutside(.course), "\(card.code)")
            #expect(card.gradeText == "\u{2014}")
            #expect(card.notInCanvas?.caption == "Not in Canvas")
            #expect(card.notInCanvas?.spoken == "Grade not in Canvas")
            #expect(card.infoButtonLabel == "About grades for \(card.code)")
            #expect(card.accessibilityLabel.contains("Grade not in Canvas"), "\(card.accessibilityLabel)")
            // VoiceOver never says "dash", and never "No grade yet" for these.
            #expect(!card.accessibilityLabel.contains("\u{2014}") && !card.accessibilityLabel.lowercased().contains("dash"))
            #expect(!card.accessibilityLabel.contains("No grade yet"), "\(card.accessibilityLabel)")
        }
        // The chip's words are said once: "Grade not in Canvas" is the grade's, not repeated as health.
        let byCode = ExternalGrades.byCode(cards) { $0 }
        #expect(byCode["ALG2"]?.accessibilityLabel.hasPrefix("Algebra II, ALG2, Grade not in Canvas, next ") == true)
        #expect(byCode["ENG-10"]?.accessibilityLabel.hasPrefix("English 10, ENG-10, Grade not in Canvas, Needs attention, next ") == true)
    }

    @Test("Row 3: advisory is a dash and 'Not graded in Canvas' with no Tell My School; the others are unchanged")
    func otherCards() async throws {
        let cards = ExternalGrades.byCode(
            CourseCardBuilder.cards(from: try await ExternalGrades.snapshot(), formatter: ExternalGrades.formatter())) { $0 }
        let advisory = try #require(cards["ADVISORY"])
        #expect(advisory.notInCanvas == .notGraded)
        #expect(advisory.gradeText == "\u{2014}")
        #expect(advisory.notInCanvas?.caption == "Not graded in Canvas")
        #expect(advisory.infoButtonLabel == nil)
        #expect(advisory.accessibilityLabel.hasPrefix("Advisory, ADVISORY, Not graded in Canvas, "))

        let art = try #require(cards["ART-1"])
        #expect(art.notInCanvas == nil && art.gradeText == "No grade yet" && art.health == .noGradeYet)
        let spanish = try #require(cards["SPAN-2"])
        #expect(spanish.notInCanvas == nil && spanish.percentText == "91.4%" && spanish.letter == "A-")
        #expect(spanish.infoButtonLabel == nil)
    }

    @Test("Row 4: 'Grade not in Canvas' (minus.circle) unless missing work says otherwise")
    func healthChip() async throws {
        let cards = ExternalGrades.byCode(
            CourseCardBuilder.cards(from: try await ExternalGrades.snapshot(), formatter: ExternalGrades.formatter())) { $0.health }
        #expect(cards == ["ALG2": .gradeNotInCanvas, "BIO-H": .gradeNotInCanvas, "ENG-10": .needsAttention,
                          "ADVISORY": .needsAttention, "ART-1": .noGradeYet, "SPAN-2": .needsAttention])
        #expect(CourseHealth.gradeNotInCanvas.label == "Grade not in Canvas")
        #expect(CourseHealth.gradeNotInCanvas.symbol == "minus.circle")
        #expect(CourseHealth.allCases.filter(\.isSaidByTheGrade) == [.noGradeYet, .gradeNotInCanvas])
        // Missing work still counts: three days on, ENG-10's open missing items make it at risk.
        let later = CourseCardBuilder.cards(from: try await ExternalGrades.snapshot(),
                                            formatter: ExternalGrades.formatter(now: ExternalGrades.anchor.addingTimeInterval(3 * 86_400)))
        #expect(later.first { $0.code == "ENG-10" }?.health == .atRisk)
    }

    @Test("Row 4: grade and goal rules never run for a course kept outside Canvas, even with a Canvas score")
    func gradeRulesNeverRun() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let (spanish, overridden) = try ExternalGrades.spanishOverridden(snapshot)
        let groups = snapshot.groups[spanish.id] ?? []
        let formatter = ExternalGrades.formatter()
        // In Canvas: 91.4% is 1.4 points above the 90% cutoff, and well below a 99% goal.
        let inCanvas = CourseHealthRules.evaluate(course: spanish, groups: groups, gradingPeriods: [],
                                                  availability: .available, formatter: formatter)
        #expect(inCanvas.reasons == ["1.4 points above the 90% cutoff"])
        let goal = CourseHealthRules.evaluate(course: spanish, groups: groups, gradingPeriods: [], goal: 99,
                                              availability: .available, formatter: formatter)
        #expect(goal.health == .atRisk)
        for availability in [overridden[spanish.id], .notYetPosted, .lettersOnly, .hiddenByInstructor] {
            for target in [nil, 99.0] {
                let evaluation = CourseHealthRules.evaluate(course: spanish, groups: groups, gradingPeriods: [], goal: target,
                                                            availability: availability, formatter: formatter)
                #expect(evaluation.reasons.isEmpty, "\(String(describing: availability)): \(evaluation.reasons)")
            }
        }
        #expect(CourseHealthRules.evaluate(course: spanish, groups: groups, gradingPeriods: [],
                                           availability: overridden[spanish.id], formatter: formatter).health == .gradeNotInCanvas)
    }

    @Test("The screens use the projector's index: an override reaches the card, the detail and Insights")
    func screensUseTheIndex() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let (spanish, overridden) = try ExternalGrades.spanishOverridden(snapshot)
        let screens = ScreenProjections.build(from: snapshot, formatter: ExternalGrades.formatter(), gradeAvailability: overridden)
        // With SPAN-2 out, no course is graded in Canvas: the school's wording (§4.2).
        #expect(overridden.school == .noneInCanvas)
        let card = try #require(screens.courseCards.first { $0.id == spanish.id })
        #expect(card.notInCanvas == .keptOutside(.school) && card.percentText == nil && card.letter == nil)
        let detail = try #require(screens.courseDetails[spanish.id])
        #expect(detail.grade.notInCanvas == .keptOutside(.school))
        #expect(!screens.insights.trendInput.courses.contains { $0.id == spanish.id })
        // Without an index, each builder classifies the snapshot itself, as the projector does.
        let index = GradeAvailabilityIndex(snapshot: snapshot, overrides: [:], now: ExternalGrades.anchor)
        #expect(ScreenProjections.build(from: snapshot, formatter: ExternalGrades.formatter(), gradeAvailability: index)
                == ScreenProjections.build(from: snapshot, formatter: ExternalGrades.formatter()))
    }

    @Test("School level: with no course graded in Canvas, every bubble uses the school's wording")
    func schoolScope() async throws {
        let none = ExternalGrades.trimmed(try await ExternalGrades.snapshot(), keeping: ExternalGrades.noneInCanvas)
        let cards = CourseCardBuilder.cards(from: none, formatter: ExternalGrades.formatter())
        #expect(cards.filter { $0.notInCanvas == .keptOutside(.school) }.map(\.code).sorted() == ["ALG2", "BIO-H", "ENG-10"])
        #expect(GradeInfoScope(.noneInCanvas) == .school)
        for summary in [SchoolGradeSummary.allInCanvas, .mixed(outside: 2), .undetermined] {
            #expect(GradeInfoScope(summary) == .course)
        }
    }
}

@Suite("XG-03 rows 5-6: Course Detail and the what-if (external-grades)")
struct GradeNotInCanvasDetailTests {
    static func details(_ snapshot: CanvasSnapshot, index: GradeAvailabilityIndex? = nil) -> [String: CourseDetailProjection] {
        let details = CourseDetailBuilder.details(from: snapshot, formatter: ExternalGrades.formatter(), gradeAvailability: index)
        return Dictionary(uniqueKeysWithValues: details.values.map { ($0.code, $0) })
    }

    @Test("Row 5: the dash hero, one line for recent grades, category names only, no chart, no percentages")
    func keptOutsideDetail() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let details = Self.details(snapshot)
        let english = try #require(details["ENG-10"])
        #expect(english.heroLabel == "English 10, ENG-10, Grade not in Canvas, Needs attention")
        #expect(details["ALG2"]?.heroLabel == "Algebra II, ALG2, Grade not in Canvas")
        for code in ExternalGrades.keptOutside {
            let detail = try #require(details[code])
            #expect(detail.grade.notInCanvas == .keptOutside(.course), "\(code)")
            #expect(detail.recentGraded.isEmpty)
            #expect(detail.recentGradesNote == "Grades for this course aren't in Canvas.")
            #expect(detail.weights.isEmpty && detail.weightsSummary.isEmpty, "\(code): \(detail.weights)")
            #expect(!detail.categories.isEmpty && detail.categories.allSatisfy { $0.weightText == nil }, "\(code)")
            #expect(!detail.showsCategoryPercentages && detail.gradeInput == nil)
            #expect(!detail.heroLabel.contains("No grade yet") && !detail.heroLabel.contains("\u{2014}"))
        }
        #expect(details["BIO-H"]?.grade.hiddenReason == nil, "kept outside Canvas, not 'hidden by your instructor'")
        // Upcoming, missing and submitted are unchanged: the same rows the course had before.
        let course = try #require(snapshot.courses.first { $0.courseCode == "ENG-10" })
        #expect(english.sections == CourseDetailBuilder.sections(groups: snapshot.groups[course.id] ?? [], lettersOnly: false,
                                                                  formatter: ExternalGrades.formatter()))
        #expect(english.sections.map(\.kind) == [.upcoming, .missing, .submitted])
    }

    @Test("Row 5: a course kept outside Canvas by the student's override shows none of Canvas's grades")
    func overrideHidesCanvasGrades() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let (_, overridden) = try ExternalGrades.spanishOverridden(snapshot)
        #expect(try #require(Self.details(snapshot)["SPAN-2"]).recentGraded.count == 5)
        let spanish = try #require(Self.details(snapshot, index: overridden)["SPAN-2"])
        #expect(spanish.recentGraded.isEmpty && spanish.recentGradesNote != nil)
        #expect(spanish.grade.percentText == nil && spanish.grade.letter == nil)
        #expect(spanish.whatIf == nil && spanish.whatIfUnavailable == .notInCanvas)
        #expect(spanish.heroLabel == "Spanish 2, SPAN-2, Grade not in Canvas")
    }

    @Test("Row 6: the what-if is disabled with G-4's explanation, not hidden; advisory says why too")
    func whatIfDisabled() async throws {
        let details = Self.details(try await ExternalGrades.snapshot())
        for code in ExternalGrades.keptOutside {
            let detail = try #require(details[code])
            #expect(detail.whatIf == nil, "\(code)")
            #expect(detail.whatIfUnavailable == .notInCanvas, "\(code)")
        }
        #expect(WhatIfUnavailable.notInCanvas.showsDisabledButton)
        #expect(WhatIfUnavailable.notInCanvas.text
                == "What-if needs grades in Canvas, and this course's grades don't appear to be kept there.")
        let advisory = try #require(details["ADVISORY"])
        #expect(advisory.whatIf == nil && advisory.whatIfUnavailable == .notGradedInCanvas)
        #expect(WhatIfUnavailable.notGradedInCanvas.showsDisabledButton)
        #expect(WhatIfUnavailable.notGradedInCanvas.text == "This course doesn't have graded work in Canvas.")
        // In Canvas: SPAN-2 offers it; ART-1 (no grade posted yet) keeps today's rule and offers it.
        #expect(details["SPAN-2"]?.whatIf != nil && details["SPAN-2"]?.whatIfUnavailable == nil)
        #expect(details["ART-1"]?.whatIf != nil && details["ART-1"]?.whatIfUnavailable == nil)
    }

    @Test("Row 6: the other reasons keep their words (now whole-sentence keys) and no disabled button")
    func otherWhatIfReasons() async throws {
        let snapshot = try await ExternalGrades.snapshot("grading-periods")
        let chemistry = try #require(CourseDetailBuilder.details(from: snapshot, formatter: ExternalGrades.formatter())
            .values.first { $0.code == "CHEM-H" })
        #expect(chemistry.whatIfUnavailable == .hiddenTotals)
        #expect(WhatIfUnavailable.hiddenTotals.text == "What-if isn't available: your instructor has hidden course totals.")
        #expect(WhatIfUnavailable.noGradePosted.text == "What-if isn't available: no grade has been posted yet.")
        #expect(WhatIfUnavailable.lettersOnly.text == "What-if isn't available for a course that shows letter grades only.")
        #expect(WhatIfUnavailable.nothingToTry.text == "Everything in this course has a score, so there is nothing to try.")
        for reason in [WhatIfUnavailable.hiddenTotals, .noGradePosted, .lettersOnly, .nothingToTry] {
            #expect(!reason.showsDisabledButton)
        }
    }
}

@Suite("XG-03 rows 7-10: Insights (external-grades)")
struct GradeNotInCanvasInsightsTests {
    static func insights(_ snapshot: CanvasSnapshot, index: GradeAvailabilityIndex? = nil) -> InsightsProjection {
        InsightsBuilder.projection(from: snapshot, formatter: ExternalGrades.formatter(), gradeAvailability: index)
    }

    @Test("Row 7: the trend takes only courses in Canvas as percentages; none and kept outside: its own empty state")
    func trend() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let spanish = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
        let full = Self.insights(snapshot)
        #expect(full.trendInput.courses.map(\.id) == [spanish.id])
        #expect(!full.trendIsNotInCanvas)

        let (_, overridden) = try ExternalGrades.spanishOverridden(snapshot)
        let withOverride = Self.insights(snapshot, index: overridden)
        #expect(withOverride.trendInput.courses.isEmpty, "the override takes SPAN-2's posted grades out of the trend")
        #expect(withOverride.trendIsNotInCanvas)

        let none = Self.insights(ExternalGrades.trimmed(snapshot, keeping: ExternalGrades.noneInCanvas))
        #expect(none.trendInput.courses.isEmpty && none.trendIsNotInCanvas)
        // Nothing to trend, but not because of grades kept outside Canvas: the ordinary empty state.
        let early = Self.insights(ExternalGrades.trimmed(snapshot, keeping: ["ART-1", "ADVISORY"]))
        #expect(early.trendInput.courses.isEmpty && !early.trendIsNotInCanvas)
    }

    @Test("Row 8: the category breakdown leaves out kept-outside and advisory courses, and hides when nothing is left")
    func categoryBreakdown() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let shares = Self.insights(snapshot).categoryShares
        #expect(shares.map(\.name) == ["Projects", "Pruebas", "Tareas"])
        #expect(abs(shares.reduce(0) { $0 + $1.share } - 1) < 0.000_001)
        let outside = Self.insights(ExternalGrades.trimmed(snapshot, keeping: ExternalGrades.keptOutside.union(["ADVISORY"])))
        #expect(outside.categoryShares.isEmpty && outside.categorySummary.isEmpty)
    }

    @Test("Row 9: completion, momentum and heavy stretches do not read grade availability")
    func submissionBasedUnchanged() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let everyCourseOutside = GradeAvailabilityIndex(
            snapshot: snapshot, overrides: Dictionary(uniqueKeysWithValues: snapshot.courses.map { ($0.id, .keptOutsideCanvas) }),
            now: ExternalGrades.anchor)
        let plain = Self.insights(snapshot)
        let outside = Self.insights(snapshot, index: everyCourseOutside)
        #expect(plain.completion == outside.completion && plain.completion != nil)
        #expect(plain.streak == outside.streak)
        #expect(plain.heavyStretches == outside.heavyStretches)
    }

    @Test("Row 10: 'Needs a look' gives missing-work reasons for every course, grade reasons only in Canvas")
    func needsALook() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let risks = Dictionary(uniqueKeysWithValues: Self.insights(snapshot).risks.map { ($0.code, $0.reasons) })
        #expect(risks == ["ADVISORY": ["6 missing items are still accepted"], "ENG-10": ["1 missing item is still accepted"],
                          "SPAN-2": ["1.4 points above the 90% cutoff"]])
        let (_, overridden) = try ExternalGrades.spanishOverridden(snapshot)
        let withOverride = Self.insights(snapshot, index: overridden).risks.map(\.code)
        #expect(withOverride == ["ADVISORY", "ENG-10"], "SPAN-2's only reason was its grade")
    }
}

@Suite("XG-03: the flagship's screens are unchanged")
struct GradeNotInCanvasFlagshipTests {
    @Test("flagship: no dash, no ⓘ, no not-in-Canvas state, every what-if as before", arguments: [0.0, 3.0, 30.0])
    func flagshipUnchanged(days: Double) async throws {
        let now = ExternalGrades.anchor.addingTimeInterval(days * 86_400)
        let snapshot = try await PersonaSnapshotHarness.fetchSnapshot(persona: "flagship", now: ExternalGrades.anchor)
        let screens = ScreenProjections.build(from: snapshot, formatter: ExternalGrades.formatter(now: now))
        #expect(screens.courseCards.count == 5)
        #expect(screens.courseCards.allSatisfy { $0.notInCanvas == nil && $0.infoButtonLabel == nil })
        #expect(screens.courseCards.allSatisfy { $0.health != .gradeNotInCanvas && $0.percentText != nil })
        for detail in screens.courseDetails.values {
            #expect(detail.grade.notInCanvas == nil && detail.recentGradesNote == nil)
            #expect(detail.categories.allSatisfy { $0.weightText != nil })
            #expect(detail.showsCategoryPercentages && detail.gradeInput != nil)
            // Before XG-03 the what-if was offered for every flagship course with work left to try.
            #expect(detail.whatIf != nil || detail.whatIfUnavailable == .nothingToTry, "\(detail.code)")
        }
        #expect(!screens.insights.trendIsNotInCanvas && screens.insights.trendInput.courses.count == 5)
    }
}

@Suite("XG-03 §4.5: the approved copy (G-4)")
struct GradeNotInCanvasCopyTests {
    @Test("the projections' words are G-4's")
    func copy() {
        #expect(GradeNotInCanvas.keptOutside(.course).caption == "Not in Canvas")
        #expect(GradeNotInCanvas.keptOutside(.school).spoken == "Grade not in Canvas")
        #expect(GradeNotInCanvas.notGraded.caption == "Not graded in Canvas")
        #expect(GradeNotInCanvas.dash == "\u{2014}")
    }
}
