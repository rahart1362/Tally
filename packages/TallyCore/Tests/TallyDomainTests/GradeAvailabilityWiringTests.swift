import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

/// Plan 08 XG-02: grade availability carried through the dashboard projection (§4.4 rows 1, 11,
/// 12), the grade alerts (rows 11, 13) and the change digest (row 16). Hand-built snapshots vary
/// only what the rule under test reads; the personas come through the production pipeline.

// MARK: - Builders

private enum Wire {
    /// The fixtures' anchor, 2026-09-28T13:00:00Z (the `external-grades` persona's own "now").
    static let now = Date(timeIntervalSince1970: 1_790_600_400)
    static let hour: TimeInterval = 60 * 60

    static func scores(_ current: Double?, grade: String? = nil) -> ComputedScores {
        ComputedScores(currentScore: current, finalScore: current, currentGrade: grade, finalGrade: nil)
    }

    static func course(_ id: String, _ visibility: GradeVisibility = .visible, scores: ComputedScores? = nil,
                       period: ComputedScores? = nil) -> Course {
        Course(id: CanvasID(id), name: "Synthetic \(id)", courseCode: "SYN-\(id)", term: nil, teachers: [], timeZone: nil,
               appliesGroupWeights: false, hasGradingPeriods: period != nil,
               currentGradingPeriodID: period == nil ? nil : "1", gradeVisibility: visibility,
               scores: scores, currentPeriodScores: period, htmlURL: nil)
    }

    static let unsubmitted = Submission(score: nil, grade: nil, submittedAt: nil, gradedAt: nil, postedAt: nil,
                                        excused: false, missing: false, late: false, workflowState: "unsubmitted")

    static func item(_ id: String, course: Course, points: Double, dueInHours hours: Double,
                     submission: Submission? = unsubmitted) -> Assignment {
        Assignment(id: CanvasID(id), courseID: course.id, groupID: CanvasID("g-\(course.id.rawValue)"), name: "Item \(id)",
                   dueAt: now.addingTimeInterval(hours * hour), lockAt: nil, pointsPossible: points, gradingType: .points,
                   omitFromFinalGrade: false, htmlURL: nil, submission: submission, published: true,
                   submissionTypes: ["online_upload"])
    }

    static func snapshot(_ courses: [Course], items: [Assignment] = [], fetchedAt: Date = now) -> CanvasSnapshot {
        let groups = Dictionary(grouping: items, by: \.courseID).mapValues { assignments in
            [AssignmentGroup(id: assignments[0].groupID, name: "Work", position: 1, weight: nil, rules: DropRules(),
                             assignments: assignments)]
        }
        return CanvasSnapshot(
            generation: 1, accountKey: AccountKey("xg02"), host: "canvas.xg02.example", fetchedAt: fetchedAt,
            profile: UserProfile(id: "1", name: "Synthetic Student", shortName: nil, timeZone: nil, calendarFeedURL: nil),
            courses: courses, groups: groups, gradingPeriods: [:], planner: [], events: [], announcements: [],
            courseColors: [:],
            sections: Dictionary(uniqueKeysWithValues: SnapshotSection.allCases.map {
                ($0, SectionStatus(fetchedAt: fetchedAt, carriedForward: false))
            }))
    }

    /// `snapshot` with only the courses whose code is in `codes` (and their groups).
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

    static func persona(_ name: String, now: Date = Wire.now) async throws -> CanvasSnapshot {
        try await PersonaSnapshotHarness.fetchSnapshot(persona: name, now: now)
    }

    /// The hero's mean exactly as `DashboardProjection.swift` computed it at 47a461c (`hero(courses:)`,
    /// lines 185-193): every `.visible` course's current score.
    static func legacyMean(_ courses: [Course]) -> Double? {
        let percents = courses.compactMap { $0.gradeVisibility == .visible ? $0.scores?.currentScore : nil }
        return percents.isEmpty ? nil : percents.reduce(0, +) / Double(percents.count)
    }

    /// Every `GradeAvailability` state, and "not in the index".
    static let everyState: [GradeAvailability?] = [
        .available, .lettersOnly, .hiddenByInstructor, .notYetPosted, .notGradedInCanvas,
        .keptOutsideCanvas(.init(pastDueItems: 5, submittedOrOfflineItems: 3)), nil,
    ]
}

// MARK: - Row 1: the dashboard hero

@Suite("XG-02 row 1: the hero averages only courses whose grades are in Canvas (G-5)")
struct GradeAvailabilityHeroTests {
    @Test("The flagship persona is unchanged: Average of 5 courses, the same mean and band")
    func flagshipIsUnchanged() async throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000) // DashboardProjectionTests' instant
        let snapshot = try await Wire.persona("flagship", now: now)
        let hero = DashboardBuilder.build(from: snapshot, digest: nil, digestAsOf: nil, now: now).hero
        #expect(hero.courseCount == 5)
        #expect(hero.averagedCount == 5)
        #expect(hero.exclusions.isEmpty)
        #expect(hero.school == .allInCanvas)
        #expect(hero.overallPercent == Wire.legacyMean(snapshot.courses))
        #expect(abs((hero.overallPercent ?? 0) - 88.34) < 0.005)
        #expect(hero.overallBand == .bRange)
    }

    @Test("Every older persona keeps the old mean; only a course with hidden totals leaves N",
          arguments: ["flagship", "flagship-previous", "finals", "grading-periods", "large"])
    func olderPersonasKeepTheirMean(persona: String) async throws {
        let snapshot = try await Wire.persona(persona)
        let hero = DashboardBuilder.build(from: snapshot, digest: nil, digestAsOf: nil, now: Wire.now).hero
        #expect(hero.overallPercent == Wire.legacyMean(snapshot.courses))
        #expect(hero.courseCount == snapshot.courses.count)
        #expect(hero.averagedCount == snapshot.courses.filter {
            $0.gradeVisibility == .visible && $0.scores?.currentScore != nil
        }.count)
        #expect(hero.averagedCount + hero.exclusions.values.reduce(0, +) == hero.courseCount)
        #expect(hero.school == .allInCanvas)
        if persona == "grading-periods" {
            // Plan 08 G-5: CHEM-H hides its total, so it is not averaged: "Average of 3 courses", not 4.
            #expect(hero.averagedCount == 3)
            #expect(hero.exclusions == [.hiddenByInstructor: 1])
        } else {
            #expect(hero.exclusions.isEmpty)
        }
    }

    @Test("external-grades: SPAN-2 alone is averaged; every other course is counted under its reason")
    func externalGradesPersona() async throws {
        let snapshot = try await Wire.persona("external-grades")
        let hero = DashboardBuilder.build(from: snapshot, digest: nil, digestAsOf: nil, now: Wire.now).hero
        #expect(hero.courseCount == 6)
        #expect(hero.averagedCount == 1)
        #expect(hero.overallPercent == 91.39)
        #expect(hero.overallBand == .aRange)
        #expect(hero.exclusions == [.keptOutsideCanvas: 3, .notYetPosted: 1, .notGradedInCanvas: 1])
        #expect(hero.school == .mixed(outside: 3))
    }

    @Test("Nothing averaged and the school is noneInCanvas: no percent, no band (the 'Grades aren't in Canvas' state)")
    func noneInCanvas() async throws {
        let full = try await Wire.persona("external-grades")
        let snapshot = Wire.trimmed(full, keeping: ["ENG-10", "ALG2", "BIO-H", "ART-1", "ADVISORY"])
        let hero = DashboardBuilder.build(from: snapshot, digest: nil, digestAsOf: nil, now: Wire.now).hero
        #expect(hero.courseCount == 5)
        #expect(hero.averagedCount == 0)
        #expect(hero.overallPercent == nil)
        #expect(hero.overallBand == nil)
        #expect(hero.school == .noneInCanvas)
        #expect(hero.exclusions == [.keptOutsideCanvas: 3, .notYetPosted: 1, .notGradedInCanvas: 1])

        let early = Wire.trimmed(full, keeping: ["ART-1", "ADVISORY"])
        let undetermined = DashboardBuilder.build(from: early, digest: nil, digestAsOf: nil, now: Wire.now).hero
        #expect(undetermined.averagedCount == 0 && undetermined.school == .undetermined)
    }

    @Test("Only an averaged course's score is in the mean: letters only, hidden, no percent and kept outside are not")
    func onlyAveragedScoresCount() {
        let averaged = Wire.course("1", scores: Wire.scores(80))
        let gradeOnly = Wire.course("2", scores: Wire.scores(nil, grade: "A"))
        let periodOnly = Wire.course("3", scores: Wire.scores(nil), period: Wire.scores(70))
        let letters = Wire.course("4", .lettersOnly, scores: Wire.scores(60, grade: "D-"))
        let hidden = Wire.course("5", .hiddenTotals, scores: Wire.scores(50))
        let overridden = Wire.course("6", scores: Wire.scores(40))
        let snapshot = Wire.snapshot([averaged, gradeOnly, periodOnly, letters, hidden, overridden])
        let index = GradeAvailabilityIndex(snapshot: snapshot, overrides: [overridden.id: .keptOutsideCanvas], now: Wire.now)

        let hero = DashboardBuilder.build(from: snapshot, digest: nil, digestAsOf: nil, now: Wire.now,
                                          gradeAvailability: index).hero
        #expect(hero.averagedCount == 1)
        #expect(hero.overallPercent == 80)
        #expect(hero.overallBand == .bRange)
        #expect(hero.exclusions == [.noPercentage: 2, .lettersOnly: 1, .hiddenByInstructor: 1, .keptOutsideCanvas: 1])
        #expect(hero.school == .mixed(outside: 1))
    }

    @Test("A repeated course ID is counted once, by its first occurrence (CS-07)")
    func repeatedCourseCountsOnce() {
        let first = Wire.course("1", scores: Wire.scores(90))
        let repeated = Wire.course("1", scores: Wire.scores(10))
        let hero = DashboardBuilder.build(from: Wire.snapshot([first, repeated]), digest: nil, digestAsOf: nil,
                                          now: Wire.now).hero
        #expect(hero.courseCount == 1)
        #expect(hero.averagedCount == 1)
        #expect(hero.overallPercent == 90)
    }

    @Test("CourseGradeStatus: one status per state; only .available with a current score is averaged")
    func statusTable() {
        let scored = Wire.course("1", scores: Wire.scores(88))
        let unscored = Wire.course("2", scores: Wire.scores(nil, grade: "B+"))
        let expected: [CourseGradeStatus] = [.averaged, .lettersOnly, .hiddenByInstructor, .notYetPosted,
                                             .notGradedInCanvas, .keptOutsideCanvas, .notYetPosted]
        #expect(Wire.everyState.map { CourseGradeStatus(course: scored, availability: $0) } == expected)
        #expect(CourseGradeStatus(course: unscored, availability: .available) == .noPercentage)
        // The raw values are the glance's persisted contract.
        #expect(CourseGradeStatus.allCases.map(\.rawValue) == [
            "averaged", "noPercentage", "lettersOnly", "hiddenByInstructor", "notYetPosted", "notGradedInCanvas",
            "keptOutsideCanvas",
        ])
        // The summary over statuses equals the summary over the states they came from.
        for states in [Wire.everyState.compactMap { $0 }, [.available, .notYetPosted],
                       [.keptOutsideCanvas(.init(pastDueItems: 9, submittedOrOfflineItems: 9)), .notGradedInCanvas]] {
            let statuses = states.map { CourseGradeStatus(course: scored, availability: $0) }
            #expect(SchoolGradeSummary(statuses: statuses) == SchoolGradeSummary(states: states))
        }
    }

    @Test("The four-argument build is the explicit build with the automatic index")
    func automaticIndexIsTheDefault() async throws {
        let snapshot = try await Wire.persona("external-grades")
        let index = GradeAvailabilityIndex(snapshot: snapshot, overrides: [:], now: Wire.now)
        #expect(DashboardBuilder.build(from: snapshot, digest: nil, digestAsOf: nil, now: Wire.now)
                == DashboardBuilder.build(from: snapshot, digest: nil, digestAsOf: nil, now: Wire.now, gradeAvailability: index))
    }
}

// MARK: - Rows 11 and 12: priority modifiers and the course-weight reason

@Suite("XG-02 rows 11-12: modifiers see a score only when .available; no weight reason for excluded courses")
struct GradeAvailabilityPriorityTests {
    /// 80.5 is within `priorityBoundaryWindow` (1.5) above the 80 cutoff: near a boundary.
    static let nearBoundary = Wire.course("1", scores: Wire.scores(80.5))
    /// 85 is more than 1.5 above 83 and below 87: no course modifier either way.
    static let clear = Wire.course("2", scores: Wire.scores(85))

    @Test("modifierScore: the current score for .available only", arguments: Wire.everyState.indices)
    func modifierScoreOnlyForAvailable(stateIndex: Int) {
        let state = Wire.everyState[stateIndex]
        #expect(DashboardBuilder.modifierScore(of: Self.nearBoundary, availability: state)
                == (state == .available ? 80.5 : nil))
    }

    @Test("Next up: near a grade boundary for an .available course, not once its grades are kept outside Canvas")
    func nearBoundaryFollowsAvailability() throws {
        let course = Self.nearBoundary
        let snapshot = Wire.snapshot([course], items: [Wire.item("a1", course: course, points: 10, dueInHours: 30)])
        let automatic = DashboardBuilder.build(from: snapshot, digest: nil, digestAsOf: nil, now: Wire.now)
        let outside = DashboardBuilder.build(
            from: snapshot, digest: nil, digestAsOf: nil, now: Wire.now,
            gradeAvailability: GradeAvailabilityIndex(snapshot: snapshot, overrides: [course.id: .keptOutsideCanvas],
                                                      now: Wire.now))
        let inCanvas = try #require(automatic.nextUp.first)
        let excluded = try #require(outside.nextUp.first)
        #expect(inCanvas.reasonFactors.contains(.nearBoundary))
        #expect(!excluded.reasonFactors.contains(.nearBoundary))
        #expect(!excluded.reasonFactors.contains(.courseBelowGoal))
    }

    @Test("Next up: the course-weight reason is dropped for a course kept outside Canvas; the ranking is unchanged")
    func weightReasonIsDroppedRankingIsNot() throws {
        let course = Self.clear
        let other = Wire.course("3", scores: Wire.scores(85))
        // a1 is the whole course's points (weight 1.0, far over the reason floor); b1 ranks against it.
        let snapshot = Wire.snapshot([course, other], items: [
            Wire.item("a1", course: course, points: 50, dueInHours: 30),
            Wire.item("b1", course: other, points: 10, dueInHours: 20),
            Wire.item("b2", course: other, points: 90, dueInHours: 200),
        ])
        let automatic = DashboardBuilder.build(from: snapshot, digest: nil, digestAsOf: nil, now: Wire.now)
        let outside = DashboardBuilder.build(
            from: snapshot, digest: nil, digestAsOf: nil, now: Wire.now,
            gradeAvailability: GradeAvailabilityIndex(snapshot: snapshot, overrides: [course.id: .keptOutsideCanvas],
                                                      now: Wire.now))
        #expect(automatic.nextUp.map(\.id) == outside.nextUp.map(\.id))
        #expect(automatic.nextUp.map(\.band) == outside.nextUp.map(\.band))
        let before = try #require(automatic.nextUp.first { $0.id == "a1" })
        let after = try #require(outside.nextUp.first { $0.id == "a1" })
        #expect(before.reasonFactors.contains(.courseWeight(1.0)))
        #expect(after.reasonFactors == before.reasonFactors.filter { $0 != .courseWeight(1.0) })
        // The other course is untouched.
        #expect(automatic.nextUp.filter { $0.id != "a1" } == outside.nextUp.filter { $0.id != "a1" })
    }

    @Test("external-grades: no Next up item from a course whose grades are not in Canvas gives a weight reason")
    func personaHasNoWeightReasonForExcludedCourses() async throws {
        let snapshot = try await Wire.persona("external-grades")
        let index = GradeAvailabilityIndex(snapshot: snapshot, overrides: [:], now: Wire.now)
        let projection = DashboardBuilder.build(from: snapshot, digest: nil, digestAsOf: nil, now: Wire.now,
                                                gradeAvailability: index)
        let courseOf = Dictionary(snapshot.groups.flatMap { courseID, groups in
            groups.flatMap(\.assignments).map { ($0.id, courseID) }
        }, uniquingKeysWith: { first, _ in first })
        #expect(!projection.nextUp.isEmpty)
        for item in projection.nextUp {
            let state = try #require(courseOf[item.id].flatMap { index[$0] })
            if !state.isInCanvas {
                #expect(!item.reasonFactors.contains { if case .courseWeight = $0 { true } else { false } },
                        "\(item.title): \(item.reasonFactors)")
            }
        }
    }

    @Test("Below goal (A5) and significant drop (A6) fire only for .available", arguments: Wire.everyState.indices)
    func gradeAlertsNeedAvailable(stateIndex: Int) {
        guard let state = Wire.everyState[stateIndex] else { return }
        let below = AlertEngine.belowGoalAlert(courseID: "1", currentScore: 70, goal: 80, wasActive: false, availability: state)
        let drop = AlertEngine.significantDropAlert(courseID: "1", currentScore: 80, previousRefreshScore: 90,
                                                    score14DaysAgo: nil, weekOf: Wire.now, belowGoalIsFiring: false,
                                                    availability: state)
        #expect((below != nil) == (state == .available))
        #expect((drop != nil) == (state == .available))
    }
}

// MARK: - Row 13: "New grade posted"

@Suite("XG-02 row 13: no grade-posted alert while a course is kept outside Canvas; the first posted grade fires once")
struct GradeAvailabilityGradePostedTests {
    @Test("While flagged, nothing in a kept-outside course can fire; one posted grade recovers and fires once")
    func flaggedThenRecovered() async throws {
        let snapshot = try await Wire.persona("external-grades")
        let index = GradeAvailabilityIndex(snapshot: snapshot, overrides: [:], now: Wire.now)
        var flaggedItems = 0
        for course in snapshot.courses {
            guard let state = index[course.id], case .keptOutsideCanvas = state else { continue }
            for assignment in (snapshot.groups[course.id] ?? []).flatMap(\.assignments) {
                flaggedItems += 1
                #expect(AlertEngine.gradePostedAlert(previous: nil, current: assignment, availability: state) == nil)
                #expect(AlertEngine.gradePostedAlert(previous: assignment, current: assignment, availability: state) == nil)
                // Under the strict rule there is nothing to fire on, whatever the guard says.
                #expect(AlertEngine.gradePostedAlert(previous: nil, current: assignment, availability: .available) == nil)
            }
        }
        #expect(flaggedItems > 0)

        // The ENG-10 teacher grades and posts the first reading response.
        let eng = try #require(snapshot.courses.first { $0.courseCode == "ENG-10" })
        let groups = snapshot.groups[eng.id] ?? []
        let first = try #require(groups.first?.assignments.first)
        let posted = Assignment(
            id: first.id, courseID: first.courseID, groupID: first.groupID, name: first.name, dueAt: first.dueAt,
            lockAt: first.lockAt, pointsPossible: first.pointsPossible, gradingType: first.gradingType,
            omitFromFinalGrade: first.omitFromFinalGrade, htmlURL: first.htmlURL,
            submission: Submission(score: 9, grade: "9", submittedAt: first.submission?.submittedAt, gradedAt: Wire.now,
                                   postedAt: Wire.now, excused: false, missing: false, late: false, workflowState: "graded"),
            published: first.published, submissionTypes: first.submissionTypes)
        let regraded = groups.enumerated().map { position, group in
            position > 0 ? group : AssignmentGroup(id: group.id, name: group.name, position: group.position,
                                                   weight: group.weight, rules: group.rules,
                                                   assignments: [posted] + group.assignments.dropFirst())
        }
        let recovered = GradeAvailabilityIndex(courses: snapshot.courses, groups: snapshot.groups.merging([eng.id: regraded]) { $1 },
                                               overrides: [:], now: Wire.now)
        let state = try #require(recovered[eng.id])
        #expect(state == .notYetPosted, "rule 3: the posted grade takes ENG-10 out of keptOutsideCanvas at once")
        #expect(AlertEngine.gradePostedAlert(previous: first, current: posted, availability: state)?.kind
                == .gradePosted(submissionID: CanvasID(posted.id.rawValue), postedAt: Wire.now))
        #expect(AlertEngine.gradePostedAlert(previous: posted, current: posted, availability: state) == nil, "once")

        // Only the student's "kept outside Canvas" override keeps the course flagged with a posted
        // score; then the alert stays quiet.
        let overridden = GradeAvailabilityIndex(courses: snapshot.courses,
                                                groups: snapshot.groups.merging([eng.id: regraded]) { $1 },
                                                overrides: [eng.id: .keptOutsideCanvas], now: Wire.now)
        let flagged = try #require(overridden[eng.id])
        #expect(AlertEngine.gradePostedAlert(previous: first, current: posted, availability: flagged) == nil)
    }
}

// MARK: - Row 16: the change digest

@Suite("XG-02 row 16: a course-score change is reported only for an .available course")
struct GradeAvailabilityDigestTests {
    static let course = Wire.course("1", scores: Wire.scores(80))
    static let old = Wire.snapshot([course], items: [Wire.item("a1", course: course, points: 10, dueInHours: 30)])
    static let new = Wire.snapshot([Wire.course("1", scores: Wire.scores(90))], items: [
        Wire.item("a1", course: course, points: 10, dueInHours: 30),
        Wire.item("a2", course: course, points: 10, dueInHours: 60),
    ], fetchedAt: Wire.now.addingTimeInterval(Wire.hour))

    @Test("Available: the score change is reported; kept outside Canvas: it is not, and the other changes still count")
    func scoreChangeFollowsAvailability() {
        let automatic = ChangeDigest.diff(old: Self.old, new: Self.new)
        #expect(automatic.courseScoreChanges == [.init(courseID: Self.course.id, previousScore: 80, newScore: 90)])
        #expect(automatic.count == 2)

        let outside = ChangeDigest.diff(
            old: Self.old, new: Self.new,
            gradeAvailability: GradeAvailabilityIndex(snapshot: Self.new, overrides: [Self.course.id: .keptOutsideCanvas],
                                                      now: Self.new.fetchedAt))
        #expect(outside.courseScoreChanges.isEmpty)
        #expect(outside.newAssignments.map(\.assignmentID) == ["a2"])
        #expect(outside.count == 1)
    }

    @Test("Letters only and hidden totals are never reported, as before")
    func lettersOnlyAndHiddenAreNot() {
        for visibility in [GradeVisibility.lettersOnly, .hiddenTotals] {
            let old = Wire.snapshot([Wire.course("1", visibility, scores: Wire.scores(80, grade: "B-"))])
            let new = Wire.snapshot([Wire.course("1", visibility, scores: Wire.scores(90, grade: "A-"))])
            #expect(ChangeDigest.diff(old: old, new: new).courseScoreChanges.isEmpty, "\(visibility)")
        }
    }

    @Test("The default index is the new snapshot's, at its fetch time, with no override")
    func defaultIndexIsTheNewSnapshots() async throws {
        let previous = try await Wire.persona("flagship-previous")
        let current = try await Wire.persona("flagship")
        // "All": MATH 122's real 0.01-point move (ChangeDigestFixtureTests) is reported, so the guard is exercised.
        let all = DigestThresholds(global: .all)
        let automatic = ChangeDigest.diff(old: previous, new: current, thresholds: all)
        let explicit = ChangeDigest.diff(old: previous, new: current, thresholds: all,
                                         gradeAvailability: GradeAvailabilityIndex(snapshot: current, overrides: [:],
                                                                                   now: current.fetchedAt))
        #expect(automatic == explicit)
        #expect(automatic.courseScoreChanges.map(\.courseID) == ["51842"])
    }
}
