import Foundation
import TallyDomain
import TallyStrings

/// One snapshot's reminder subjects (M3-C, E07): `ReminderPlanner`'s candidates, and the words each
/// planned reminder says. Pure and off the main actor; it keeps assignments, titles and course codes
/// only, never the snapshot.
///
/// What each reminder says is a TallyCore `NotificationMessage` (plan 08 L10N-02): values with no
/// score, percentage or letter grade in any case (PMO R10), and no course name or assignment title
/// at all when "Hide Course Names" is on. `TallyStrings.NotificationText` phrases it in the
/// student's language ("a course", "An assignment" for the hidden names). A reminder with nothing
/// honest to say (an evening digest with nothing due, §3.3 #4) has no message, and the pipeline
/// does not schedule it.
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
    /// `gradeAvailabilityOverrides`: the student's "grades kept outside Canvas" answers (plan 08
    /// G-3, XG-04), so the priority's course modifiers classify each course as the Dashboard does.
    init(snapshot: CanvasSnapshot, now: Date, doneAssignments: Set<CanvasID<Assignment>> = [],
         gradeAvailabilityOverrides: [CanvasID<Course>: GradeAvailabilityOverride] = [:]) {
        // Plan 08 §4.4 rows 11 and 18 (the XG-02 report's F2): the same index the Dashboard's
        // priority uses, so a course whose grades are not in Canvas never adds a grade modifier.
        let gradeAvailability = GradeAvailabilityIndex(snapshot: snapshot, overrides: gradeAvailabilityOverrides, now: now)
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
                                                   modifiers: Self.modifiers(assignment: assignment, course: course,
                                                                             availability: gradeAvailability[course.id], now: now))
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
    /// standing with no goal set (goals are not built yet), from a score only a course whose
    /// grades are in Canvas as percentages has (`DashboardBuilder.modifierScore`).
    static func modifiers(assignment: Assignment, course: Course, availability: GradeAvailability?,
                          now: Date) -> PriorityScore.Modifiers {
        let overdueStillOpen: Bool = {
            guard let due = assignment.dueAt, due < now else { return false }
            return assignment.lockAt.map { $0 > now } ?? true
        }()
        let (belowGoal, nearBoundary) = PriorityScore.courseModifiers(
            currentScore: TallyDomain.DashboardBuilder.modifierScore(of: course, availability: availability), goal: nil)
        return PriorityScore.Modifiers(overdueStillOpen: overdueStillOpen, courseBelowGoal: belowGoal, nearBoundary: nearBoundary)
    }

    // MARK: - Words

    /// What `reminder` says, in the student's language, or `nil` when it has nothing honest to say
    /// (its subject is gone, or a digest has nothing due) and must not be scheduled.
    func content(for reminder: PendingReminder, accountKey: AccountKey, hideCourseNames: Bool,
                 lastSuccess: Date?, format: ReminderTimeFormat) -> NotificationContent.Rendered? {
        message(for: reminder, accountKey: accountKey, hideCourseNames: hideCourseNames, lastSuccess: lastSuccess,
                format: format)
            .map { format.render($0, seenAt: reminder.fireDate) }
    }

    /// What `reminder` says, as values (plan 08 L10N-02), or `nil` as for `content`.
    func message(for reminder: PendingReminder, accountKey: AccountKey, hideCourseNames: Bool,
                 lastSuccess: Date?, format: ReminderTimeFormat) -> NotificationMessage? {
        func subject(_ item: Item) -> NotificationMessage.Subject {
            .init(assignmentTitle: item.assignment.name, courseCode: item.courseCode, hideCourseNames: hideCourseNames)
        }
        switch reminder.kind {
        case .due:
            guard let item = itemsByID[reminder.subjectID] else { return nil }
            return .due(subject(item), dueAt: item.dueAt,
                        isFinalReminder: reminder.id == Self.finalDueReminderID(accountKey: accountKey, subjectID: reminder.subjectID))
        case .followup:
            guard let item = itemsByID[reminder.subjectID] else { return nil }
            // No closing date in Canvas (`nil`): the words say exactly that, never "still accepted until …".
            return .missingFollowup(subject(item), stillAcceptedUntil: item.assignment.lockAt)
        case .exam:
            guard let item = itemsByID[reminder.subjectID] else { return nil }
            return .examReminder(subject(item), dueAt: item.dueAt)
        case .digest:
            let due = items(dueAfter: reminder.fireDate, within: RemindersConfig.digestWindow)
            guard let first = due.first else { return nil }
            return .eveningDigest(dueCount: due.count, firstItem: .init(title: first.assignment.name, hideCourseNames: hideCourseNames))
        case .weekAhead:
            let due = items(dueAfter: reminder.fireDate, within: RemindersConfig.weekAheadWindow)
            guard !due.isEmpty else { return nil }
            return .weekAhead(dueCount: due.count, busiestDay: format.busiestDay(of: due.map(\.dueAt)))
        case .sentinel:
            guard let lastSuccess else { return nil }
            return .sentinel(lastSuccess: lastSuccess)
        case .gradePosted:
            guard let code = courseCodes[reminder.subjectID] else { return nil }
            return .gradePosted(.init(courseCode: code, hideCourseNames: hideCourseNames))
        case .belowGoal:
            guard let code = courseCodes[reminder.subjectID] else { return nil }
            return .belowGoal(.init(courseCode: code, hideCourseNames: hideCourseNames))
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

/// Reminder words and dates ("Due today at 6:00 PM.", "Fri at 11:59 PM") in the student's time
/// zone and locale, relative to when the notification is seen (its fire date), not to when it was
/// planned. The phrasing is `TallyStrings.NotificationText`'s (plan 08 L10N-02).
nonisolated struct ReminderTimeFormat: Sendable {
    let timeZone: TimeZone
    let locale: Locale

    /// `message` in words, its dates relative to `seenAt`.
    func render(_ message: NotificationMessage, seenAt: Date) -> NotificationContent.Rendered {
        NotificationText.render(message, seenAt: seenAt, timeZone: timeZone,
                                weekdayNamingDays: RemindersConfig.weekdayNamingDays, locale: locale)
    }

    func time(_ date: Date) -> String {
        NotificationText.time(date, timeZone: timeZone, locale: locale)
    }

    /// "today at 6:00 PM", "tomorrow at …", "yesterday at …", "Fri at …" within
    /// `RemindersConfig.weekdayNamingDays` either way, else "Oct 9 at …".
    func dayTime(_ date: Date, relativeTo reference: Date) -> String {
        NotificationText.dayTime(date, relativeTo: reference, timeZone: timeZone,
                                 weekdayNamingDays: RemindersConfig.weekdayNamingDays, locale: locale)
    }

    /// The start (in `timeZone`) of the day with the most items due, the earliest of a tie, when it
    /// has at least `RemindersConfig.busiestDayMinimum`; otherwise `nil`. The week-ahead summary
    /// names its weekday ("busiest Thursday").
    func busiestDay(of dueDates: [Date]) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        let byDay = Dictionary(grouping: dueDates) { calendar.startOfDay(for: $0) }
        guard let busiest = byDay.max(by: { $0.value.count != $1.value.count ? $0.value.count < $1.value.count : $0.key > $1.key }),
              busiest.value.count >= RemindersConfig.busiestDayMinimum else { return nil }
        return busiest.key
    }
}
