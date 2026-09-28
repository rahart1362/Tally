import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

@Suite("ChangeDigest.diff: pure, Canvas-ID-keyed snapshot comparison")
struct ChangeDigestTests {
    let now = TestClock().now()
    let course: CanvasID<Course> = "51845"

    private func assignment(
        id: CanvasID<Assignment> = "1204400", dueAt: Date?, score: Double? = nil, postedAt: Date? = nil,
        submissionID: CanvasID<Submission>? = "9001", pointsPossible: Double? = 100
    ) -> Assignment {
        let submission: Submission? = (score == nil && postedAt == nil) ? nil : Submission(
            score: score, grade: nil, submittedAt: now, gradedAt: postedAt, postedAt: postedAt,
            excused: false, missing: false, late: false, workflowState: "graded", id: submissionID)
        return Assignment(id: id, courseID: course, groupID: "51842", name: "Lab Report", dueAt: dueAt, lockAt: nil,
                          pointsPossible: pointsPossible, gradingType: .points, omitFromFinalGrade: false,
                          htmlURL: nil, submission: submission)
    }

    private func snapshot(
        generation: UInt64 = 1, assignments: [Assignment] = [], announcements: [Announcement] = [],
        courseScore: Double? = 90, gradeVisibility: GradeVisibility = .visible
    ) -> CanvasSnapshot {
        let group = AssignmentGroup(id: "51842", name: "Labs", position: 1, weight: 40, rules: DropRules(), assignments: assignments)
        let courseValue = Course(id: course, name: "Biology 101", courseCode: "BIO 101", term: nil, teachers: [], timeZone: nil,
                                 appliesGroupWeights: true, hasGradingPeriods: false, currentGradingPeriodID: nil,
                                 gradeVisibility: gradeVisibility,
                                 scores: courseScore.map { ComputedScores(currentScore: $0, finalScore: $0, currentGrade: nil, finalGrade: nil) },
                                 currentPeriodScores: nil, htmlURL: nil)
        return CanvasSnapshot(
            generation: generation, accountKey: AccountKey("a1b2c3"), host: "canvas.northfield.example", fetchedAt: now,
            profile: UserProfile(id: "4820117", name: "Alex Sample", shortName: "Alex", timeZone: nil, calendarFeedURL: nil),
            courses: [courseValue], groups: [course: [group]], gradingPeriods: [:], planner: [], events: [],
            announcements: announcements, courseColors: [:],
            sections: Dictionary(uniqueKeysWithValues: SnapshotSection.allCases.filter(\.isRequired).map {
                ($0, SectionStatus(fetchedAt: now, carriedForward: false))
            }))
    }

    // MARK: - First snapshot

    @Test func firstSnapshotProducesAnEmptyDigest() {
        let digest = ChangeDigest.diff(old: nil, new: snapshot(assignments: [assignment(dueAt: now)]))
        #expect(digest == .empty)
        #expect(digest.isEmpty)
        #expect(digest.count == 0)
    }

    @Test func identicalSnapshotsProduceAnEmptyDigest() {
        let snap = snapshot(assignments: [assignment(dueAt: now, score: 92, postedAt: now)])
        let digest = ChangeDigest.diff(old: snap, new: snap)
        #expect(digest.isEmpty)
    }

    // MARK: - New assignment

    @Test func newAssignmentIDIsReportedOnce() {
        let old = snapshot(assignments: [])
        let new = snapshot(assignments: [assignment(id: "1204439", dueAt: now)])
        let digest = ChangeDigest.diff(old: old, new: new)
        #expect(digest.newAssignments == [ChangeDigest.NewAssignment(courseID: course, assignmentID: "1204439", dueAt: now)])
        #expect(digest.gradeChanges.isEmpty)
        #expect(digest.dueDateChanges.isEmpty)
    }

    // MARK: - Due-date change

    @Test func dueDateChangeOnAnExistingAssignmentIsReported() {
        let old = snapshot(assignments: [assignment(dueAt: now)])
        let laterDue = now.addingTimeInterval(2 * 24 * 3600)
        let new = snapshot(assignments: [assignment(dueAt: laterDue)])
        let digest = ChangeDigest.diff(old: old, new: new)
        #expect(digest.dueDateChanges == [ChangeDigest.DueDateChange(courseID: course, assignmentID: "1204400",
                                                                     previousDueAt: now, newDueAt: laterDue)])
        #expect(digest.newAssignments.isEmpty) // present in both -> not "new"
    }

    @Test func unchangedDueDateIsNotReported() {
        let old = snapshot(assignments: [assignment(dueAt: now)])
        let new = snapshot(assignments: [assignment(dueAt: now)])
        #expect(ChangeDigest.diff(old: old, new: new).dueDateChanges.isEmpty)
    }

    // MARK: - Grade changes (new or changed scores; "newly graded work")

    @Test func aNewlyPostedScoreIsReportedAsAGradeChangeFromNil() {
        let old = snapshot(assignments: [assignment(dueAt: now)]) // no submission yet
        let new = snapshot(assignments: [assignment(dueAt: now, score: 92, postedAt: now, pointsPossible: 100)])
        let digest = ChangeDigest.diff(old: old, new: new)
        #expect(digest.gradeChanges == [ChangeDigest.GradeChange(courseID: course, assignmentID: "1204400", submissionID: "9001",
                                                                 previousScore: nil, newScore: 92, pointsPossible: 100)])
    }

    @Test func aChangedPostedScoreIsReportedWithItsPreviousValue() {
        let old = snapshot(assignments: [assignment(dueAt: now, score: 80, postedAt: now)])
        let regradedAt = now.addingTimeInterval(3600)
        let new = snapshot(assignments: [assignment(dueAt: now, score: 88, postedAt: regradedAt)])
        let digest = ChangeDigest.diff(old: old, new: new)
        #expect(digest.gradeChanges.map(\.previousScore) == [80])
        #expect(digest.gradeChanges.map(\.newScore) == [88])
    }

    @Test func anUnpostedScoreIsNeverReported() {
        // Canvas can carry a score before posting it; postedAt == nil means "not shown to the student".
        let old = snapshot(assignments: [assignment(dueAt: now)])
        let new = snapshot(assignments: [assignment(dueAt: now, score: 92, postedAt: nil)])
        #expect(ChangeDigest.diff(old: old, new: new).gradeChanges.isEmpty)
    }

    @Test func anUnchangedPostedScoreIsNotReported() {
        let snap = snapshot(assignments: [assignment(dueAt: now, score: 92, postedAt: now)])
        #expect(ChangeDigest.diff(old: snap, new: snap).gradeChanges.isEmpty)
    }

    // MARK: - New announcements

    @Test func newAnnouncementIDsAreReportedAndExistingOnesAreNot() {
        let existing = Announcement(id: "2551000", courseID: course, title: "Guest lecture", postedAt: now, isRead: true, htmlURL: nil)
        let added = Announcement(id: "2551005", courseID: course, title: "Problem Set 6 graded", postedAt: now, isRead: false, htmlURL: nil)
        let old = snapshot(announcements: [existing])
        let new = snapshot(announcements: [existing, added])
        let digest = ChangeDigest.diff(old: old, new: new)
        #expect(digest.newAnnouncements == [ChangeDigest.NewAnnouncement(courseID: course, announcementID: "2551005", postedAt: now)])
    }

    // MARK: - Course-score deltas at or above a threshold

    @Test func courseScoreDeltaAtOrAboveTheThresholdIsReported() {
        let old = snapshot(courseScore: 90.0)
        let new = snapshot(courseScore: 90.5) // delta exactly 0.5, the default threshold's own boundary ("at or above")
        let digest = ChangeDigest.diff(old: old, new: new)
        #expect(digest.courseScoreChanges == [ChangeDigest.CourseScoreChange(courseID: course, previousScore: 90.0, newScore: 90.5)])
        #expect(digest.courseScoreChanges.first?.delta == 0.5)
    }

    @Test func courseScoreDeltaBelowTheThresholdIsNotReported() {
        // Matches the flagship fixture's MATH 122 change: 90.09 -> 90.10, a 0.01 pt
        // move that Tally's own threshold (0.5) filters out (see the fixture-driven test).
        let old = snapshot(courseScore: 90.09)
        let new = snapshot(courseScore: 90.10)
        #expect(ChangeDigest.diff(old: old, new: new).courseScoreChanges.isEmpty)
    }

    @Test func courseScoreDeltaIsReportedInEitherDirection() {
        let old = snapshot(courseScore: 90.0)
        let new = snapshot(courseScore: 88.0)
        let digest = ChangeDigest.diff(old: old, new: new)
        #expect(digest.courseScoreChanges.first?.delta == -2.0)
    }

    @Test func hiddenTotalsCoursesNeverProduceACourseScoreChange() {
        let old = snapshot(courseScore: 90, gradeVisibility: .hiddenTotals)
        let new = snapshot(courseScore: 95, gradeVisibility: .hiddenTotals)
        #expect(ChangeDigest.diff(old: old, new: new).courseScoreChanges.isEmpty)
    }

    @Test func aCustomThresholdOverridesTheDefault() {
        let old = snapshot(courseScore: 90.0)
        let new = snapshot(courseScore: 90.2)
        #expect(ChangeDigest.diff(old: old, new: new, thresholds: DigestThresholds(global: .points(1.0))).courseScoreChanges.isEmpty)
        #expect(!ChangeDigest.diff(old: old, new: new, thresholds: DigestThresholds(global: .points(0.1))).courseScoreChanges.isEmpty)
    }

    // MARK: Owner decision 2026-09-27: 0.5 pt default, "All" or a per-course threshold.

    @Test func defaultIsHalfAPointAndAllReportsTinyChanges() {
        let old = snapshot(courseScore: 90.0)
        let tiny = snapshot(courseScore: 90.01)
        #expect(DigestThresholds.default.threshold(for: course) == .points(0.5))
        #expect(ChangeDigest.diff(old: old, new: tiny).courseScoreChanges.isEmpty)
        #expect(ChangeDigest.diff(old: old, new: tiny, thresholds: DigestThresholds(global: .all)).courseScoreChanges.count == 1)
        #expect(ChangeDigest.diff(old: old, new: old, thresholds: DigestThresholds(global: .all)).courseScoreChanges.isEmpty, "no change, nothing to report")
    }

    @Test func perCourseOverrideBeatsTheGlobalSettingInBothDirections() {
        let old = snapshot(courseScore: 90.0)
        let small = snapshot(courseScore: 89.8) // a 0.2 pt drop
        let loose = DigestThresholds(global: .points(0.5), perCourse: [course: .all])
        #expect(ChangeDigest.diff(old: old, new: small, thresholds: loose).courseScoreChanges.first?.delta ?? 0 < 0)
        let strict = DigestThresholds(global: .all, perCourse: [course: .points(2.0)])
        #expect(ChangeDigest.diff(old: old, new: small, thresholds: strict).courseScoreChanges.isEmpty)
        #expect(strict.threshold(for: "99999") == .all, "courses without an override use the global setting")
    }

    @Test func thresholdsRoundTripThroughJSON() throws {
        let value = DigestThresholds(global: .all, perCourse: [course: .points(1.5)])
        #expect(try JSONDecoder().decode(DigestThresholds.self, from: JSONEncoder().encode(value)) == value)
    }
}
