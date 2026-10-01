import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

/// insights-at-a-glance.md §5.1/§5.2/§5.3. The §5.3 golden fixtures (h, w,
/// modifiers -> P) were recomputed by hand against the published formula
/// while building this suite and are internally consistent: every one of
/// F1–F8 reproduces the table's P to within 0.05, and the published order
/// F5 > F4 > F6 > F7 > F2 > F1 > F3 > F8 holds exactly. (The task brief's
/// example labels the 89.6-point item "Problem Set"; the spec's own table
/// calls it "F4 Homework" — a labeling-only mismatch, not a numeric one:
/// both name F5 "Lab report" = 97.5 and the 66.5 item "Discussion".)
@Suite("PriorityScore: §5.1 formula, §5.2 weight, ranking")
struct PriorityScoreTests {
    // MARK: - §5.3 golden fixtures

    private struct Fixture {
        let name: String
        let h: Double?
        let w: Double
        let modifiers: PriorityScore.Modifiers
        let expectedP: Double
        let expectedBand: PriorityScore.Band
    }

    private static let fixtures: [Fixture] = [
        Fixture(name: "F1 Quiz", h: 24, w: 0.01, modifiers: .init(), expectedP: 49.0, expectedBand: .medium),
        Fixture(name: "F2 Essay", h: 72, w: 0.20, modifiers: .init(), expectedP: 53.4, expectedBand: .medium),
        Fixture(name: "F3 Midterm exam", h: 240, w: 0.25, modifiers: .init(), expectedP: 40.4, expectedBand: .medium),
        Fixture(name: "F4 Homework", h: -12, w: 0.02, modifiers: .init(overdueStillOpen: true), expectedP: 89.6, expectedBand: .high),
        Fixture(name: "F5 Lab report", h: 6, w: 0.05, modifiers: .init(courseBelowGoal: true), expectedP: 97.5, expectedBand: .high),
        Fixture(name: "F6 Discussion", h: 2, w: 0.005, modifiers: .init(), expectedP: 66.5, expectedBand: .high),
        Fixture(name: "F7 Problem set", h: 30, w: 0.03, modifiers: .init(nearBoundary: true), expectedP: 59.4, expectedBand: .medium),
        Fixture(name: "F8 Reading", h: nil, w: 0.10, modifiers: .init(), expectedP: 20.0, expectedBand: .low),
    ]

    @Test(arguments: PriorityScoreTests.fixtures.map(\.name))
    func goldenFixtureMatchesTheSpecTable(_ name: String) throws {
        let fixture = try #require(Self.fixtures.first { $0.name == name })
        let p = PriorityScore.score(hoursUntilDue: fixture.h, courseWeight: fixture.w, modifiers: fixture.modifiers)
        #expect(abs(p - fixture.expectedP) < 0.05, "\(name): got \(p), want \(fixture.expectedP)")
        #expect(PriorityScore.band(p) == fixture.expectedBand, "\(name): band of \(p)")
    }

    /// §5.3: "Expected order: F5 > F4 > F6 > F7 > F2 > F1 > F3 > F8."
    @Test func goldenFixturesReproduceThePublishedOrder() {
        let ordered = Self.fixtures.map {
            PriorityScore.score(hoursUntilDue: $0.h, courseWeight: $0.w, modifiers: $0.modifiers)
        }
        let byName = Dictionary(uniqueKeysWithValues: zip(Self.fixtures.map(\.name), ordered))
        let names = ["F5 Lab report", "F4 Homework", "F6 Discussion", "F7 Problem set",
                     "F2 Essay", "F1 Quiz", "F3 Midterm exam", "F8 Reading"]
        for (a, b) in zip(names, names.dropFirst()) {
            #expect(byName[a]! > byName[b]!, "\(a) (\(byName[a]!)) should outrank \(b) (\(byName[b]!))")
        }
    }

    // MARK: - §5.3 monotonicity properties

    @Test func scoreNeverIncreasesAsHoursGrowPastZero() {
        var previous = Double.infinity
        for h in stride(from: 0.5, through: 400.0, by: 0.5) {
            let p = PriorityScore.score(hoursUntilDue: h, courseWeight: 0.15)
            #expect(p <= previous + 1e-9, "h=\(h): \(p) > previous \(previous)")
            previous = p
        }
    }

    @Test func scoreNeverDecreasesAsWeightGrows() {
        for h in [-10.0, 0.0, 6.0, 72.0] {
            var previous = -Double.infinity
            for w in stride(from: 0.0, through: 0.5, by: 0.01) {
                let p = PriorityScore.score(hoursUntilDue: h, courseWeight: w)
                #expect(p >= previous - 1e-9, "h=\(h) w=\(w): \(p) < previous \(previous)")
                previous = p
            }
        }
    }

    @Test func anOverdueOpenItemScoresAtLeastTheSameItemDueNow() {
        let dueNow = PriorityScore.score(hoursUntilDue: 0, courseWeight: 0.1)
        let overdueOpen = PriorityScore.score(hoursUntilDue: -5, courseWeight: 0.1, modifiers: .init(overdueStillOpen: true))
        #expect(overdueOpen >= dueNow)
    }

    // MARK: - §5.1 exclusion

    private func assignment(
        due: Date? = nil, lock: Date? = nil, points: Double? = 10, types: [String] = ["online_upload"],
        submission: Submission? = nil
    ) -> Assignment {
        Assignment(id: "a1", courseID: "c1", groupID: "g1", name: "Test", dueAt: due, lockAt: lock,
                  pointsPossible: points, gradingType: .points, omitFromFinalGrade: false, htmlURL: nil,
                  submission: submission, submissionTypes: types)
    }

    private func submission(
        score: Double? = nil, submittedAt: Date? = nil, gradedAt: Date? = nil, excused: Bool = false
    ) -> Submission {
        Submission(score: score, grade: nil, submittedAt: submittedAt, gradedAt: gradedAt, postedAt: gradedAt,
                  excused: excused, missing: false, late: false, workflowState: "unsubmitted")
    }

    @Test func submittedItemsAreExcluded() {
        let now = Date(timeIntervalSince1970: 1_790_600_400)
        let a = assignment(submission: submission(submittedAt: now.addingTimeInterval(-100)))
        #expect(PriorityScore.isExcluded(assignment: a, markedDone: false, now: now))
    }

    @Test func gradedItemsAreExcluded() {
        let now = Date(timeIntervalSince1970: 1_790_600_400)
        let a = assignment(submission: submission(score: 9, gradedAt: now.addingTimeInterval(-100)))
        #expect(PriorityScore.isExcluded(assignment: a, markedDone: false, now: now))
    }

    @Test func excusedItemsAreExcluded() {
        let now = Date(timeIntervalSince1970: 1_790_600_400)
        let a = assignment(submission: submission(excused: true))
        #expect(PriorityScore.isExcluded(assignment: a, markedDone: false, now: now))
    }

    @Test func markedDoneItemsAreExcluded() {
        let now = Date(timeIntervalSince1970: 1_790_600_400)
        #expect(PriorityScore.isExcluded(assignment: assignment(), markedDone: true, now: now))
    }

    /// F9: overdue AND locked becomes alert A2, not a "Next up" candidate.
    @Test func overdueAndLockedIsExcluded() {
        let now = Date(timeIntervalSince1970: 1_790_600_400)
        let a = assignment(due: now.addingTimeInterval(-3600), lock: now.addingTimeInterval(-60))
        #expect(PriorityScore.isExcluded(assignment: a, markedDone: false, now: now))
    }

    /// Overdue but still open (lock in the future, or no lock at all) is included.
    @Test func overdueButStillOpenIsIncluded() {
        let now = Date(timeIntervalSince1970: 1_790_600_400)
        let stillOpenNoLock = assignment(due: now.addingTimeInterval(-3600), lock: nil)
        let stillOpenFutureLock = assignment(due: now.addingTimeInterval(-3600), lock: now.addingTimeInterval(3600))
        #expect(!PriorityScore.isExcluded(assignment: stillOpenNoLock, markedDone: false, now: now))
        #expect(!PriorityScore.isExcluded(assignment: stillOpenFutureLock, markedDone: false, now: now))
    }

    @Test func noSubmissionExpectedWithNoDueDateIsExcluded() {
        let now = Date(timeIntervalSince1970: 1_790_600_400)
        let a = assignment(due: nil, types: ["none"])
        #expect(PriorityScore.isExcluded(assignment: a, markedDone: false, now: now))
    }

    @Test func noSubmissionExpectedWithADueDateIsAnAttendOrPrepareItem() {
        let now = Date(timeIntervalSince1970: 1_790_600_400)
        let a = assignment(due: now.addingTimeInterval(3600), types: ["on_paper"])
        #expect(!PriorityScore.isExcluded(assignment: a, markedDone: false, now: now))
    }

    // MARK: - §5.2 weight derivation

    private func item(_ id: String, group: CanvasID<AssignmentGroup>, points: Double?, omit: Bool = false, due: Date? = nil) -> Assignment {
        Assignment(id: CanvasID(id), courseID: "c1", groupID: group, name: id, dueAt: due, lockAt: nil,
                  pointsPossible: points, gradingType: .points, omitFromFinalGrade: omit, htmlURL: nil, submission: nil)
    }

    private func course(appliesGroupWeights: Bool, hasGradingPeriods: Bool = false) -> Course {
        Course(id: "c1", name: "Test", courseCode: "T1", term: nil, teachers: [], timeZone: nil,
              appliesGroupWeights: appliesGroupWeights, hasGradingPeriods: hasGradingPeriods,
              currentGradingPeriodID: nil, gradeVisibility: .visible, scores: nil, currentPeriodScores: nil, htmlURL: nil)
    }

    @Test func weightedGroupShareMatchesTheFormula() {
        let group = AssignmentGroup(id: "g1", name: "Homework", position: 1, weight: 40, rules: DropRules(),
                                    assignments: [item("a1", group: "g1", points: 20), item("a2", group: "g1", points: 80)])
        let course = course(appliesGroupWeights: true)
        // w = 0.40 * 20 / (20+80) = 0.08
        let w = PriorityScore.weight(assignment: group.assignments[0], course: course, groups: [group])
        #expect(abs(w - 0.08) < 1e-9)
    }

    @Test func unweightedShareIsPointsOverCourseTotal() {
        let g1 = AssignmentGroup(id: "g1", name: "A", position: 1, weight: nil, rules: DropRules(),
                                 assignments: [item("a1", group: "g1", points: 10)])
        let g2 = AssignmentGroup(id: "g2", name: "B", position: 2, weight: nil, rules: DropRules(),
                                 assignments: [item("a2", group: "g2", points: 30)])
        let course = course(appliesGroupWeights: false)
        // w = 10 / (10 + 30) = 0.25
        let w = PriorityScore.weight(assignment: g1.assignments[0], course: course, groups: [g1, g2])
        #expect(abs(w - 0.25) < 1e-9)
    }

    @Test func dropLowestDiscountsTheWeight() {
        let rules = DropRules(dropLowest: 1)
        let group = AssignmentGroup(id: "g1", name: "Labs", position: 1, weight: nil, rules: rules,
                                    assignments: (0..<4).map { item("a\($0)", group: "g1", points: 25) })
        let course = course(appliesGroupWeights: false)
        // Undiscounted: 25/100 = 0.25; discounted by (1 - 1/4) = 0.75 -> 0.1875.
        let w = PriorityScore.weight(assignment: group.assignments[0], course: course, groups: [group])
        #expect(abs(w - 0.1875) < 1e-9)
    }

    @Test func neverDropItemIsNotDiscounted() {
        let rules = DropRules(dropLowest: 1, neverDrop: ["a0"])
        let group = AssignmentGroup(id: "g1", name: "Labs", position: 1, weight: nil, rules: rules,
                                    assignments: (0..<4).map { item("a\($0)", group: "g1", points: 25) })
        let course = course(appliesGroupWeights: false)
        let w = PriorityScore.weight(assignment: group.assignments[0], course: course, groups: [group])
        #expect(abs(w - 0.25) < 1e-9, "never_drop item should not be discounted")
    }

    @Test func omittedOrZeroPointItemsHaveZeroWeight() {
        let course = course(appliesGroupWeights: false)
        let group = AssignmentGroup(id: "g1", name: "G", position: 1, weight: nil, rules: DropRules(),
                                    assignments: [item("a1", group: "g1", points: 10, omit: true)])
        #expect(PriorityScore.weight(assignment: group.assignments[0], course: course, groups: [group]) == 0)

        let zeroPointCourse = course
        let zeroGroup = AssignmentGroup(id: "g1", name: "G", position: 1, weight: nil, rules: DropRules(),
                                        assignments: [item("a1", group: "g1", points: 0)])
        #expect(PriorityScore.weight(assignment: zeroGroup.assignments[0], course: zeroPointCourse, groups: [zeroGroup]) == 0)
    }

    @Test func gradingPeriodsRestrictTheDenominatorToTheAssignmentsOwnPeriod() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let q1 = GradingPeriod(id: "q1", title: "Q1", startDate: start, endDate: start.addingTimeInterval(30 * 86_400),
                               closeDate: nil, weight: 50, isClosed: false)
        let q2 = GradingPeriod(id: "q2", title: "Q2", startDate: q1.endDate, endDate: q1.endDate.addingTimeInterval(30 * 86_400),
                               closeDate: nil, weight: 50, isClosed: false)
        let inQ1 = item("a1", group: "g1", points: 10, due: start.addingTimeInterval(86_400))
        let alsoQ1 = item("a2", group: "g1", points: 10, due: start.addingTimeInterval(2 * 86_400))
        let inQ2 = item("a3", group: "g1", points: 10, due: q2.startDate.addingTimeInterval(86_400))
        let group = AssignmentGroup(id: "g1", name: "G", position: 1, weight: nil, rules: DropRules(),
                                    assignments: [inQ1, alsoQ1, inQ2])
        let course = course(appliesGroupWeights: false, hasGradingPeriods: true)
        // Without period restriction this would be 10/30; with it, Q1's
        // denominator is only {inQ1, alsoQ1} = 20.
        let w = PriorityScore.weight(assignment: inQ1, course: course, groups: [group], gradingPeriods: [q1, q2])
        #expect(abs(w - 0.5) < 1e-9, "expected 10/20 within Q1, got \(w)")
    }

    // MARK: - Course modifiers (below goal / near boundary)

    @Test func belowGoalTakesPriorityOverNearBoundary() {
        let (below, near) = PriorityScore.courseModifiers(currentScore: 78, goal: 80)
        #expect(below)
        #expect(!near)
    }

    @Test func nearTheGoalFromAboveIsFlagged() {
        let (below, near) = PriorityScore.courseModifiers(currentScore: 80.5, goal: 80)
        #expect(!below)
        #expect(near)
    }

    @Test func nearAStandardLetterBoundaryIsFlaggedWithNoGoal() {
        let (below, near) = PriorityScore.courseModifiers(currentScore: 90.9, goal: nil)
        #expect(!below)
        #expect(near, "90.9 is within 1.5 of the A- boundary (90)")
    }

    @Test func comfortablyAboveEverythingIsNeither() {
        let (below, near) = PriorityScore.courseModifiers(currentScore: 95, goal: 80)
        #expect(!below)
        #expect(!near)
    }

    // MARK: - Ranking

    @Test func sortIsDeterministicUnderPermutation() {
        let base = Date(timeIntervalSince1970: 1_790_600_400)
        let items = [
            PriorityScore.RankedItem(assignmentID: "1", score: 90, dueAt: base, weight: 0.1, courseOrder: 0),
            PriorityScore.RankedItem(assignmentID: "2", score: 90, dueAt: base.addingTimeInterval(-60), weight: 0.1, courseOrder: 0),
            PriorityScore.RankedItem(assignmentID: "3", score: 70, dueAt: nil, weight: 0.2, courseOrder: 1),
            PriorityScore.RankedItem(assignmentID: "4", score: 90, dueAt: base.addingTimeInterval(-60), weight: 0.5, courseOrder: 0),
        ]
        // "4" and "2" tie on score and dueAt (both base-60); "4"'s higher
        // weight (0.5 > 0.1) puts it first. "1" (due base, later) comes next.
        // "3" has the lowest score and sorts last regardless of its tiebreaks.
        let expectedOrder = ["4", "2", "1", "3"]
        let sortedIDs = PriorityScore.sorted(items).map(\.assignmentID.rawValue)
        #expect(sortedIDs == expectedOrder)
        // Permute the input; the result must be identical.
        let permuted = PriorityScore.sorted(items.reversed())
        #expect(permuted.map(\.assignmentID.rawValue) == expectedOrder)
    }

    // MARK: - Reason (plan 08 L10N-02: values; the app phrases them, pinned by the hosted goldens)

    @Test func reasonLeadsWithDueTimeAndIncludesTopModifiers() {
        let factors = PriorityScore.reasonFactors(hoursUntilDue: 6, weight: 0.05, modifiers: .init(courseBelowGoal: true))
        #expect(factors == [.dueIn(hours: 6), .courseBelowGoal, .courseWeight(0.05)])
        #expect(factors.map(PriorityScore.reasonPart) == [.dueInHours(6), .courseBelowGoal, .courseWeightPercent(5)])
    }

    @Test func reasonForAnUndatedItemSaysSo() {
        let factors = PriorityScore.reasonFactors(hoursUntilDue: nil, weight: 0.10, modifiers: .init())
        #expect(factors == [.noDueDate, .courseWeight(0.10)])
    }

    /// At most two modifiers follow the lead, in priority order (below-goal or near-boundary,
    /// then still-accepted, then weight), and below-goal wins over near-boundary.
    @Test func reasonKeepsTheTopTwoModifiersInPriorityOrder() {
        let all = PriorityScore.Modifiers(overdueStillOpen: true, courseBelowGoal: true, nearBoundary: true)
        #expect(PriorityScore.reasonFactors(hoursUntilDue: -3, weight: 0.5, modifiers: all)
                    == [.overdue, .courseBelowGoal, .stillAccepted])
        #expect(PriorityScore.reasonFactors(hoursUntilDue: 0, weight: 0.5, modifiers: .init(nearBoundary: true))
                    == [.overdue, .nearBoundary, .courseWeight(0.5)])
        let floor = InsightsConfig.priorityReasonWeightFloor
        #expect(PriorityScore.reasonFactors(hoursUntilDue: 2, weight: floor, modifiers: .init()) == [.dueIn(hours: 2), .courseWeight(floor)])
        #expect(PriorityScore.reasonFactors(hoursUntilDue: 2, weight: floor.nextDown, modifiers: .init()) == [.dueIn(hours: 2)])
    }

    /// The whole units a reason shows: minutes under an hour (at least 1), hours from an hour,
    /// weight in whole percent, each rounded to nearest (the same numbers "Due in 59m", "Due in
    /// 24h", "~12% of …" showed before L10N-02; the capture at 628ee09 is in the L10N-02 report).
    @Test(arguments: [
        (0.001, PriorityScore.ReasonPart.dueInMinutes(1)), (0.0083, .dueInMinutes(1)), (0.5, .dueInMinutes(30)),
        (0.99, .dueInMinutes(59)), (1, .dueInHours(1)), (1.5, .dueInHours(2)), (23.6, .dueInHours(24)),
        (100, .dueInHours(100)),
    ])
    func reasonPartRoundsDueTimes(hours: Double, expected: PriorityScore.ReasonPart) {
        #expect(PriorityScore.reasonPart(.dueIn(hours: hours)) == expected)
    }

    @Test func reasonPartRoundsWeightToWholePercent() {
        #expect(PriorityScore.reasonPart(.courseWeight(0.123)) == .courseWeightPercent(12))
        #expect(PriorityScore.reasonPart(.courseWeight(0.125)) == .courseWeightPercent(13))
        #expect(PriorityScore.reasonPart(.courseWeight(1)) == .courseWeightPercent(100))
        #expect(PriorityScore.reasonPart(.overdue) == .overdue)
        #expect(PriorityScore.reasonPart(.stillAccepted) == .stillAccepted)
        #expect(PriorityScore.reasonPart(.courseBelowGoal) == .courseBelowGoal)
        #expect(PriorityScore.reasonPart(.nearBoundary) == .nearBoundary)
        #expect(PriorityScore.reasonPart(.noDueDate) == .noDueDate)
    }
}
