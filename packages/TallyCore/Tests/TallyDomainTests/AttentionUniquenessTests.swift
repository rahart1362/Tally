import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

/// R-3 (resilience.md, crash-safety-2.md F-7): "Needs attention" never repeats a row ID. A row's
/// `id` is its alert's `dedupeKey`, and SwiftUI's `ForEach` needs unique IDs. Valid data repeated
/// one: A2 groups closed missing work per course (`missingClosed:<course>`), so two closed missing
/// assignments in one course gave two rows with one ID (CS-07 observed
/// `["missingClosed:c1", "missingClosed:c1"]`). Now there is one row per key: the highest severity,
/// then the first. The three-row cap is unchanged.
@Suite("Needs attention: one row per ID (R-3)", .timeLimit(.minutes(TestTimeBudget.minutes(1))))
struct AttentionUniquenessTests {
    private let now = DuplicateIDFixture.now

    private func course(_ id: CanvasID<Course>, _ code: String) -> Course {
        Course(id: id, name: code, courseCode: code, term: nil, teachers: [], timeZone: nil, appliesGroupWeights: false,
               hasGradingPeriods: false, currentGradingPeriodID: nil, gradeVisibility: .visible,
               scores: ComputedScores(currentScore: 80, finalScore: 80, currentGrade: nil, finalGrade: nil),
               currentPeriodScores: nil, htmlURL: nil)
    }

    /// Missing work due `dueInDays` from now, locked (closed) `lockInDays` from now.
    private func missing(_ id: CanvasID<Assignment>, _ name: String, in courseID: CanvasID<Course>,
                         dueInDays: Double, lockInDays: Double) -> Assignment {
        Assignment(id: id, courseID: courseID, groupID: CanvasID("g-\(courseID.rawValue)"), name: name,
                   dueAt: now.addingTimeInterval(dueInDays * 86_400), lockAt: now.addingTimeInterval(lockInDays * 86_400),
                   pointsPossible: 10, gradingType: .points, omitFromFinalGrade: false, htmlURL: nil,
                   submission: Submission(score: nil, grade: nil, submittedAt: nil, gradedAt: nil, postedAt: nil,
                                          excused: false, missing: true, late: false, workflowState: "unsubmitted"),
                   submissionTypes: ["online_upload"])
    }

    private func snapshot(_ assignments: [Assignment], courses: [Course]) -> CanvasSnapshot {
        var groups: [CanvasID<Course>: [AssignmentGroup]] = [:]
        for course in courses {
            groups[course.id] = [AssignmentGroup(id: CanvasID("g-\(course.id.rawValue)"), name: "G", position: 1, weight: nil,
                                                 rules: DropRules(), assignments: assignments.filter { $0.courseID == course.id })]
        }
        return CanvasSnapshot(generation: 1, accountKey: AccountKey("r3"), host: "canvas.fixtures.example", fetchedAt: now,
                              profile: UserProfile(id: "1", name: "S", shortName: nil, timeZone: nil, calendarFeedURL: nil),
                              courses: courses, groups: groups, gradingPeriods: [:], planner: [], events: [], announcements: [],
                              courseColors: [:], sections: [:])
    }

    @Test func twoClosedMissingAssignmentsInOneCourseGiveOneRow() {
        let snapshot = snapshot([missing("a1", "Lab 1", in: "c1", dueInDays: -9, lockInDays: -2),
                                 missing("a2", "Lab 2", in: "c1", dueInDays: -8, lockInDays: -1)],
                                courses: [course("c1", "BIO 101")])
        let attention = DashboardBuilder.build(from: snapshot, digest: nil, digestAsOf: nil, now: now).needsAttention
        #expect(attention.map(\.id) == ["missingClosed:c1"])
    }

    /// The same key at two severities keeps the higher, in the first one's place; at one
    /// severity it keeps the first. A repeated assignment ID only reaches here from data that
    /// bypassed the gateway, but the rule has to hold for it too.
    @Test func theRowKeptHasTheHighestSeverityThenComesFirst() {
        let courses = [course("c1", "BIO 101")]
        // Missing and open: High when the lock is weeks away, Critical when it is within the window.
        let high = missing("a1", "Lab 1 (first)", in: "c1", dueInDays: -2, lockInDays: 20)
        let critical = missing("a1", "Lab 1 (critical repeat)", in: "c1", dueInDays: -2, lockInDays: 0.5)
        let highRepeat = missing("a1", "Lab 1 (high repeat)", in: "c1", dueInDays: -2, lockInDays: 25)

        let escalated = DashboardBuilder.build(from: snapshot([high, critical], courses: courses), digest: nil, digestAsOf: nil,
                                               now: now).needsAttention
        #expect(escalated.map(\.id) == ["missing:a1"])
        #expect(escalated.first?.severity == .critical)
        #expect(escalated.first?.title == "Lab 1 (critical repeat) is missing")

        let level = DashboardBuilder.build(from: snapshot([high, highRepeat], courses: courses), digest: nil, digestAsOf: nil,
                                           now: now).needsAttention
        #expect(level.map(\.id) == ["missing:a1"])
        #expect(level.first?.title == "Lab 1 (first) is missing")
    }

    /// The cap counts rows, not alerts: a repeated key no longer takes one of the three slots. The
    /// repeat here is a High alert (a repeated assignment ID), so it outranks the Medium rows and
    /// would always have taken a slot; rows of equal rank from different courses come in
    /// `Dictionary` order, which changes between processes, so the check is on the set.
    @Test func theCapStillShowsThreeDifferentRows() {
        let courses = [course("c1", "BIO 101"), course("c2", "HIS 210"), course("c3", "CHEM 110")]
        let snapshot = snapshot([missing("a1", "Lab 1", in: "c1", dueInDays: -2, lockInDays: 20),
                                 missing("a1", "Lab 1 (repeat)", in: "c1", dueInDays: -2, lockInDays: 25),
                                 missing("a3", "Essay", in: "c2", dueInDays: -9, lockInDays: -2),
                                 missing("a4", "Titration", in: "c3", dueInDays: -9, lockInDays: -2)],
                                courses: courses)
        let attention = DashboardBuilder.build(from: snapshot, digest: nil, digestAsOf: nil, now: now).needsAttention
        #expect(attention.count == 3)
        #expect(Set(attention.map(\.id)) == ["missing:a1", "missingClosed:c2", "missingClosed:c3"])
    }

    // MARK: - Every persona and the stress account

    /// Several instants, so assignments move from due soon to missing to closed.
    private static let instants: [Date] = [-7, 0, 7, 30, 90].map {
        DuplicateIDFixture.now.addingTimeInterval(Double($0) * 86_400)
    }

    private func expectUniqueIDs(_ projection: DashboardProjection, _ label: String) {
        func unique<ID: Hashable>(_ ids: [ID], _ list: String) {
            #expect(Set(ids).count == ids.count, "\(label) \(list): \(ids)")
        }
        unique(projection.nextUp.map(\.id), "nextUp")
        unique(projection.needsAttention.map(\.id), "needsAttention")
        unique(projection.dueSoon.map(\.id), "dueSoon")
        unique(projection.weekAhead.map(\.id), "weekAhead")
    }

    @Test(arguments: Fixtures.personas)
    func everyPersonaProjectsUniqueIDs(_ persona: String) async throws {
        let snapshot = try await PersonaSnapshotHarness.fetchSnapshot(persona: persona, now: now)
        for instant in Self.instants {
            expectUniqueIDs(DashboardBuilder.build(from: snapshot, digest: nil, digestAsOf: nil, now: instant), "\(persona) at \(instant)")
        }
    }

    @Test func theStressAccountProjectsUniqueIDs() {
        let snapshot = StressSnapshotFixture.make(scale: .stress)
        for instant in Self.instants {
            expectUniqueIDs(DashboardBuilder.build(from: snapshot, digest: nil, digestAsOf: nil, now: instant), "stress at \(instant)")
        }
    }
}
