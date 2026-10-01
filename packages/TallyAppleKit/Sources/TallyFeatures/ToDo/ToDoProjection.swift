import Foundation
import TallyDomain

/// A To-Do row's Canvas status, shown as a chip with an icon and a word (ux-ui.md §3.6
/// StatusChip; never colour alone).
public nonisolated enum WorkStatus: String, Equatable, Sendable {
    case missing, notSubmitted, submitted, graded, excused, late

    public var label: String {
        switch self {
        case .missing: "Missing"
        case .notSubmitted: "Not submitted"
        case .submitted: "Submitted"
        case .graded: "Graded"
        case .excused: "Excused"
        case .late: "Late"
        }
    }

    public var symbol: String {
        switch self {
        case .missing: "exclamationmark.circle"
        case .notSubmitted: "circle.dashed"
        case .submitted: "checkmark.circle"
        case .graded: "checkmark.seal"
        case .excused: "minus.circle"
        case .late: "clock.badge.exclamationmark"
        }
    }
}

/// One To-Do row (ux-ui.md §3.7.5, UX-WP-18), built off the main actor. The done state is not in
/// here: it is the student's local mark (`ScreenLocalState`), so marking an item shows at once.
public nonisolated struct ToDoItem: Identifiable, Equatable, Sendable {
    public var id: CanvasID<Assignment> { assignmentID }
    public let assignmentID: CanvasID<Assignment>
    public let courseID: CanvasID<Course>
    public let title: String
    public let courseCode: String
    public let paletteIndex: Int
    /// "Due Thu at 11:59 PM", "Was due Fri", or `nil` for undated work.
    public let dueText: String?
    /// `nil` for work with nothing to submit online (in class or on paper).
    public let status: WorkStatus?
    /// "Still accepted until Fri at 11:59 PM" / "Still accepted" / "Closed — talk to your instructor".
    public let lateNote: String?
    public let band: PriorityScore.Band
    /// The item still needs a Canvas submission: a local "done" mark then also says "Not submitted
    /// in Canvas" (ux-ui.md §3.7.5: "Done" semantics must be honest).
    public let needsCanvasSubmission: Bool
    public let canvasURL: URL?
    /// Title, course code, status words, due and priority, for VoiceOver (A11Y-06). The view adds
    /// the local done state.
    public let accessibilityLabel: String

    /// The priority flag's word, shown for high-priority work only ("High", ux-ui.md §3.7.5).
    public var priorityWord: String? { band == .high ? "High priority" : nil }

    /// "Done" is Tally's own mark (PMO R16), so the row says exactly that (ux-ui.md §3.7.5).
    public static let markedDoneText = "Marked done in Tally"
    /// Shown with a done mark while Canvas still expects a submission.
    public static let notSubmittedText = "Not submitted in Canvas"

    /// The row's VoiceOver label: the projector's words, then the honest done state.
    public func spokenLabel(isDone: Bool) -> String {
        guard isDone else { return accessibilityLabel }
        var parts = [accessibilityLabel, Self.markedDoneText]
        if needsCanvasSubmission { parts.append(Self.notSubmittedText) }
        return parts.joined(separator: ", ")
    }
}

public nonisolated struct ToDoSection: Identifiable, Equatable, Sendable {
    public nonisolated enum Kind: String, Equatable, Sendable, CaseIterable {
        case missing, thisWeek, later
    }

    public var id: Kind { kind }
    public let kind: Kind
    public let title: String
    /// The section's rows in each sort order the toolbar offers, sorted here, off the main actor.
    public let byDueDate: [ToDoItem]
    public let byPriority: [ToDoItem]
    public let byCourse: [ToDoItem]

    public func items(sortedBy order: ToDoSortOrder) -> [ToDoItem] {
        switch order {
        case .dueDate: byDueDate
        case .priority: byPriority
        case .course: byCourse
        }
    }
}

public nonisolated enum ToDoSortOrder: String, Equatable, Sendable, CaseIterable, Identifiable {
    case dueDate, priority, course
    public var id: Self { self }
    public var label: String {
        switch self {
        case .dueDate: "Due Date"
        case .priority: "Priority"
        case .course: "Course"
        }
    }
}

public nonisolated struct ToDoProjection: Equatable, Sendable {
    /// Missing and overdue first (ux-ui.md §3.7.5), then due this week, then later. Empty
    /// sections are left out.
    public let sections: [ToDoSection]
    /// Open missing work (for the tab badge, ux-ui.md §3.4: "Badge on To-Do only for missing work").
    public let missingCount: Int

    public static let empty = ToDoProjection(sections: [], missingCount: 0)
}

/// Builds the To-Do tab from one snapshot (pure; unit-tested). The work comes from the assignment
/// groups, which carry what the To-Do needs and the planner does not: submission state, lock dates
/// ("still accepted until") and grade weights (priority).
public nonisolated enum ToDoBuilder {
    /// The "this week" window: the same 7 days as the Dashboard's "Due soon".
    static let thisWeek: TimeInterval = 7 * 24 * 3600

    /// `gradeAvailability` (plan 08 §4.4 row 18): the projection's index; `nil` classifies the
    /// snapshot at `formatter.now` with no override.
    public static func projection(from snapshot: CanvasSnapshot, formatter: ScreenFormatter,
                                  gradeAvailability: GradeAvailabilityIndex? = nil) -> ToDoProjection {
        let now = formatter.now
        let availability = gradeAvailability ?? GradeAvailabilityIndex(snapshot: snapshot, overrides: [:], now: now)
        var missing: [Entry] = []
        var thisWeek: [Entry] = []
        var later: [Entry] = []
        var openMissing = 0
        var seen = Set<CanvasID<Assignment>>()

        for (courseOrder, course) in snapshot.courses.enumerated() {
            let groups = snapshot.groups[course.id] ?? []
            let weights = PriorityScore.WeightContext(course: course, groups: groups,
                                                      gradingPeriods: snapshot.gradingPeriods[course.id] ?? [])
            for assignment in groups.flatMap(\.assignments) where assignment.published {
                // CS-07: an assignment ID can repeat; the first occurrence wins.
                guard seen.insert(assignment.id).inserted else { continue }
                guard let placement = placement(of: assignment, now: now) else { continue }
                let weight = weights.weight(of: assignment)
                let score = priority(assignment: assignment, course: course, availability: availability[course.id],
                                     weight: weight, now: now)
                let item = row(assignment: assignment, course: course, paletteIndex: courseOrder, placement: placement,
                               band: PriorityScore.band(score), formatter: formatter)
                let entry = (item: item, due: assignment.dueAt, score: score, courseOrder: courseOrder)
                if case .stillAccepted = placement.late { openMissing += 1 }
                switch placement.section {
                case .missing: missing.append(entry)
                case .thisWeek: thisWeek.append(entry)
                case .later: later.append(entry)
                }
            }
        }

        let sections = [(ToDoSection.Kind.missing, "Missing & overdue", missing),
                        (.thisWeek, "Due this week", thisWeek),
                        (.later, "Due later", later)]
            .filter { !$0.2.isEmpty }
            .map { kind, title, entries in
                ToDoSection(kind: kind, title: title,
                            byDueDate: entries.sorted(by: dueFirst).map(\.item),
                            byPriority: entries.sorted(by: priorityFirst).map(\.item),
                            byCourse: entries.sorted(by: courseFirst).map(\.item))
            }
        return ToDoProjection(sections: sections, missingCount: openMissing)
    }

    // MARK: - Which section, if any

    nonisolated struct Placement: Equatable {
        nonisolated enum Late: Equatable {
            /// Missing, and Canvas still accepts it (until `lockAt`, or with no lock date).
            case stillAccepted(until: Date?)
            /// Missing, and the lock date has passed.
            case closed
        }

        let section: ToDoSection.Kind
        let status: WorkStatus?
        let late: Late?
        let needsCanvasSubmission: Bool
    }

    /// `nil` when the item is not to-do: excused, submitted, graded, or past due with nothing to
    /// submit (in-class work Canvas does not flag missing).
    static func placement(of assignment: Assignment, now: Date) -> Placement? {
        let submission = assignment.submission
        if let submission, submission.excused || submission.isSubmitted || submission.gradedAt != nil {
            return nil
        }
        let expectsOnlineSubmission = !(!assignment.submissionTypes.isEmpty
            && assignment.submissionTypes.allSatisfy { $0 == "none" || $0 == "on_paper" })
            && assignment.isGradeable
        if let alert = AlertEngine.missingAlert(assignment: assignment, now: now) {
            let late: Placement.Late
            if case .missingClosed = alert.kind {
                late = .closed
            } else {
                late = .stillAccepted(until: assignment.lockAt)
            }
            return Placement(section: .missing, status: .missing, late: late, needsCanvasSubmission: expectsOnlineSubmission)
        }
        guard let due = assignment.dueAt else {
            // Undated: to-do only when there is something to hand in.
            guard expectsOnlineSubmission else { return nil }
            return Placement(section: .later, status: .notSubmitted, late: nil, needsCanvasSubmission: true)
        }
        guard due >= now else { return nil }
        return Placement(section: due.timeIntervalSince(now) <= thisWeek ? .thisWeek : .later,
                         status: expectsOnlineSubmission ? .notSubmitted : nil, late: nil,
                         needsCanvasSubmission: expectsOnlineSubmission)
    }

    /// `PriorityScore` (insights-at-a-glance.md §5.1) with the course's modifiers; no goals are set
    /// in this build, so only the near-boundary modifier can apply, and only to a course whose
    /// grades are in Canvas and shown as percentages (plan 08 §4.4 row 18, the dashboard's rule:
    /// `DashboardBuilder.modifierScore`).
    static func priority(assignment: Assignment, course: Course, availability: GradeAvailability?, weight: Double,
                         now: Date) -> Double {
        let hours = assignment.dueAt.map { $0.timeIntervalSince(now) / 3600 }
        let overdueStillOpen: Bool = {
            guard let due = assignment.dueAt, due < now else { return false }
            return assignment.lockAt.map { $0 > now } ?? true
        }()
        let score = TallyDomain.DashboardBuilder.modifierScore(of: course, availability: availability)
        let (belowGoal, nearBoundary) = PriorityScore.courseModifiers(currentScore: score, goal: nil)
        return PriorityScore.score(hoursUntilDue: hours, courseWeight: weight,
                                   modifiers: .init(overdueStillOpen: overdueStillOpen, courseBelowGoal: belowGoal,
                                                    nearBoundary: nearBoundary))
    }

    static func row(assignment: Assignment, course: Course, paletteIndex: Int, placement: Placement,
                    band: PriorityScore.Band, formatter: ScreenFormatter) -> ToDoItem {
        let lateNote: String?
        let spokenLateNote: String?
        switch placement.late {
        case .stillAccepted(let lock?):
            lateNote = "Still accepted until \(formatter.untilText(lock))"
            spokenLateNote = "Still accepted until \(formatter.untilText(lock, spoken: true))"
        case .stillAccepted(nil):
            lateNote = "Still accepted"
            spokenLateNote = lateNote
        case .closed:
            lateNote = "Closed — talk to your instructor"
            spokenLateNote = lateNote
        case nil:
            lateNote = nil
            spokenLateNote = nil
        }
        let dueText = assignment.dueAt.map { formatter.dueText($0) }
        var spoken = [assignment.name, course.courseCode]
        if let status = placement.status { spoken.append(status.label) }
        if let due = assignment.dueAt { spoken.append(formatter.dueText(due, spoken: true)) }
        if let spokenLateNote { spoken.append(spokenLateNote) }
        if band == .high { spoken.append("High priority") }
        return ToDoItem(
            assignmentID: assignment.id, courseID: course.id, title: assignment.name, courseCode: course.courseCode,
            paletteIndex: paletteIndex, dueText: dueText, status: placement.status, lateNote: lateNote, band: band,
            needsCanvasSubmission: placement.needsCanvasSubmission, canvasURL: assignment.htmlURL,
            accessibilityLabel: spoken.joined(separator: ", "))
    }

    // MARK: - Sort orders (every one ends on the assignment ID, so each is deterministic)

    private typealias Entry = (item: ToDoItem, due: Date?, score: Double, courseOrder: Int)

    private static func dueFirst(_ a: Entry, _ b: Entry) -> Bool {
        switch (a.due, b.due) {
        case let (x?, y?) where x != y: return x < y
        case (.some, nil): return true
        case (nil, .some): return false
        default: return a.item.assignmentID < b.item.assignmentID
        }
    }

    private static func priorityFirst(_ a: Entry, _ b: Entry) -> Bool {
        if a.score != b.score { return a.score > b.score }
        return dueFirst(a, b)
    }

    private static func courseFirst(_ a: Entry, _ b: Entry) -> Bool {
        if a.courseOrder != b.courseOrder { return a.courseOrder < b.courseOrder }
        return dueFirst(a, b)
    }
}
