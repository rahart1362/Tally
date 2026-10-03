import Foundation
import Testing
import TallyTestSupport
@testable import TallyStore
@testable import TallyDomain

/// WP-C03: a small first-paint/widget projection derived only from the snapshot, with grades
/// opt-in per encryption.md D-E3 and a size budget from `TallyConfig`.
@Suite("GlanceProjectionBuilder: content allowlist and size budget")
struct GlanceProjectionTests {
    @Test func gradesAreOmittedByDefault() {
        let snapshot = CanvasSnapshotFixture.make(courseCount: 3)
        let glance = GlanceProjectionBuilder.build(from: snapshot, includeGrades: false)
        #expect(glance.overallGradeBand == nil)
        #expect(glance.courses.allSatisfy { $0.currentGrade == nil })
    }

    @Test func gradesAppearOnlyWhenOptedIn() {
        let snapshot = CanvasSnapshotFixture.make(courseCount: 3)
        let glance = GlanceProjectionBuilder.build(from: snapshot, includeGrades: true)
        #expect(glance.overallGradeBand != nil)
        #expect(glance.courses.contains { $0.currentGrade != nil })
    }

    @Test func hiddenTotalsNeverShowABandEvenWhenOptedIn() {
        let snapshot = CanvasSnapshotFixture.make(courseCount: 2, hiddenTotalsForFirstCourse: true)
        let glance = GlanceProjectionBuilder.build(from: snapshot, includeGrades: true)
        #expect(glance.courses[0].currentGrade == nil, "the teacher withheld this course's total")
        #expect(glance.courses[1].currentGrade != nil)
    }

    @Test func generationAndAsOfComeFromTheSnapshot() {
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = CanvasSnapshotFixture.make(generation: 42, fetchedAt: fetchedAt)
        let glance = GlanceProjectionBuilder.build(from: snapshot, includeGrades: false)
        #expect(glance.generation == 42)
        #expect(glance.asOf == fetchedAt)
    }

    @Test func dueItemsAreSortedEarliestFirstAndCappedAtTheConfiguredLimit() {
        let snapshot = CanvasSnapshotFixture.make(courseCount: 1, dueItemCount: TallyConfig.glanceDueItemLimit + 5)
        let glance = GlanceProjectionBuilder.build(from: snapshot, includeGrades: false)
        #expect(glance.dueSoon.count == TallyConfig.glanceDueItemLimit)
        #expect(glance.dueSoon == glance.dueSoon.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) })
    }

    @Test func titlesAreTruncatedToTheConfiguredLength() {
        let snapshot = CanvasSnapshotFixture.make(dueItemCount: 1)
        let glance = GlanceProjectionBuilder.build(from: snapshot, includeGrades: false)
        #expect(glance.dueSoon[0].title.count <= TallyConfig.glanceTitleMaxLength)
    }

    @Test func completedMarkedDoneItemsAreExcludedFromDueSoon() {
        var snapshot = CanvasSnapshotFixture.make(courseCount: 1, dueItemCount: 0)
        let done = PlannerItem(id: "assignment:done", courseID: snapshot.courses.first?.id, title: "Finished thing",
                                plannableType: "assignment", dueAt: snapshot.fetchedAt, pointsPossible: 10,
                                submitted: true, graded: true, missing: false, late: false, excused: false,
                                markedComplete: true, htmlURL: nil)
        snapshot = CanvasSnapshot(generation: snapshot.generation, accountKey: snapshot.accountKey, host: snapshot.host,
                                   fetchedAt: snapshot.fetchedAt, profile: snapshot.profile, courses: snapshot.courses,
                                   groups: snapshot.groups, gradingPeriods: snapshot.gradingPeriods, planner: [done],
                                   events: snapshot.events, announcements: snapshot.announcements,
                                   courseColors: snapshot.courseColors, sections: snapshot.sections)
        let glance = GlanceProjectionBuilder.build(from: snapshot, includeGrades: false)
        #expect(glance.dueSoon.isEmpty)
    }

    /// M3-D2 (UX-WP-18, PMO R16): the "Mark Done" button's write (`UserState.doneAssignments`)
    /// takes an otherwise-open item off the widget, the same as a submitted one; a planner item of
    /// another plannable type with a numerically matching ID is untouched, since `doneAssignments`
    /// is scoped to `CanvasID<Assignment>` (`GlancePlannerID.assignmentID`).
    @Test func doneAssignmentsAreExcludedFromDueSoon() {
        var snapshot = CanvasSnapshotFixture.make(courseCount: 1, dueItemCount: 0)
        let courseID = snapshot.courses.first?.id
        let done = PlannerItem(id: "assignment:9001", courseID: courseID, title: "Marked done in Tally",
                               plannableType: "assignment", dueAt: snapshot.fetchedAt, pointsPossible: 10,
                               submitted: false, graded: false, missing: false, late: false, excused: false,
                               markedComplete: false, htmlURL: nil)
        let quiz = PlannerItem(id: "quiz:9001", courseID: courseID, title: "Same numeric ID, a quiz",
                               plannableType: "quiz", dueAt: snapshot.fetchedAt, pointsPossible: 10,
                               submitted: false, graded: false, missing: false, late: false, excused: false,
                               markedComplete: false, htmlURL: nil)
        snapshot = CanvasSnapshot(generation: snapshot.generation, accountKey: snapshot.accountKey, host: snapshot.host,
                                  fetchedAt: snapshot.fetchedAt, profile: snapshot.profile, courses: snapshot.courses,
                                  groups: snapshot.groups, gradingPeriods: snapshot.gradingPeriods, planner: [done, quiz],
                                  events: snapshot.events, announcements: snapshot.announcements,
                                  courseColors: snapshot.courseColors, sections: snapshot.sections)
        let untouched = GlanceProjectionBuilder.build(from: snapshot, includeGrades: false)
        #expect(untouched.dueSoon.map(\.id).sorted() == ["assignment:9001", "quiz:9001"])

        let glance = GlanceProjectionBuilder.build(from: snapshot, includeGrades: false, doneAssignments: [CanvasID("9001")])
        #expect(glance.dueSoon.map(\.id) == ["quiz:9001"], "the done assignment is left out; the quiz of the same numeric ID is not")
    }

    @Test func glancePlannerIDOnlyMapsAssignmentItems() {
        #expect(GlancePlannerID.assignmentID("assignment:123") == CanvasID("123"))
        #expect(GlancePlannerID.assignmentID("quiz:123") == nil)
        #expect(GlancePlannerID.assignmentID("assignment:") == nil, "an empty ID never maps")
        #expect(GlancePlannerID.assignmentID("garbage") == nil)
    }

    /// A regression guard: the allowlist (encryption.md §3.3) must never grow by accident. If a
    /// field is added to `GlanceProjection`/`GlanceCourse`/`GlanceDueItem`, this test's expected
    /// key sets must be updated deliberately, in the same review as the addition.
    @Test func codableKeySetMatchesTheAllowlistExactly() throws {
        let snapshot = CanvasSnapshotFixture.make(courseCount: 1, dueItemCount: 1)
        let glance = GlanceProjectionBuilder.build(from: snapshot, includeGrades: true)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(glance)) as! [String: Any]

        // Plan 08 XG-02 (schema 2): `gradeSummary` replaced `overallGradeBand`; each course gained
        // `gradeStatus` (a state, never a grade value).
        #expect(Set(json.keys) == ["schemaVersion", "generation", "asOf", "gradeSummary", "courses", "dueSoon"])

        // PAY-04 (M3-B1): `entitledUntil`, an expiry date only, present when the gate mirrors one
        // (encryption.md §3.3). Absent above: no entitlement mirrored.
        let entitled = GlanceProjectionBuilder.build(from: snapshot, includeGrades: true,
                                                     entitledUntil: Date(timeIntervalSince1970: 1_800_000_000))
        let entitledJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entitled)) as! [String: Any]
        #expect(Set(entitledJSON.keys) == ["schemaVersion", "generation", "asOf", "gradeSummary", "courses", "dueSoon",
                                           "entitledUntil"])
        #expect(entitledJSON["entitledUntil"] is Double, "a date, never a receipt or a transaction ID")
        #expect(Set((json["gradeSummary"] as! [String: Any]).keys) == ["state", "band"])

        let course = (json["courses"] as! [[String: Any]])[0]
        #expect(Set(course.keys) == ["id", "shortCode", "currentGrade", "gradeStatus"])

        let due = (json["dueSoon"] as! [[String: Any]])[0]
        #expect(Set(due.keys) == ["id", "courseShortCode", "title", "dueAt", "missing", "late", "excused", "submitted"])

        // Never included, even indirectly: instructor names, the user's name, or the host.
        let flatKeys = Set(json.keys).union(course.keys).union(due.keys)
        for forbidden in ["instructor", "teacher", "userName", "name", "host", "email", "token"] {
            #expect(!flatKeys.contains(forbidden))
        }
    }

    @Test func staysWithinTheConfiguredSizeBudgetEvenForALargeSnapshot() throws {
        let snapshot = CanvasSnapshotFixture.make(courseCount: 40, dueItemCount: 200)
        let glance = GlanceProjectionBuilder.build(from: snapshot, includeGrades: true)
        let size = try JSONEncoder().encode(glance).count
        #expect(size <= TallyConfig.glanceSizeBudgetBytes,
                "glance is \(size) bytes; budget is \(TallyConfig.glanceSizeBudgetBytes)")
    }

    @Test func roundTripsThroughCodable() throws {
        let snapshot = CanvasSnapshotFixture.make(courseCount: 2, dueItemCount: 2)
        let glance = GlanceProjectionBuilder.build(from: snapshot, includeGrades: true)
        let decoded = try JSONDecoder().decode(GlanceProjection.self, from: JSONEncoder().encode(glance))
        #expect(decoded == glance)
    }
}
