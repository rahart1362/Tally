import Foundation
import TallyDomain

/// One snapshot's reminder subjects (M3-C, E07): `ReminderPlanner`'s candidates, and the words each
/// planned reminder says. Pure and off the main actor; it keeps assignments, titles and course codes
/// only, never the snapshot.
///
/// The words come from TallyCore's `NotificationContent` builders, which take no score, percentage
/// or letter grade at all (PMO R10), and honour "Hide Course Names" (course names and codes become
/// "a course", assignment titles "An assignment"). A reminder with nothing honest to say (an evening
/// digest with nothing due, §3.3 #4) has no content, and the pipeline does not schedule it.
nonisolated struct ReminderSubjects: Sendable {
    /// An open assignment that has a due date, with what its reminders show.
    struct Item: Sendable {
        let assignment: Assignment
        let courseCode: String
        let dueAt: Date
    }

    /// What the planner plans over: every open item with a due date, with its §5.1 priority (which
    /// decides whether its final reminder is Time Sensitive, §3.5).
    let candidates: [ReminderCandidate]
    /// The same items, soonest first (the digests count them).
    let openItems: [Item]
    private let itemsByID: [String: Item]
    private let courseCodes: [String: String]

    /// `doneAssignments`: the student's "done" marks (M3-C O2): a marked item is excluded like a
    /// submitted one, so it neither reminds nor counts in the digests.
    init(snapshot: CanvasSnapshot, now: Date, doneAssignments: Set<CanvasID<Assignment>> = []) {
        // CS-07: a course or an assignment ID can repeat; the first occurrence wins, as in
        // `DashboardBuilder`.
        var candidates: [ReminderCandidate] = []
        var items: [Item] = []
        var seen = Set<CanvasID<Assignment>>()
        var seenCourses = Set<CanvasID<Course>>()
        for course in snapshot.courses where seenCourses.insert(course.id).inserted {
            let groups = snapshot.groups[course.id] ?? []
            let weights = PriorityScore.WeightContext(course: course, groups: groups,
                                                      gradingPeriods: snapshot.gradingPeriods[course.id] ?? [])
            for assignment in groups.flatMap(\.assignments) {
                guard let due = assignment.dueAt, seen.insert(assignment.id).inserted,
                      !PriorityScore.isExcluded(assignment: assignment, markedDone: doneAssignments.contains(assignment.id),
                                                now: now) else { continue }
                let priority = PriorityScore.score(hoursUntilDue: due.timeIntervalSince(now) / 3600,
                                                   courseWeight: weights.weight(of: assignment),
                                                   modifiers: Self.modifiers(assignment: assignment, course: course, now: now))
                candidates.append(ReminderCandidate(assignment: assignment, priority: priority))
                items.append(Item(assignment: assignment, courseCode: course.courseCode, dueAt: due))
            }
        }
        self.candidates = candidates
        openItems = items.sorted { $0.dueAt != $1.dueAt ? $0.dueAt < $1.dueAt : $0.assignment.id.rawValue < $1.assignment.id.rawValue }
        itemsByID = Dictionary(items.map { ($0.assignment.id.rawValue, $0) }, uniquingKeysWith: { first, _ in first })
        courseCodes = Dictionary(snapshot.courses.map { ($0.id.rawValue, $0.courseCode) }, uniquingKeysWith: { first, _ in first })
    }

    /// `DashboardBuilder`'s own §5.1 modifiers (private there): overdue-but-open, and the course's
    /// standing with no goal set (goals are not built yet).
    private static func modifiers(assignment: Assignment, course: Course, now: Date) -> PriorityScore.Modifiers {
        let overdueStillOpen: Bool = {
            guard let due = assignment.dueAt, due < now else { return false }
            return assignment.lockAt.map { $0 > now } ?? true
        }()
        let (belowGoal, nearBoundary) = PriorityScore.courseModifiers(currentScore: course.scores?.currentScore, goal: nil)
        return PriorityScore.Modifiers(overdueStillOpen: overdueStillOpen, courseBelowGoal: belowGoal, nearBoundary: nearBoundary)
    }

    // MARK: - Words

    /// What `reminder` says, or `nil` when it has nothing honest to say (its subject is gone, or a
    /// digest has nothing due) and must not be scheduled.
    func content(for reminder: PendingReminder, accountKey: AccountKey, hideCourseNames: Bool,
                 lastSuccess: Date?, format: ReminderTimeFormat) -> NotificationContent.Rendered? {
        switch reminder.kind {
        case .due:
            guard let item = itemsByID[reminder.subjectID] else { return nil }
            return NotificationContent.due(
                assignmentTitle: item.assignment.name, courseCode: item.courseCode,
                dueTimeText: format.dayTime(item.dueAt, relativeTo: reminder.fireDate),
                isFinalReminder: reminder.id == Self.finalDueReminderID(accountKey: accountKey, subjectID: reminder.subjectID),
                hideCourseNames: hideCourseNames)
        case .followup:
            guard let item = itemsByID[reminder.subjectID] else { return nil }
            guard let lockAt = item.assignment.lockAt else {
                // No closing date in Canvas: say exactly that, never "still accepted until …".
                let titled = NotificationContent.missingFollowup(assignmentTitle: item.assignment.name, courseCode: item.courseCode,
                                                                 stillAcceptedUntilText: "", hideCourseNames: hideCourseNames)
                return NotificationContent.Rendered(title: titled.title, body: RemindersCopy.pastDueNoClosingDate)
            }
            return NotificationContent.missingFollowup(
                assignmentTitle: item.assignment.name, courseCode: item.courseCode,
                stillAcceptedUntilText: format.dayTime(lockAt, relativeTo: reminder.fireDate), hideCourseNames: hideCourseNames)
        case .exam:
            guard let item = itemsByID[reminder.subjectID] else { return nil }
            return NotificationContent.examReminder(
                assignmentTitle: item.assignment.name, courseCode: item.courseCode,
                dueTimeText: format.dayTime(item.dueAt, relativeTo: reminder.fireDate), hideCourseNames: hideCourseNames)
        case .digest:
            let due = items(dueAfter: reminder.fireDate, within: RemindersConfig.digestWindow)
            guard let first = due.first else { return nil }
            return NotificationContent.eveningDigest(dueCount: due.count, firstItemTitle: first.assignment.name,
                                                     hideCourseNames: hideCourseNames)
        case .weekAhead:
            let due = items(dueAfter: reminder.fireDate, within: RemindersConfig.weekAheadWindow)
            guard !due.isEmpty else { return nil }
            return NotificationContent.weekAhead(dueCount: due.count, busiestDayText: format.busiestDay(of: due.map(\.dueAt)))
        case .sentinel:
            guard let lastSuccess else { return nil }
            return NotificationContent.sentinel(lastSuccessText: format.dayTime(lastSuccess, relativeTo: reminder.fireDate))
        case .gradePosted:
            guard let code = courseCodes[reminder.subjectID] else { return nil }
            return NotificationContent.gradePosted(courseCode: code, hideCourseNames: hideCourseNames)
        case .belowGoal:
            guard let code = courseCodes[reminder.subjectID] else { return nil }
            return NotificationContent.belowGoal(courseCode: code, hideCourseNames: hideCourseNames)
        }
    }

    /// Open items due after `start` and no later than `start + window`, soonest first.
    private func items(dueAfter start: Date, within window: Duration) -> [Item] {
        let end = start.addingTimeInterval(window.timeInterval)
        return openItems.filter { $0.dueAt > start && $0.dueAt <= end }
    }

    /// The final (soonest) due-item reminder's ID (`ReminderPlanner`'s own deterministic ID for the
    /// last Balanced offset), which says "…, if you haven't submitted yet." (§3.6).
    static func finalDueReminderID(accountKey: AccountKey, subjectID: String) -> String? {
        guard let final = InsightsConfig.balancedDueOffsets.last else { return nil }
        return NotificationID.make(accountKey: accountKey, kind: .due, canvasID: subjectID, ruleID: "due",
                                   offset: "\(Int(final.timeInterval))")
    }
}

/// Copy the reminders feature adds to TallyCore's `NotificationContent`.
nonisolated enum RemindersCopy {
    /// The missing-work follow-up for an assignment Canvas gives no closing date: factual, and no
    /// promise that Canvas will still accept it.
    static let pastDueNoClosingDate = "Past due. Canvas lists no closing date."
}

/// Dates in reminder text ("today at 6:00 PM", "Fri at 11:59 PM"), in the student's time zone and
/// locale, relative to when the notification is seen (its fire date), not to when it was planned.
nonisolated struct ReminderTimeFormat: Sendable {
    let timeZone: TimeZone
    let locale: Locale

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        return calendar
    }

    func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
    }

    func weekday(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).weekday(.abbreviated))
    }

    /// "today at 6:00 PM", "tomorrow at …", "yesterday at …", "Fri at …" within
    /// `RemindersConfig.weekdayNamingDays` either way, else "Oct 9 at …".
    func dayTime(_ date: Date, relativeTo reference: Date) -> String {
        let calendar = calendar
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: reference),
                                           to: calendar.startOfDay(for: date)).day ?? Int.max
        let day: String
        switch days {
        case 0: day = "today"
        case 1: day = "tomorrow"
        case -1: day = "yesterday"
        case -RemindersConfig.weekdayNamingDays...RemindersConfig.weekdayNamingDays: day = weekday(date)
        default: day = date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).month(.abbreviated).day())
        }
        return "\(day) at \(time(date))"
    }

    /// The weekday with the most items due ("Thursday"), the earliest of a tie, when it has at least
    /// `RemindersConfig.busiestDayMinimum`; otherwise `nil`.
    func busiestDay(of dueDates: [Date]) -> String? {
        let calendar = calendar
        let byDay = Dictionary(grouping: dueDates) { calendar.startOfDay(for: $0) }
        guard let busiest = byDay.max(by: { $0.value.count != $1.value.count ? $0.value.count < $1.value.count : $0.key > $1.key }),
              busiest.value.count >= RemindersConfig.busiestDayMinimum else { return nil }
        return busiest.key.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).weekday(.wide))
    }
}
