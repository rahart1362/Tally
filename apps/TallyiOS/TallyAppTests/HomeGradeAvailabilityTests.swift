import Foundation
import Testing
import TallyDomain
import TallyStore
import TallyTestSupport
@testable import TallyFeatures

/// Plan 08 XG-02, §4.4 rows 17 and 18, in the app: `HomeProjector` builds one
/// `GradeAvailabilityIndex` per projection and hands it to the dashboard, the course rows and the
/// To-Do priority. Synthetic personas only (`fixtures/canvas/personas`).
@Suite("Home rows and To-Do priority follow grade availability (plan 08 XG-02)")
struct HomeGradeAvailabilityTests {
    /// The fixtures' anchor, 2026-09-28T13:00:00Z.
    private static let anchor = Date(timeIntervalSince1970: 1_790_600_400)

    private static func persona(_ name: String) async throws -> CanvasSnapshot {
        try await PersonaSnapshotHarness.fetchSnapshot(persona: name, now: anchor)
    }

    @Test("Row 17: the projector's course rows carry each course's state; a grade only for an available course")
    func courseRowsCarryAvailability() async throws {
        let snapshot = try await Self.persona("external-grades")
        let projector = HomeProjector(calendar: Calendar(identifier: .gregorian), locale: Locale(identifier: "en_US"))
        await projector.install(HomeUpdate(generation: 1, snapshot: snapshot, digest: nil, digestAsOf: nil, freshness: .noCache))
        let projection = try #require(await projector.project(now: Self.anchor))

        let rows = Dictionary(uniqueKeysWithValues: projection.courses.map { ($0.code, $0) })
        #expect(rows.mapValues(\.gradeAvailability) == [
            "ENG-10": .keptOutsideCanvas(.init(pastDueItems: 8, submittedOrOfflineItems: 8)),
            "ALG2": .keptOutsideCanvas(.init(pastDueItems: 9, submittedOrOfflineItems: 9)),
            "BIO-H": .keptOutsideCanvas(.init(pastDueItems: 8, submittedOrOfflineItems: 8)),
            "ART-1": .notYetPosted, "ADVISORY": .notGradedInCanvas, "SPAN-2": .available,
        ])
        #expect(rows["SPAN-2"]?.percent == 91.39)
        #expect(rows["SPAN-2"]?.letterGrade == "A-")
        #expect(rows.values.filter { $0.code != "SPAN-2" }.allSatisfy { $0.percent == nil && $0.letterGrade == nil })
        // ENG-10's Canvas final grade is "F" for a course with nothing graded: never shown.
        #expect(rows["ENG-10"]?.letterGrade == nil)

        // The same index drives the dashboard's hero (row 1).
        #expect(projection.dashboard.hero.averagedCount == 1)
        #expect(projection.dashboard.hero.overallPercent == 91.39)
        #expect(projection.dashboard.hero.school == .mixed(outside: 3))
    }

    @Test("Row 17: an override (kept outside Canvas) hides a Canvas grade; an unknown course shows none")
    func courseRowFollowsTheState() async throws {
        let snapshot = try await Self.persona("external-grades")
        let spanish = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
        let index = GradeAvailabilityIndex(snapshot: snapshot, overrides: [spanish.id: .keptOutsideCanvas], now: Self.anchor)
        let overridden = HomeProjector.courseRow(spanish, availability: index[spanish.id])
        #expect(overridden.percent == nil && overridden.letterGrade == nil)
        guard case .keptOutsideCanvas = overridden.gradeAvailability else {
            Issue.record("SPAN-2 with the override is \(overridden.gradeAvailability)")
            return
        }
        let unknown = HomeProjector.courseRow(spanish, availability: nil)
        #expect(unknown.percent == nil && unknown.gradeAvailability == .notYetPosted)
    }

    @Test("Row 17: the flagship rows are unchanged (every course available, with its percent and letter)")
    func flagshipRowsAreUnchanged() async throws {
        let snapshot = try await Self.persona("flagship")
        let projector = HomeProjector(calendar: Calendar(identifier: .gregorian), locale: Locale(identifier: "en_US"))
        await projector.install(HomeUpdate(generation: 1, snapshot: snapshot, digest: nil, digestAsOf: nil, freshness: .noCache))
        let projection = try #require(await projector.project(now: Self.anchor))
        #expect(projection.courses.map(\.percent) == snapshot.courses.map { $0.scores?.currentScore })
        #expect(projection.courses.map(\.letterGrade) == snapshot.courses.map { $0.scores?.currentGrade })
        #expect(projection.courses.allSatisfy { $0.gradeAvailability == .available })
        #expect(projection.dashboard.hero.averagedCount == 5)
    }

    @Test("Row 2: the launch paint's hero is the full projection's but for the percentage (Average of 1 course)")
    func launchPaintHeroMatchesTheProjection() async throws {
        let snapshot = try await Self.persona("external-grades")
        let projector = HomeProjector(calendar: Calendar(identifier: .gregorian), locale: Locale(identifier: "en_US"))
        await projector.install(HomeUpdate(generation: 1, snapshot: snapshot, digest: nil, digestAsOf: nil, freshness: .noCache))
        let projected = try #require(await projector.project(now: Self.anchor)).dashboard.hero
        for includeGrades in [false, true] {
            let glance = GlanceProjectionBuilder.build(from: snapshot, includeGrades: includeGrades)
            let launch = HomeGlance.make(from: glance, now: Self.anchor).dashboard.hero
            #expect(launch.averagedCount == 1)
            #expect(launch.courseCount == projected.courseCount)
            #expect(launch.averagedCount == projected.averagedCount)
            #expect(launch.exclusions == projected.exclusions)
            #expect(launch.school == projected.school)
            #expect(launch.overallPercent == nil)
            #expect(launch.overallBand == (includeGrades ? projected.overallBand : nil))
        }
    }

    /// 80.5 is within `InsightsConfig.priorityBoundaryWindow` above the 80 cutoff: near a boundary.
    private static func nearBoundaryCourse() -> (Course, Assignment) {
        let course = Course(id: "700", name: "Synthetic 700", courseCode: "SYN-700", term: nil, teachers: [], timeZone: nil,
                            appliesGroupWeights: false, hasGradingPeriods: false, currentGradingPeriodID: nil,
                            gradeVisibility: .visible,
                            scores: ComputedScores(currentScore: 80.5, finalScore: 80.5, currentGrade: "B-", finalGrade: nil),
                            currentPeriodScores: nil, htmlURL: nil)
        let assignment = Assignment(
            id: "7001", courseID: course.id, groupID: "70", name: "Item", dueAt: anchor.addingTimeInterval(30 * 3600),
            lockAt: nil, pointsPossible: 10, gradingType: .points, omitFromFinalGrade: false, htmlURL: nil,
            submission: nil, published: true, submissionTypes: ["online_upload"])
        return (course, assignment)
    }

    @Test("Row 18: the To-Do priority's near-boundary modifier applies only to an available course")
    func toDoPriorityFollowsAvailability() {
        let (course, assignment) = Self.nearBoundaryCourse()
        let available = ToDoBuilder.priority(assignment: assignment, course: course, availability: .available,
                                             weight: 0.1, now: Self.anchor)
        let plain = PriorityScore.score(hoursUntilDue: 30, courseWeight: 0.1)
        #expect(available == PriorityScore.score(hoursUntilDue: 30, courseWeight: 0.1, modifiers: .init(nearBoundary: true)))
        #expect(available > plain)
        for state: GradeAvailability? in [.lettersOnly, .hiddenByInstructor, .notYetPosted, .notGradedInCanvas,
                                          .keptOutsideCanvas(.init(pastDueItems: 5, submittedOrOfflineItems: 3)), nil] {
            #expect(ToDoBuilder.priority(assignment: assignment, course: course, availability: state, weight: 0.1,
                                         now: Self.anchor) == plain, "\(String(describing: state))")
        }
    }

    @Test("Row 18: no visible change today: every To-Do priority equals the old visible-score rule",
          arguments: ["flagship", "finals", "grading-periods", "large", "external-grades"])
    func toDoPriorityIsUnchangedWithoutOverrides(persona: String) async throws {
        let snapshot = try await Self.persona(persona)
        let index = GradeAvailabilityIndex(snapshot: snapshot, overrides: [:], now: Self.anchor)
        var compared = 0
        for course in snapshot.courses {
            let groups = snapshot.groups[course.id] ?? []
            let weights = PriorityScore.WeightContext(course: course, groups: groups,
                                                      gradingPeriods: snapshot.gradingPeriods[course.id] ?? [])
            // The rule at 47a461c (`ToDoProjection.swift:221`): the score when the course shows percentages.
            let oldScore = course.gradeVisibility == .visible ? course.scores?.currentScore : nil
            let (belowGoal, nearBoundary) = PriorityScore.courseModifiers(currentScore: oldScore, goal: nil)
            for assignment in groups.flatMap(\.assignments) {
                let weight = weights.weight(of: assignment)
                let overdueStillOpen = (assignment.dueAt.map { $0 < Self.anchor } ?? false)
                    && (assignment.lockAt.map { $0 > Self.anchor } ?? true)
                let old = PriorityScore.score(
                    hoursUntilDue: assignment.dueAt.map { $0.timeIntervalSince(Self.anchor) / 3600 }, courseWeight: weight,
                    modifiers: .init(overdueStillOpen: overdueStillOpen, courseBelowGoal: belowGoal, nearBoundary: nearBoundary))
                #expect(ToDoBuilder.priority(assignment: assignment, course: course, availability: index[course.id],
                                             weight: weight, now: Self.anchor) == old)
                compared += 1
            }
        }
        #expect(compared > 0)
        // The screens built with the projector's index are the screens built without one.
        let formatter = ScreenFixtures.formatter()
        #expect(ScreenProjections.build(from: snapshot, formatter: formatter, gradeAvailability: index)
                == ScreenProjections.build(from: snapshot, formatter: formatter))
    }
}
