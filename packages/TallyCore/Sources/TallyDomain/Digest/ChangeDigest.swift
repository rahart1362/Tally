import Foundation

/// WP-A07: a pure, Canvas-ID-keyed diff between two snapshots of the same account
/// (architecture.md §3.4). Feeds the Dashboard's "What changed" card and, via the sync
/// lane's post-commit pipeline (out of this file's scope), an optional digest push.
///
/// `diff(old:new:)` never performs I/O and never reads persisted state directly — every
/// fact it needs comes from the two snapshots — so it is trivially unit-testable and
/// reusable from a background refresh. `old == nil` (the very first snapshot after
/// sign-in) always yields `.empty`: without it, a fresh login would report every
/// assignment and announcement as "new", flooding the student on their first look
/// (architecture §3.4: "prevents a notification flood after login").
public struct ChangeDigest: Codable, Sendable, Equatable {
    /// A submission's displayed score newly appeared or changed since `old`. Gated on
    /// the *new* submission's `postedAt` being non-nil (architecture §3.3: "unposted
    /// work is excluded from displayed grades"), so a teacher's in-progress regrade
    /// never surfaces here before it is posted to the student.
    public struct GradeChange: Codable, Sendable, Equatable {
        public let courseID: CanvasID<Course>
        public let assignmentID: CanvasID<Assignment>
        public let submissionID: CanvasID<Submission>?
        /// nil when the assignment had no score at all in `old` (a first grade,
        /// not a change to one).
        public let previousScore: Double?
        public let newScore: Double
        public let pointsPossible: Double?

        public init(courseID: CanvasID<Course>, assignmentID: CanvasID<Assignment>, submissionID: CanvasID<Submission>?,
                    previousScore: Double?, newScore: Double, pointsPossible: Double?) {
            self.courseID = courseID; self.assignmentID = assignmentID; self.submissionID = submissionID
            self.previousScore = previousScore; self.newScore = newScore; self.pointsPossible = pointsPossible
        }
    }

    /// An assignment ID present in `new` but not anywhere in `old`.
    public struct NewAssignment: Codable, Sendable, Equatable {
        public let courseID: CanvasID<Course>
        public let assignmentID: CanvasID<Assignment>
        public let dueAt: Date?

        public init(courseID: CanvasID<Course>, assignmentID: CanvasID<Assignment>, dueAt: Date?) {
            self.courseID = courseID; self.assignmentID = assignmentID; self.dueAt = dueAt
        }
    }

    /// An assignment present in both snapshots whose `dueAt` differs (either side may
    /// be nil: a date being added or removed is also a "due-date change").
    public struct DueDateChange: Codable, Sendable, Equatable {
        public let courseID: CanvasID<Course>
        public let assignmentID: CanvasID<Assignment>
        public let previousDueAt: Date?
        public let newDueAt: Date?

        public init(courseID: CanvasID<Course>, assignmentID: CanvasID<Assignment>, previousDueAt: Date?, newDueAt: Date?) {
            self.courseID = courseID; self.assignmentID = assignmentID
            self.previousDueAt = previousDueAt; self.newDueAt = newDueAt
        }
    }

    /// An announcement ID present in `new` but not in `old`.
    public struct NewAnnouncement: Codable, Sendable, Equatable {
        public let courseID: CanvasID<Course>
        public let announcementID: CanvasID<Announcement>
        public let postedAt: Date?

        public init(courseID: CanvasID<Course>, announcementID: CanvasID<Announcement>, postedAt: Date?) {
            self.courseID = courseID; self.announcementID = announcementID; self.postedAt = postedAt
        }
    }

    /// A course present in both snapshots whose overall current score moved by at
    /// least the course's `DigestThresholds` value (default `TallyConfig.courseScoreChangeThreshold` points;
    /// "All" reports any change), in either direction.
    /// Never reported for a course with hidden totals in *either* snapshot, matching
    /// the "Tally never shows a band/score it wasn't given" rule applied elsewhere
    /// (`GlanceProjectionBuilder`, `AlertEngine.belowGoalAlert`).
    public struct CourseScoreChange: Codable, Sendable, Equatable {
        public let courseID: CanvasID<Course>
        public let previousScore: Double
        public let newScore: Double
        public var delta: Double { newScore - previousScore }

        public init(courseID: CanvasID<Course>, previousScore: Double, newScore: Double) {
            self.courseID = courseID; self.previousScore = previousScore; self.newScore = newScore
        }
    }

    public let gradeChanges: [GradeChange]
    public let newAssignments: [NewAssignment]
    public let dueDateChanges: [DueDateChange]
    public let newAnnouncements: [NewAnnouncement]
    public let courseScoreChanges: [CourseScoreChange]

    public static let empty = ChangeDigest(gradeChanges: [], newAssignments: [], dueDateChanges: [],
                                           newAnnouncements: [], courseScoreChanges: [])

    public init(gradeChanges: [GradeChange], newAssignments: [NewAssignment], dueDateChanges: [DueDateChange],
                newAnnouncements: [NewAnnouncement], courseScoreChanges: [CourseScoreChange]) {
        self.gradeChanges = gradeChanges
        self.newAssignments = newAssignments
        self.dueDateChanges = dueDateChanges
        self.newAnnouncements = newAnnouncements
        self.courseScoreChanges = courseScoreChanges
    }

    public var isEmpty: Bool {
        gradeChanges.isEmpty && newAssignments.isEmpty && dueDateChanges.isEmpty
            && newAnnouncements.isEmpty && courseScoreChanges.isEmpty
    }

    /// Total entries across every category — the Dashboard's "N changes since <time>" count.
    public var count: Int {
        gradeChanges.count + newAssignments.count + dueDateChanges.count + newAnnouncements.count + courseScoreChanges.count
    }

    /// Pure, Canvas-ID-keyed diff (architecture.md §3.4: "Detects: new or changed
    /// scores, newly graded work, new assignments, due-date changes, new
    /// announcements, and course-score deltas at or above a threshold"). Deterministic
    /// ordering (sorted by Canvas ID within each category) so two diffs of the same
    /// pair of snapshots are byte-for-byte equal.
    public static func diff(
        old: CanvasSnapshot?, new: CanvasSnapshot,
        thresholds: DigestThresholds = .default
    ) -> ChangeDigest {
        guard let old else { return .empty }

        let oldAssignments = assignmentsByID(old)
        let newAssignmentsMap = assignmentsByID(new)

        var gradeChanges: [GradeChange] = []
        var newAssignmentEntries: [NewAssignment] = []
        var dueDateChanges: [DueDateChange] = []

        for (assignmentID, (courseID, assignment)) in newAssignmentsMap.sorted(by: { $0.key < $1.key }) {
            guard let (_, previousAssignment) = oldAssignments[assignmentID] else {
                newAssignmentEntries.append(NewAssignment(courseID: courseID, assignmentID: assignmentID, dueAt: assignment.dueAt))
                continue
            }
            if previousAssignment.dueAt != assignment.dueAt {
                dueDateChanges.append(DueDateChange(courseID: courseID, assignmentID: assignmentID,
                                                    previousDueAt: previousAssignment.dueAt, newDueAt: assignment.dueAt))
            }
            if let change = gradeChange(courseID: courseID, assignmentID: assignmentID, pointsPossible: assignment.pointsPossible,
                                       previous: previousAssignment.submission, current: assignment.submission) {
                gradeChanges.append(change)
            }
        }

        let oldAnnouncementIDs = Set(old.announcements.map(\.id))
        let newAnnouncementEntries = new.announcements
            .filter { !oldAnnouncementIDs.contains($0.id) }
            .sorted { $0.id < $1.id }
            .map { NewAnnouncement(courseID: $0.courseID, announcementID: $0.id, postedAt: $0.postedAt) }

        // CS-07: the older snapshot can repeat a course ID (for one written before the gateway
        // de-duplicated). `Dictionary(uniqueKeysWithValues:)` trapped on that, at every commit.
        // The first occurrence wins, as in `PriorityScore.WeightContext`.
        let oldCoursesByID = Dictionary(old.courses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var courseScoreChanges: [CourseScoreChange] = []
        for course in new.courses.sorted(by: { $0.id < $1.id }) {
            guard let previousCourse = oldCoursesByID[course.id],
                  course.gradeVisibility == .visible, previousCourse.gradeVisibility == .visible,
                  let previousScore = previousCourse.scores?.currentScore,
                  let newScore = course.scores?.currentScore else { continue }
            guard thresholds.threshold(for: course.id).isCleared(by: newScore - previousScore) else { continue }
            courseScoreChanges.append(CourseScoreChange(courseID: course.id, previousScore: previousScore, newScore: newScore))
        }

        return ChangeDigest(gradeChanges: gradeChanges, newAssignments: newAssignmentEntries, dueDateChanges: dueDateChanges,
                            newAnnouncements: newAnnouncementEntries, courseScoreChanges: courseScoreChanges)
    }

    /// nil unless the *new* submission has a posted score that is either new (no prior
    /// score at all) or different from what was posted before (a re-grade).
    private static func gradeChange(
        courseID: CanvasID<Course>, assignmentID: CanvasID<Assignment>, pointsPossible: Double?,
        previous: Submission?, current: Submission?
    ) -> GradeChange? {
        guard let current, let newScore = current.score, current.postedAt != nil else { return nil }
        guard previous?.postedAt != current.postedAt || previous?.score != newScore else { return nil }
        return GradeChange(courseID: courseID, assignmentID: assignmentID, submissionID: current.id,
                           previousScore: previous?.score, newScore: newScore, pointsPossible: pointsPossible)
    }

    /// Flattens every course's assignment groups into one lookup by assignment ID.
    /// Canvas assignment IDs are unique account-wide, so this never collides across courses.
    ///
    /// R-4 (resilience.md, crash-safety-2.md F-10): a repeat, from data that bypassed the gateway,
    /// keeps its **first** occurrence, in the order `LiveCanvasGateway`'s de-duplication uses:
    /// courses in `courses` order, then any other course the groups are keyed by, in ID order;
    /// groups in order, a repeated group skipped whole; assignments in order. It used to keep the
    /// last, in `Dictionary` order, which changes from one process to the next.
    private static func assignmentsByID(
        _ snapshot: CanvasSnapshot
    ) -> [CanvasID<Assignment>: (courseID: CanvasID<Course>, assignment: Assignment)] {
        var listed = Set<CanvasID<Course>>()
        let listedOrder = snapshot.courses.map(\.id).filter { listed.insert($0).inserted }
        let courseOrder = listedOrder + snapshot.groups.keys.filter { !listed.contains($0) }.sorted()
        var result: [CanvasID<Assignment>: (courseID: CanvasID<Course>, assignment: Assignment)] = [:]
        for courseID in courseOrder {
            var seenGroups = Set<CanvasID<AssignmentGroup>>()
            for group in snapshot.groups[courseID] ?? [] where seenGroups.insert(group.id).inserted {
                for assignment in group.assignments where result[assignment.id] == nil {
                    result[assignment.id] = (courseID, assignment)
                }
            }
        }
        return result
    }
}
