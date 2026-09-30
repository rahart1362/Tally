import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

/// Plan 08 (XG-01): `GradeAvailabilityRules.classify` rule by rule, the school summary, the
/// `external-grades` persona end to end (through the production mappers), and recovery.
///
/// Hand-built courses below are synthetic and minimal: only the fields the classifier reads vary.

// MARK: - Builders

private enum Build {
    /// The fixtures' anchor, 2026-09-28T13:00:00Z.
    static let now = Date(timeIntervalSince1970: 1_790_600_400)
    static let second: TimeInterval = 1
    static let day: TimeInterval = 24 * 60 * 60
    /// "Due `InsightsConfig.externalGradesGraceDays` or more days ago" means due at or before this.
    static let cutoff = now.addingTimeInterval(-InsightsConfig.externalGradesGraceWindow.timeInterval)
    static let courseID: CanvasID<Course> = "900001"
    static let noScores = ComputedScores(currentScore: nil, finalScore: nil, currentGrade: nil, finalGrade: nil)

    static func course(_ visibility: GradeVisibility = .visible, scores: ComputedScores? = noScores,
                       period: ComputedScores? = nil, id: CanvasID<Course> = courseID) -> Course {
        Course(id: id, name: "Synthetic \(id)", courseCode: "SYN-\(id)", term: nil, teachers: [], timeZone: nil,
               appliesGroupWeights: false, hasGradingPeriods: period != nil,
               currentGradingPeriodID: period == nil ? nil : "1", gradeVisibility: visibility,
               scores: scores, currentPeriodScores: period, htmlURL: nil)
    }

    static let unsubmitted = Submission(score: nil, grade: nil, submittedAt: nil, gradedAt: nil, postedAt: nil,
                                        excused: false, missing: false, late: false, workflowState: "unsubmitted")

    static func submitted(_ at: Date) -> Submission {
        Submission(score: nil, grade: nil, submittedAt: at, gradedAt: nil, postedAt: nil,
                   excused: false, missing: false, late: false, workflowState: "submitted")
    }

    static func item(_ n: Int, due: Date?, points: Double? = 10, grading: GradingType = .points,
                     types: [String] = ["online_upload"], published: Bool = true, omit: Bool = false,
                     submission: Submission? = unsubmitted, course: CanvasID<Course> = courseID) -> Assignment {
        Assignment(id: CanvasID("\(course.rawValue)\(n)"), courseID: course, groupID: "1", name: "Item \(n)",
                   dueAt: due, lockAt: nil, pointsPossible: points, gradingType: grading, omitFromFinalGrade: omit,
                   htmlURL: nil, submission: submission, published: published, submissionTypes: types)
    }

    /// `count` points items due at `due`, numbered from `first`; the first `submitted` were turned in
    /// online a day before they were due.
    static func batch(_ count: Int, due: Date, submitted: Int, types: [String] = ["online_upload"],
                      first: Int = 1) -> [Assignment] {
        (0..<count).map { i in
            item(first + i, due: due, types: types,
                 submission: i < submitted ? Build.submitted(due.addingTimeInterval(-day)) : unsubmitted)
        }
    }

    /// The smallest world that meets the strict threshold: exactly the minimum number of items, due
    /// exactly at the cutoff, exactly the minimum number submitted.
    static var atThreshold: [Assignment] {
        batch(InsightsConfig.externalGradesMinPastDueItems, due: cutoff,
              submitted: InsightsConfig.externalGradesMinSubmittedOrOffline)
    }

    static var atThresholdEvidence: GradeAvailability.Evidence {
        .init(pastDueItems: InsightsConfig.externalGradesMinPastDueItems,
              submittedOrOfflineItems: InsightsConfig.externalGradesMinSubmittedOrOffline)
    }

    static func groups(_ items: [Assignment]) -> [AssignmentGroup] {
        [AssignmentGroup(id: "1", name: "Work", position: 1, weight: nil, rules: DropRules(), assignments: items)]
    }

    /// A copy of `item` with `submission` replaced.
    static func with(_ item: Assignment, submission: Submission?) -> Assignment {
        Assignment(id: item.id, courseID: item.courseID, groupID: item.groupID, name: item.name, dueAt: item.dueAt,
                   lockAt: item.lockAt, pointsPossible: item.pointsPossible, gradingType: item.gradingType,
                   omitFromFinalGrade: item.omitFromFinalGrade, htmlURL: item.htmlURL, submission: submission,
                   published: item.published, submissionTypes: item.submissionTypes)
    }

    /// A course whose single extra item carries only the given graded signal.
    static func withSignal(_ signal: Submission, visibility: GradeVisibility = .visible) -> (Course, [Assignment]) {
        (course(visibility), atThreshold + [item(99, due: cutoff, submission: signal)])
    }
}

// MARK: - The rules table

struct RuleCase: Sendable, CustomTestStringConvertible {
    let name: String
    let course: Course
    let items: [Assignment]
    let override: GradeAvailabilityOverride?
    let expected: GradeAvailability
    var testDescription: String { name }

    init(_ name: String, _ course: Course, _ items: [Assignment], override: GradeAvailabilityOverride? = nil,
         expect expected: GradeAvailability) {
        self.name = name; self.course = course; self.items = items; self.override = override; self.expected = expected
    }

    static let all: [RuleCase] = rule1 + rule2 + rule3 + rule4 + rule5

    // Rule 1: the override wins, both ways.
    static let rule1: [RuleCase] = [
        RuleCase("R1 kept-outside override beats a Canvas score (rule 2)",
                 Build.course(scores: .init(currentScore: 91, finalScore: 60, currentGrade: nil, finalGrade: nil)),
                 Build.batch(2, due: Build.cutoff, submitted: 1), override: .keptOutsideCanvas,
                 expect: .keptOutsideCanvas(.init(pastDueItems: 2, submittedOrOfflineItems: 1))),
        RuleCase("R1 kept-outside override beats a graded signal (rule 3)",
                 Build.course(),
                 [Build.item(1, due: Build.cutoff, submission: Submission(
                    score: 9, grade: "9", submittedAt: nil, gradedAt: Build.cutoff, postedAt: Build.cutoff,
                    excused: false, missing: false, late: false, workflowState: "graded"))],
                 override: .keptOutsideCanvas, expect: .keptOutsideCanvas(.init(pastDueItems: 1, submittedOrOfflineItems: 0))),
        RuleCase("R1 kept-outside override on a course with no assignments",
                 Build.course(), [], override: .keptOutsideCanvas,
                 expect: .keptOutsideCanvas(.init(pastDueItems: 0, submittedOrOfflineItems: 0))),
        RuleCase("R1 in-Canvas override stops rule 5 at the threshold",
                 Build.course(), Build.atThreshold, override: .inCanvas, expect: .notYetPosted),
        RuleCase("R1 in-Canvas override on hidden totals at the threshold",
                 Build.course(.hiddenTotals), Build.atThreshold, override: .inCanvas, expect: .notYetPosted),
        RuleCase("R1 in-Canvas override keeps rule 2",
                 Build.course(scores: .init(currentScore: 88, finalScore: 70, currentGrade: nil, finalGrade: nil)),
                 Build.atThreshold, override: .inCanvas, expect: .available),
        RuleCase("R1 in-Canvas override keeps rule 4",
                 Build.course(), [Build.item(1, due: Build.cutoff, points: nil, grading: .notGraded, types: ["not_graded"])],
                 override: .inCanvas, expect: .notGradedInCanvas),
    ]

    // Rule 2: a current score or grade in Canvas; the final score and an all-nil score set don't count.
    static let rule2: [RuleCase] = [
        RuleCase("R2 visible current score -> available",
                 Build.course(scores: .init(currentScore: 91.4, finalScore: 56.7, currentGrade: nil, finalGrade: nil)),
                 Build.atThreshold, expect: .available),
        RuleCase("R2 letters only, current grade only -> lettersOnly",
                 Build.course(.lettersOnly, scores: .init(currentScore: nil, finalScore: nil, currentGrade: "B+", finalGrade: nil)),
                 [], expect: .lettersOnly),
        RuleCase("R2 hidden totals with a score -> hiddenByInstructor",
                 Build.course(.hiddenTotals, scores: .init(currentScore: 80, finalScore: nil, currentGrade: nil, finalGrade: nil)),
                 [], expect: .hiddenByInstructor),
        RuleCase("R2 current grading period score only -> available",
                 Build.course(scores: Build.noScores,
                              period: .init(currentScore: 84, finalScore: nil, currentGrade: nil, finalGrade: nil)),
                 Build.atThreshold, expect: .available),
        RuleCase("R2 current grading period grade only -> available",
                 Build.course(scores: nil, period: .init(currentScore: nil, finalScore: nil, currentGrade: "Pass", finalGrade: nil)),
                 Build.atThreshold, expect: .available),
        RuleCase("R2 final score 0.0 and final grade F alone are not a grade",
                 Build.course(scores: .init(currentScore: nil, finalScore: 0, currentGrade: nil, finalGrade: "F")),
                 Build.atThreshold, expect: .keptOutsideCanvas(Build.atThresholdEvidence)),
        RuleCase("R2 an enrollment score set with every field nil is not a grade",
                 Build.course(scores: Build.noScores, period: Build.noScores),
                 Build.atThreshold, expect: .keptOutsideCanvas(Build.atThresholdEvidence)),
        RuleCase("R2 no enrollment scores at all",
                 Build.course(scores: nil), Build.atThreshold, expect: .keptOutsideCanvas(Build.atThresholdEvidence)),
    ]

    // Rule 3: one graded signal anywhere vetoes rule 5 (the slow grader, the term-end poster).
    static let rule3: [RuleCase] = {
        func signal(score: Double? = nil, grade: String? = nil, gradedAt: Date? = nil, state: String = "submitted") -> Submission {
            Submission(score: score, grade: grade, submittedAt: Build.cutoff, gradedAt: gradedAt, postedAt: nil,
                       excused: false, missing: false, late: false, workflowState: state)
        }
        let scoreOnly = Build.withSignal(signal(score: 8))
        let gradeOnly = Build.withSignal(signal(grade: "complete"))
        let gradedAtOnly = Build.withSignal(signal(gradedAt: Build.cutoff))
        let stateOnly = Build.withSignal(signal(state: "graded"))
        let hidden = Build.withSignal(signal(gradedAt: Build.cutoff), visibility: .hiddenTotals)
        let letters = Build.withSignal(signal(score: 8), visibility: .lettersOnly)
        return [
            RuleCase("R3 veto: a posted score", scoreOnly.0, scoreOnly.1, expect: .notYetPosted),
            RuleCase("R3 veto: a posted grade", gradeOnly.0, gradeOnly.1, expect: .notYetPosted),
            RuleCase("R3 veto: gradedAt (score withheld, unposted)", gradedAtOnly.0, gradedAtOnly.1, expect: .notYetPosted),
            RuleCase("R3 veto: workflowState graded", stateOnly.0, stateOnly.1, expect: .notYetPosted),
            RuleCase("R3 veto on hidden totals -> hiddenByInstructor", hidden.0, hidden.1, expect: .hiddenByInstructor),
            RuleCase("R3 veto on letters only -> notYetPosted", letters.0, letters.1, expect: .notYetPosted),
            RuleCase("R3 veto from an item that is not eligible (zero points)", Build.course(),
                     Build.atThreshold + [Build.item(99, due: nil, points: 0, submission: signal(gradedAt: Build.now))],
                     expect: .notYetPosted),
            RuleCase("R3 veto from an unpublished item", Build.course(),
                     Build.atThreshold + [Build.item(99, due: nil, published: false, submission: signal(state: "graded"))],
                     expect: .notYetPosted),
            RuleCase("R3 veto on a course with no eligible item", Build.course(),
                     [Build.item(1, due: Build.cutoff, points: 0, submission: signal(score: 0))], expect: .notYetPosted),
        ]
    }()

    // Rule 4: nothing eligible.
    static let rule4: [RuleCase] = [
        RuleCase("R4 no groups -> notYetPosted", Build.course(), [], expect: .notYetPosted),
        RuleCase("R4 only unpublished items -> notYetPosted (none reach the student yet)", Build.course(),
                 (1...8).map { Build.item($0, due: Build.cutoff, published: false, submission: Build.submitted(Build.cutoff)) },
                 expect: .notYetPosted),
        RuleCase("R4 only not_graded items -> notGradedInCanvas", Build.course(),
                 (1...8).map { Build.item($0, due: Build.cutoff, points: nil, grading: .notGraded, types: ["not_graded"],
                                          submission: Build.submitted(Build.cutoff)) },
                 expect: .notGradedInCanvas),
        RuleCase("R4 not_graded grading type alone -> notGradedInCanvas", Build.course(),
                 (1...8).map { Build.item($0, due: Build.cutoff, grading: .notGraded, submission: Build.submitted(Build.cutoff)) },
                 expect: .notGradedInCanvas),
        RuleCase("R4 not_graded submission type alone (not gradeable) -> notGradedInCanvas", Build.course(),
                 (1...8).map { Build.item($0, due: Build.cutoff, types: ["not_graded"]) }, expect: .notGradedInCanvas),
        RuleCase("R4 only zero-point items -> notGradedInCanvas", Build.course(),
                 (1...8).map { Build.item($0, due: Build.cutoff, points: 0, submission: Build.submitted(Build.cutoff)) },
                 expect: .notGradedInCanvas),
        RuleCase("R4 only point-less (nil) points items -> notGradedInCanvas", Build.course(),
                 (1...8).map { Build.item($0, due: Build.cutoff, points: nil, submission: Build.submitted(Build.cutoff)) },
                 expect: .notGradedInCanvas),
        RuleCase("R4 a mix of not_graded and zero-point items -> notGradedInCanvas", Build.course(),
                 [Build.item(1, due: Build.cutoff, points: nil, grading: .notGraded, types: ["not_graded"]),
                  Build.item(2, due: Build.cutoff, points: 0, types: ["on_paper"]),
                  Build.item(3, due: nil, types: ["wiki_page"])],
                 expect: .notGradedInCanvas),
        RuleCase("R4 unpublished points items don't stop notGradedInCanvas", Build.course(),
                 [Build.item(1, due: Build.cutoff, points: nil, grading: .notGraded, types: ["not_graded"]),
                  Build.item(2, due: Build.cutoff, published: false)],
                 expect: .notGradedInCanvas),
        RuleCase("R4 only omitted-from-final points items -> notYetPosted", Build.course(),
                 (1...8).map { Build.item($0, due: Build.cutoff, omit: true, submission: Build.submitted(Build.cutoff)) },
                 expect: .notYetPosted),
        RuleCase("R4 zero-point pass/fail items are eligible", Build.course(),
                 (1...5).map { Build.item($0, due: Build.cutoff, points: 0, grading: .passFail,
                                          submission: Build.submitted(Build.cutoff)) },
                 expect: .keptOutsideCanvas(.init(pastDueItems: 5, submittedOrOfflineItems: 5))),
        RuleCase("R4 zero-point letter-graded items are eligible", Build.course(),
                 (1...5).map { Build.item($0, due: Build.cutoff, points: 0, grading: .letterGrade, types: ["on_paper"]) },
                 expect: .keptOutsideCanvas(.init(pastDueItems: 5, submittedOrOfflineItems: 5))),
        RuleCase("R4 zero-point percent items are not eligible", Build.course(),
                 (1...5).map { Build.item($0, due: Build.cutoff, points: 0, grading: .percent, types: ["on_paper"]) },
                 expect: .notGradedInCanvas),
    ]

    // Rule 5 (G-2 strict) and its boundaries; rule 6 is every fall-through.
    static let rule5: [RuleCase] = {
        let min = InsightsConfig.externalGradesMinPastDueItems
        let minSubmitted = InsightsConfig.externalGradesMinSubmittedOrOffline
        let justInside = Build.cutoff.addingTimeInterval(Build.second)   // 13 d 23:59:59 ago
        return [
            RuleCase("R5 5 items due exactly 14 days ago, 3 submitted -> kept outside", Build.course(),
                     Build.atThreshold, expect: .keptOutsideCanvas(Build.atThresholdEvidence)),
            RuleCase("R5 4/5 items: 4 due 14 days ago plus 1 due 13 days ago -> notYetPosted", Build.course(),
                     Build.batch(min - 1, due: Build.cutoff, submitted: min - 1)
                        + Build.batch(1, due: Build.cutoff.addingTimeInterval(Build.day), submitted: 1, first: 50),
                     expect: .notYetPosted),
            RuleCase("R5 13/14 days: 5 items due one second inside the grace window -> notYetPosted", Build.course(),
                     Build.batch(min, due: justInside, submitted: min), expect: .notYetPosted),
            RuleCase("R5 13/14 days: 5 items due 13 days ago -> notYetPosted", Build.course(),
                     Build.batch(min, due: Build.cutoff.addingTimeInterval(Build.day), submitted: min), expect: .notYetPosted),
            RuleCase("R5 2/3 submitted -> notYetPosted", Build.course(),
                     Build.batch(min, due: Build.cutoff, submitted: minSubmitted - 1), expect: .notYetPosted),
            RuleCase("R5 on_paper items count as offline", Build.course(),
                     Build.batch(min, due: Build.cutoff, submitted: 0, types: ["on_paper"]),
                     expect: .keptOutsideCanvas(.init(pastDueItems: min, submittedOrOfflineItems: min))),
            RuleCase("R5 submission type none counts as offline", Build.course(),
                     Build.batch(min, due: Build.cutoff, submitted: 0, types: ["none"]),
                     expect: .keptOutsideCanvas(.init(pastDueItems: min, submittedOrOfflineItems: min))),
            RuleCase("R5 on_paper mixed with an online type is not offline", Build.course(),
                     Build.batch(min, due: Build.cutoff, submitted: 0, types: ["on_paper", "online_upload"]),
                     expect: .notYetPosted),
            RuleCase("R5 2 submitted + 1 offline makes 3", Build.course(),
                     Build.batch(min - 1, due: Build.cutoff, submitted: minSubmitted - 1)
                        + Build.batch(1, due: Build.cutoff, submitted: 0, types: ["on_paper"], first: 50),
                     expect: .keptOutsideCanvas(Build.atThresholdEvidence)),
            RuleCase("R5 items with no due date never count", Build.course(),
                     Build.batch(min - 1, due: Build.cutoff, submitted: min - 1)
                        + [Build.item(50, due: nil, submission: Build.submitted(Build.cutoff))],
                     expect: .notYetPosted),
            RuleCase("R5 submitted items omitted from the final grade never count", Build.course(),
                     Build.batch(min - 1, due: Build.cutoff, submitted: min - 1)
                        + [Build.item(50, due: Build.cutoff, omit: true, submission: Build.submitted(Build.cutoff))],
                     expect: .notYetPosted),
            RuleCase("R5 hidden totals: kept outside takes precedence (no grade anywhere)", Build.course(.hiddenTotals),
                     Build.atThreshold, expect: .keptOutsideCanvas(Build.atThresholdEvidence)),
            RuleCase("R5 letters only: kept outside takes precedence", Build.course(.lettersOnly),
                     Build.atThreshold, expect: .keptOutsideCanvas(Build.atThresholdEvidence)),
            RuleCase("R5 evidence counts every past-due item, recent and future ones excluded", Build.course(),
                     Build.batch(8, due: Build.cutoff.addingTimeInterval(-10 * Build.day), submitted: 6)
                        + Build.batch(3, due: Build.now.addingTimeInterval(-Build.day), submitted: 3, first: 50)
                        + Build.batch(3, due: Build.now.addingTimeInterval(Build.day), submitted: 0, first: 60),
                     expect: .keptOutsideCanvas(.init(pastDueItems: 8, submittedOrOfflineItems: 6))),
            RuleCase("R6 early term: plenty submitted, nothing past the grace window", Build.course(),
                     Build.batch(10, due: Build.now.addingTimeInterval(-3 * Build.day), submitted: 10), expect: .notYetPosted),
        ]
    }()
}

@Suite("GradeAvailability: plan 08 §4.2 rules, first match wins")
struct GradeAvailabilityRuleTests {
    @Test("Every rule and guard", arguments: RuleCase.all)
    func rule(_ c: RuleCase) {
        let result = GradeAvailabilityRules.classify(course: c.course, groups: Build.groups(c.items), now: Build.now,
                                                     override: c.override)
        #expect(result == c.expected, "\(c.name)")
    }

    @Test("The G-2 strict thresholds the owner chose: 5 items, 14 days, 3 submitted or offline")
    func strictThresholdValues() {
        #expect(InsightsConfig.externalGradesMinPastDueItems == 5)
        #expect(InsightsConfig.externalGradesGraceDays == 14)
        #expect(InsightsConfig.externalGradesMinSubmittedOrOffline == 3)
        #expect(InsightsConfig.externalGradesGraceWindow == .seconds(14 * 24 * 60 * 60))
    }

    @Test("The classifier looks at every group, not only the first")
    func everyGroupCounts() {
        let items = Build.atThreshold
        let groups = items.enumerated().map { index, item in
            AssignmentGroup(id: CanvasID("\(index + 1)"), name: "Group", position: index + 1, weight: nil,
                            rules: DropRules(), assignments: [item])
        }
        #expect(GradeAvailabilityRules.classify(course: Build.course(), groups: groups, now: Build.now, override: nil)
                == .keptOutsideCanvas(Build.atThresholdEvidence))
    }

    @Test("isInCanvas is the plan 08 §4.4 partition")
    func isInCanvasPartition() {
        #expect(GradeAvailability.available.isInCanvas)
        #expect(GradeAvailability.lettersOnly.isInCanvas)
        #expect(GradeAvailability.hiddenByInstructor.isInCanvas)
        #expect(!GradeAvailability.notYetPosted.isInCanvas)
        #expect(!GradeAvailability.notGradedInCanvas.isInCanvas)
        #expect(!GradeAvailability.keptOutsideCanvas(Build.atThresholdEvidence).isInCanvas)
    }

    @Test("No state carries text: every value reachable from a GradeAvailability or SchoolGradeSummary is a number")
    func emitsNoStrings() {
        let values: [Any] = [
            GradeAvailability.available, GradeAvailability.lettersOnly, GradeAvailability.hiddenByInstructor,
            GradeAvailability.notYetPosted, GradeAvailability.notGradedInCanvas,
            GradeAvailability.keptOutsideCanvas(Build.atThresholdEvidence),
            SchoolGradeSummary.allInCanvas, SchoolGradeSummary.mixed(outside: 2), SchoolGradeSummary.noneInCanvas,
            SchoolGradeSummary.undetermined,
        ]
        func leaves(_ value: Any) -> [Any] {
            let children = Mirror(reflecting: value).children
            return children.isEmpty ? [value] : children.flatMap { leaves($0.value) }
        }
        for value in values {
            for leaf in leaves(value) {
                #expect(!(leaf is String) && !(leaf is Substring), "\(value) carries text")
            }
        }
    }
}

// MARK: - School summary and the index

private let outside = GradeAvailability.keptOutsideCanvas(.init(pastDueItems: 8, submittedOrOfflineItems: 8))

@Suite("GradeAvailability: SchoolGradeSummary and GradeAvailabilityIndex")
struct GradeAvailabilityIndexTests {
    @Test("School summary over the determinate courses", arguments: [
        ([GradeAvailability](), SchoolGradeSummary.undetermined),
        ([.notYetPosted, .notGradedInCanvas], .undetermined),
        ([.available], .allInCanvas),
        ([.lettersOnly, .hiddenByInstructor, .notYetPosted, .notGradedInCanvas], .allInCanvas),
        ([outside], .noneInCanvas),
        ([outside, outside, .notYetPosted, .notGradedInCanvas], .noneInCanvas),
        ([outside, .hiddenByInstructor], .mixed(outside: 1)),
        ([outside, outside, outside, .available, .notYetPosted, .notGradedInCanvas], .mixed(outside: 3)),
        ([outside, .lettersOnly], .mixed(outside: 1)),
    ])
    func summary(_ states: [GradeAvailability], _ expected: SchoolGradeSummary) {
        #expect(SchoolGradeSummary(states: states) == expected)
    }

    @Test("The index classifies each course with its own groups and override")
    func indexUsesPerCourseInputs() {
        let a: CanvasID<Course> = "11", b: CanvasID<Course> = "12", c: CanvasID<Course> = "13"
        let courses = [Build.course(id: a), Build.course(id: b), Build.course(id: c)]
        let groups = [a: Build.groups(Build.atThreshold), b: Build.groups(Build.atThreshold)]
        let index = GradeAvailabilityIndex(courses: courses, groups: groups, overrides: [b: .inCanvas, "99": .keptOutsideCanvas],
                                           now: Build.now)
        #expect(index[a] == .keptOutsideCanvas(Build.atThresholdEvidence))
        #expect(index[b] == .notYetPosted)
        #expect(index[c] == .notYetPosted, "a course with no groups entry has no assignments yet")
        #expect(index["99"] == nil, "an override for a course that is not in the snapshot adds nothing")
        #expect(index.byCourse.count == 3)
        #expect(index.school == .noneInCanvas)
    }

    @Test("A repeated course ID keeps its first occurrence (CS-07) and is counted once")
    func duplicateCourseIDs() {
        let id: CanvasID<Course> = "21"
        let graded = Build.course(scores: .init(currentScore: 90, finalScore: nil, currentGrade: nil, finalGrade: nil), id: id)
        let index = GradeAvailabilityIndex(courses: [Build.course(id: id), graded, Build.course(id: id)],
                                           groups: [id: Build.groups(Build.atThreshold)], overrides: [:], now: Build.now)
        #expect(index[id] == .keptOutsideCanvas(Build.atThresholdEvidence))
        #expect(index.byCourse.count == 1)
        #expect(index.school == .noneInCanvas)
    }
}

// MARK: - The external-grades persona (plan 08 §4.5) and recovery

@Suite("GradeAvailability: the external-grades persona")
struct GradeAvailabilityPersonaTests {
    static let persona = "external-grades"

    static func snapshot() async throws -> CanvasSnapshot {
        try await PersonaSnapshotHarness.fetchSnapshot(persona: persona, now: Build.now)
    }

    static func course(_ code: String, in snapshot: CanvasSnapshot) throws -> Course {
        try #require(snapshot.courses.first { $0.courseCode == code }, "\(code) is not in \(persona)")
    }

    static func trimmed(_ snapshot: CanvasSnapshot, keeping codes: Set<String>) -> [Course] {
        snapshot.courses.filter { codes.contains($0.courseCode) }
    }

    @Test("Every course gets the §4.5 state, and the school is mixed")
    func expectedStates() async throws {
        let snapshot = try await Self.snapshot()
        let index = GradeAvailabilityIndex(snapshot: snapshot, overrides: [:], now: Build.now)
        let byCode = Dictionary(uniqueKeysWithValues: snapshot.courses.map { ($0.courseCode, index[$0.id]) })
        #expect(byCode == [
            "ENG-10": .keptOutsideCanvas(.init(pastDueItems: 8, submittedOrOfflineItems: 8)),
            "ALG2": .keptOutsideCanvas(.init(pastDueItems: 9, submittedOrOfflineItems: 9)),
            "BIO-H": .keptOutsideCanvas(.init(pastDueItems: 8, submittedOrOfflineItems: 8)),
            "ART-1": .notYetPosted,
            "ADVISORY": .notGradedInCanvas,
            "SPAN-2": .available,
        ])
        #expect(index.school == .mixed(outside: 3))
    }

    @Test("The persona exercises the traps: ENG-10's final score is 0.0 and F, BIO-H hides totals")
    func personaCarriesTheTraps() async throws {
        let snapshot = try await Self.snapshot()
        let eng = try Self.course("ENG-10", in: snapshot)
        #expect(eng.scores == ComputedScores(currentScore: nil, finalScore: 0, currentGrade: nil, finalGrade: "F"))
        let bio = try Self.course("BIO-H", in: snapshot)
        #expect(bio.gradeVisibility == .hiddenTotals)
        #expect(bio.scores == Build.noScores)
    }

    @Test("Trimmed to the courses kept outside and the neutral ones, the school is noneInCanvas")
    func trimmedToNoneInCanvas() async throws {
        let snapshot = try await Self.snapshot()
        let courses = Self.trimmed(snapshot, keeping: ["ENG-10", "ALG2", "BIO-H", "ART-1", "ADVISORY"])
        let index = GradeAvailabilityIndex(courses: courses, groups: snapshot.groups, overrides: [:], now: Build.now)
        #expect(index.school == .noneInCanvas)
        let neutral = GradeAvailabilityIndex(courses: Self.trimmed(snapshot, keeping: ["ART-1", "ADVISORY"]),
                                             groups: snapshot.groups, overrides: [:], now: Build.now)
        #expect(neutral.school == .undetermined)
        let inCanvas = GradeAvailabilityIndex(courses: Self.trimmed(snapshot, keeping: ["SPAN-2", "ADVISORY"]),
                                              groups: snapshot.groups, overrides: [:], now: Build.now)
        #expect(inCanvas.school == .allInCanvas)
    }

    @Test("Overrides both ways on the persona")
    func overridesOnThePersona() async throws {
        let snapshot = try await Self.snapshot()
        let eng = try Self.course("ENG-10", in: snapshot), spa = try Self.course("SPAN-2", in: snapshot)
        let index = GradeAvailabilityIndex(snapshot: snapshot, overrides: [eng.id: .inCanvas, spa.id: .keptOutsideCanvas],
                                           now: Build.now)
        #expect(index[eng.id] == .notYetPosted)
        guard case .keptOutsideCanvas = index[spa.id] else {
            Issue.record("SPAN-2 with the kept-outside override is \(String(describing: index[spa.id]))")
            return
        }
        #expect(index.school == .noneInCanvas, "ALG2, BIO-H and SPAN-2 outside; nothing in Canvas")
    }

    @Test("Recovery: one posted grade flips ENG-10 out of keptOutsideCanvas, and to available once Canvas scores it")
    func onePostedGradeRecovers() async throws {
        let snapshot = try await Self.snapshot()
        let eng = try Self.course("ENG-10", in: snapshot)
        let groups = snapshot.groups[eng.id] ?? []
        #expect(GradeAvailabilityRules.classify(course: eng, groups: groups, now: Build.now, override: nil)
                == .keptOutsideCanvas(.init(pastDueItems: 8, submittedOrOfflineItems: 8)))

        // The teacher grades and posts the first reading response.
        let first = try #require(groups.first?.assignments.first)
        let posted = Submission(score: 9, grade: "9", submittedAt: first.submission?.submittedAt, gradedAt: Build.now,
                                postedAt: Build.now, excused: false, missing: false, late: false, workflowState: "graded")
        let regraded = groups.enumerated().map { index, group in
            index > 0 ? group : AssignmentGroup(
                id: group.id, name: group.name, position: group.position, weight: group.weight, rules: group.rules,
                assignments: [Build.with(first, submission: posted)] + group.assignments.dropFirst())
        }
        // Canvas sends the graded submission before the recomputed course score: rule 3 already vetoes.
        #expect(GradeAvailabilityRules.classify(course: eng, groups: regraded, now: Build.now, override: nil) == .notYetPosted)

        // With the course score Canvas computes for the new gradebook (GradeEngine is the parity-tested port).
        let score = GradeEngine.scores(course: eng, groups: regraded, gradingPeriods: []).currentScore
        #expect(score == 90)
        let scored = Course(id: eng.id, name: eng.name, courseCode: eng.courseCode, term: eng.term, teachers: eng.teachers,
                            timeZone: eng.timeZone, appliesGroupWeights: eng.appliesGroupWeights,
                            hasGradingPeriods: eng.hasGradingPeriods, currentGradingPeriodID: eng.currentGradingPeriodID,
                            gradeVisibility: eng.gradeVisibility,
                            scores: ComputedScores(currentScore: score, finalScore: eng.scores?.finalScore,
                                                   currentGrade: nil, finalGrade: nil),
                            currentPeriodScores: eng.currentPeriodScores, htmlURL: eng.htmlURL)
        #expect(GradeAvailabilityRules.classify(course: scored, groups: regraded, now: Build.now, override: nil) == .available)

        let courses = snapshot.courses.map { $0.id == eng.id ? scored : $0 }
        let index = GradeAvailabilityIndex(courses: courses, groups: snapshot.groups.merging([eng.id: regraded]) { $1 },
                                           overrides: [:], now: Build.now)
        #expect(index.school == .mixed(outside: 2))
    }
}
