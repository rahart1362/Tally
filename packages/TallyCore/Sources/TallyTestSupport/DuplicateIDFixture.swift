import Foundation
import TallyDomain

/// CS-07 (docs/pmo/reviews/crash-safety-2.md): a small, hand-built, duplicate-free snapshot, and
/// the same snapshot with one kind of repeated identifier injected. Real Canvas data can repeat an
/// ID: a paginated list repeats an item when the data changes between page fetches, and a course
/// can come back once per enrollment.
///
/// Every duplicate is a *different* value with the same ID (a renamed course, a group with another
/// weight, an assignment with another title), so a test can tell which occurrence a consumer kept.
/// The rule under test is "the first occurrence wins", as `PriorityScore.WeightContext` already
/// does for groups.
///
/// The base snapshot is built so each duplicate reaches the code that used to trap:
/// - every duplicated assignment is open and due within the reminder horizon, so it reaches
///   `DashboardBuilder`'s "Next up" ranking and produces `ReminderPlanner` reminders;
/// - the duplicated course has planner items and assignments, so it reaches every by-course lookup.
public enum DuplicateIDFixture {
    /// Which identifier to repeat. `assignmentAcrossCourses` repeats one assignment ID under a
    /// second course, which Canvas never does for a real assignment but a what-if caller or a
    /// corrupted snapshot can.
    public enum Kind: String, CaseIterable, Sendable, CustomStringConvertible {
        case course
        case assignmentGroup
        case assignmentWithinGroup
        case assignmentAcrossGroups
        case assignmentAcrossCourses
        case gradingPeriod
        case plannerItem
        case event
        case announcement

        public var description: String { rawValue }
    }

    /// `TestClock`'s default instant (2026-09-28T13:00:00Z), which the fixtures also use.
    public static let now = Date(timeIntervalSince1970: 1_790_600_400)

    private static func days(_ count: Double) -> Date { now.addingTimeInterval(count * 86_400) }

    public static let biology: CanvasID<Course> = "7001"
    public static let history: CanvasID<Course> = "7002"
    /// The open, soon-due Biology homework every assignment duplicate repeats.
    public static let repeatedAssignment: CanvasID<Assignment> = "8111"

    // MARK: - Base snapshot (duplicate-free)

    static func course(_ id: CanvasID<Course>, name: String, code: String, score: Double,
                       weights: Bool, periods: Bool) -> Course {
        Course(id: id, name: name, courseCode: code, term: nil, teachers: [], timeZone: "America/New_York",
               appliesGroupWeights: weights, hasGradingPeriods: periods, currentGradingPeriodID: nil,
               gradeVisibility: .visible,
               scores: ComputedScores(currentScore: score, finalScore: score - 2, currentGrade: nil, finalGrade: nil),
               currentPeriodScores: nil, htmlURL: nil)
    }

    static func open(_ id: CanvasID<Assignment>, course: CanvasID<Course>, group: CanvasID<AssignmentGroup>,
                     name: String, dueInDays: Double?, points: Double) -> Assignment {
        Assignment(id: id, courseID: course, groupID: group, name: name, dueAt: dueInDays.map(days), lockAt: nil,
                   pointsPossible: points, gradingType: .points, omitFromFinalGrade: false, htmlURL: nil,
                   submission: Submission(score: nil, grade: nil, submittedAt: nil, gradedAt: nil, postedAt: nil,
                                          excused: false, missing: false, late: false, workflowState: "unsubmitted"),
                   submissionTypes: ["online_upload"])
    }

    static func graded(_ id: CanvasID<Assignment>, course: CanvasID<Course>, group: CanvasID<AssignmentGroup>,
                       name: String, dueInDays: Double, score: Double, points: Double) -> Assignment {
        let when = days(dueInDays)
        return Assignment(id: id, courseID: course, groupID: group, name: name, dueAt: when, lockAt: nil,
                          pointsPossible: points, gradingType: .points, omitFromFinalGrade: false, htmlURL: nil,
                          submission: Submission(score: score, grade: nil, submittedAt: when, gradedAt: when,
                                                 postedAt: when, excused: false, missing: false, late: false,
                                                 workflowState: "graded", id: CanvasID("s\(id.rawValue)")),
                          submissionTypes: ["online_upload"])
    }

    static func missing(_ id: CanvasID<Assignment>, course: CanvasID<Course>, group: CanvasID<AssignmentGroup>,
                        name: String, dueInDays: Double, points: Double) -> Assignment {
        Assignment(id: id, courseID: course, groupID: group, name: name, dueAt: days(dueInDays),
                   lockAt: days(dueInDays + 30), pointsPossible: points, gradingType: .points,
                   omitFromFinalGrade: false, htmlURL: nil,
                   submission: Submission(score: nil, grade: nil, submittedAt: nil, gradedAt: nil, postedAt: nil,
                                          excused: false, missing: true, late: false, workflowState: "unsubmitted"),
                   submissionTypes: ["online_upload"])
    }

    static func homework(assignments: [Assignment], weight: Double = 40) -> AssignmentGroup {
        AssignmentGroup(id: "9011", name: "Homework", position: 1, weight: weight,
                        rules: DropRules(dropLowest: 1, neverDrop: ["8112"]), assignments: assignments)
    }

    static let homeworkAssignments: [Assignment] = [
        open(repeatedAssignment, course: biology, group: "9011", name: "Lab report 3", dueInDays: 2, points: 10),
        graded("8112", course: biology, group: "9011", name: "Lab report 2", dueInDays: -3, score: 8, points: 10),
        open("8113", course: biology, group: "9011", name: "Lab report 4", dueInDays: 5, points: 20),
    ]

    static let exams = AssignmentGroup(
        id: "9012", name: "Exams", position: 2, weight: 60, rules: DropRules(),
        assignments: [
            open("8121", course: biology, group: "9012", name: "Midterm", dueInDays: 9, points: 100),
            missing("8122", course: biology, group: "9012", name: "Quiz 1", dueInDays: -10, points: 20),
        ])

    static let papers = AssignmentGroup(
        id: "9021", name: "Papers", position: 1, weight: nil, rules: DropRules(),
        assignments: [
            open("8211", course: history, group: "9021", name: "Essay 2", dueInDays: 1, points: 50),
            graded("8212", course: history, group: "9021", name: "Essay 1", dueInDays: -20, score: 45, points: 50),
        ])

    static let quizzes = AssignmentGroup(
        id: "9022", name: "Quizzes", position: 2, weight: nil, rules: DropRules(dropLowest: 1),
        assignments: [
            open("8221", course: history, group: "9022", name: "Quiz 3", dueInDays: 3, points: 10),
            open("8222", course: history, group: "9022", name: "Reading log", dueInDays: nil, points: 5),
        ])

    static func period(_ id: CanvasID<GradingPeriod>, title: String, from start: Double, to end: Double) -> GradingPeriod {
        GradingPeriod(id: id, title: title, startDate: days(start), endDate: days(end), closeDate: days(end),
                      weight: 50, isClosed: false)
    }

    static func plannerItem(_ id: String, course: CanvasID<Course>?, title: String, dueInDays: Double) -> PlannerItem {
        PlannerItem(id: id, courseID: course, title: title, plannableType: String(id.split(separator: ":")[0]),
                    dueAt: days(dueInDays), pointsPossible: 10, submitted: false, graded: false, missing: false,
                    late: false, excused: false, markedComplete: false, htmlURL: nil)
    }

    static func event(_ id: CanvasID<CalendarEvent>, course: CanvasID<Course>, title: String, startInDays: Double) -> CalendarEvent {
        CalendarEvent(id: id, courseID: course, title: title, startAt: days(startInDays),
                      endAt: days(startInDays).addingTimeInterval(3_600), allDay: false, locationName: nil, htmlURL: nil)
    }

    static func announcement(_ id: CanvasID<Announcement>, course: CanvasID<Course>, title: String) -> Announcement {
        Announcement(id: id, courseID: course, title: title, postedAt: days(-1), isRead: false, htmlURL: nil)
    }

    /// Two courses (one group-weighted, one with grading periods), eleven assignments in four
    /// groups, four planner items, two events and two announcements. Every ID is unique.
    public static func base(generation: UInt64 = 1, fetchedAt: Date = now) -> CanvasSnapshot {
        make(generation: generation, fetchedAt: fetchedAt,
             courses: [course(biology, name: "Biology", code: "BIO 101", score: 88.5, weights: true, periods: false),
                       course(history, name: "World History", code: "HIS 210", score: 91.2, weights: false, periods: true)],
             groups: [biology: [homework(assignments: homeworkAssignments), exams], history: [papers, quizzes]],
             gradingPeriods: [history: [period("6001", title: "Fall 1", from: -60, to: 30),
                                        period("6002", title: "Fall 2", from: 30, to: 120)]],
             planner: [plannerItem("assignment:8111", course: biology, title: "Lab report 3", dueInDays: 2),
                       plannerItem("assignment:8211", course: history, title: "Essay 2", dueInDays: 1),
                       plannerItem("planner_note:5001", course: nil, title: "Buy lab goggles", dueInDays: 4),
                       plannerItem("quiz:5002", course: history, title: "Quiz 3", dueInDays: 3)],
             events: [event("4001", course: biology, title: "Lab", startInDays: 1),
                      event("4002", course: history, title: "Museum trip", startInDays: 2)],
             announcements: [announcement("3001", course: biology, title: "Lab moved"),
                             announcement("3002", course: history, title: "Reading list")])
    }

    // MARK: - Snapshots with one repeated identifier

    /// `base()` with `kind`'s identifier repeated once. The repeat always comes *after* the
    /// original, so "first occurrence wins" keeps the original value.
    public static func snapshot(duplicating kind: Kind, generation: UInt64 = 1, fetchedAt: Date = now) -> CanvasSnapshot {
        snapshot(duplicating: [kind], generation: generation, fetchedAt: fetchedAt)
    }

    /// `base()` with every listed kind of identifier repeated once.
    public static func snapshot(duplicating kinds: [Kind], generation: UInt64 = 1, fetchedAt: Date = now) -> CanvasSnapshot {
        let original = base(generation: generation, fetchedAt: fetchedAt)
        var courses = original.courses
        var groups = original.groups
        var periods = original.gradingPeriods
        var planner = original.planner
        var events = original.events
        var announcements = original.announcements
        let repeated = open(repeatedAssignment, course: biology, group: "9011", name: "Lab report 3 (repeat)",
                            dueInDays: 2.5, points: 15)

        for kind in kinds {
            switch kind {
            case .course:
                courses.append(course(biology, name: "Biology (repeat)", code: "BIO REPEAT", score: 12, weights: false,
                                      periods: false))
            case .assignmentGroup:
                groups[biology, default: []].append(homework(assignments: [repeated], weight: 5))
            case .assignmentWithinGroup:
                groups[biology] = groups[biology].map { list in
                    list.map { $0.id == "9011" ? homework(assignments: $0.assignments + [repeated], weight: $0.weight ?? 0) : $0 }
                }
            case .assignmentAcrossGroups:
                let inExams = open(repeatedAssignment, course: biology, group: "9012", name: "Lab report 3 (in Exams)",
                                   dueInDays: 2.5, points: 15)
                groups[biology] = groups[biology].map { list in
                    list.map { $0.id == "9012" ? replacing($0, assignments: $0.assignments + [inExams]) : $0 }
                }
            case .assignmentAcrossCourses:
                let inHistory = open(repeatedAssignment, course: history, group: "9021", name: "Lab report 3 (in History)",
                                     dueInDays: 2.5, points: 15)
                groups[history] = groups[history].map { list in
                    list.map { $0.id == "9021" ? replacing($0, assignments: $0.assignments + [inHistory]) : $0 }
                }
            case .gradingPeriod:
                periods[history, default: []].append(period("6001", title: "Fall 1 (repeat)", from: -90, to: 0))
            case .plannerItem:
                planner.append(plannerItem("assignment:8111", course: biology, title: "Lab report 3 (repeat)", dueInDays: 2.5))
            case .event:
                events.append(event("4001", course: biology, title: "Lab (repeat)", startInDays: 1.5))
            case .announcement:
                announcements.append(announcement("3001", course: biology, title: "Lab moved (repeat)"))
            }
        }
        return make(generation: generation, fetchedAt: fetchedAt, courses: courses, groups: groups,
                    gradingPeriods: periods, planner: planner, events: events, announcements: announcements)
    }

    // MARK: - Helpers

    public static func replacing(_ group: AssignmentGroup, assignments: [Assignment]) -> AssignmentGroup {
        AssignmentGroup(id: group.id, name: group.name, position: group.position, weight: group.weight,
                        rules: group.rules, assignments: assignments)
    }

    /// Every assignment in the snapshot, in course order, then group order.
    public static func allAssignments(_ snapshot: CanvasSnapshot) -> [Assignment] {
        snapshot.courses.flatMap { (snapshot.groups[$0.id] ?? []).flatMap(\.assignments) }
    }

    static func make(generation: UInt64, fetchedAt: Date, courses: [Course],
                     groups: [CanvasID<Course>: [AssignmentGroup]], gradingPeriods: [CanvasID<Course>: [GradingPeriod]],
                     planner: [PlannerItem], events: [CalendarEvent], announcements: [Announcement]) -> CanvasSnapshot {
        CanvasSnapshot(
            generation: generation, accountKey: AccountKey("duplicate-id-fixture"), host: "canvas.fixtures.example",
            fetchedAt: fetchedAt,
            profile: UserProfile(id: "9900", name: "Fixture Student", shortName: "Fixture", timeZone: "America/New_York",
                                 calendarFeedURL: nil),
            courses: courses, groups: groups, gradingPeriods: gradingPeriods, planner: planner, events: events,
            announcements: announcements, courseColors: [biology: "#1770AB", history: "#8F3E97"],
            sections: Dictionary(SnapshotSection.allCases.map { ($0, SectionStatus(fetchedAt: fetchedAt, carriedForward: false)) },
                                 uniquingKeysWith: { first, _ in first }))
    }
}
