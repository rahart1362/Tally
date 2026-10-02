import Foundation
import TallyDomain

/// One linked student's input to a reminders pass (FAM-08 wiring, M3-E2): the observer subject, the
/// name Canvas reported (in memory only, family-linking.md §6.3), the student's snapshot and the
/// parent's notification settings for them (§7.3 "Notifications for Maya").
public nonisolated struct ObserverSubjectSnapshot: Sendable {
    public let subject: Subject
    public let name: String
    public let snapshot: CanvasSnapshot
    public let settings: FamilySubjectNotificationSettings

    public init(subject: Subject, name: String, snapshot: CanvasSnapshot,
                settings: FamilySubjectNotificationSettings = FamilySubjectNotificationSettings()) {
        self.subject = subject
        self.name = name
        self.snapshot = snapshot
        self.settings = settings
    }
}

/// Where a reminders pass finds an account's observer subjects. A signed-in account has none yet:
/// the observer snapshot composition (FAM-04) and per-subject sealed storage (FAM-05) are not built
/// (M3-E1 report §1), so `ReminderPipeline` defaults to `NoObserverSubjects` and plans the
/// account's own reminders exactly as before.
public nonisolated protocol ObserverSubjectSource: Sendable {
    func observerSubjects(of account: AccountKey) async -> [ObserverSubjectSnapshot]
}

/// No observer subjects (every account today).
public nonisolated struct NoObserverSubjects: ObserverSubjectSource {
    public init() {}
    public func observerSubjects(of account: AccountKey) async -> [ObserverSubjectSnapshot] { [] }
}

/// FAM-08's planner (M3-E1, `FamilyNotificationPlanner`) wired into the reminders pass: the parent
/// reminders of every observer subject, each paired with the `FamilyNotificationMessage` its content
/// builder makes. A message carries no score, percentage or letter grade by construction (R10a,
/// proved in TallyCore), and its words come only from TallyStrings' `FamilyNotificationText`, so no
/// grade can reach a parent's notification. Pure and off the main actor.
///
/// Each reminder keeps E1's per-subject identifier (`tally.<account>.<subject>.<kind>.…`), so the
/// pass's reconciler diffs parent and student reminders together without a collision.
nonisolated enum FamilyReminderPlan {
    struct Planned: Sendable {
        let reminder: PendingReminder
        let message: FamilyNotificationMessage
    }

    /// - Parameter cap: the pending-notification slots left after the account's own reminders.
    static func plan(accountKey: AccountKey, subjects: [ObserverSubjectSnapshot], now: Date, format: ReminderTimeFormat,
                     cap: Int) -> [Planned] {
        guard cap > 0 else { return [] }
        // A student listed twice is planned once (the first), as the planner itself does.
        var seen: Set<SubjectKey> = []
        let subjects = subjects.filter { seen.insert($0.subject.id).inserted }
        let prepared = subjects.map { Prepared(input: $0, items: ReminderSubjects(snapshot: $0.snapshot, now: now)) }
        let planned = FamilyNotificationPlanner.plan(
            accountKey: accountKey,
            subjects: prepared.map {
                FamilySubjectPlanInput(subjectID: $0.input.subject.id, studentName: StudentNameText.firstName(of: $0.input.name),
                                       candidates: $0.items.candidates, settings: $0.input.settings)
            },
            now: now, timeZone: format.timeZone, cap: cap)
        let bySubject = Dictionary(prepared.map { ($0.input.subject.id, $0) }, uniquingKeysWith: { first, _ in first })
        return planned.compactMap { reminder in
            guard let subject = bySubject[reminder.subjectID],
                  let message = message(for: reminder, subject: subject, accountKey: accountKey, format: format) else { return nil }
            return Planned(reminder: PendingReminder(id: reminder.id, kind: kind(of: reminder.kind), fireDate: reminder.fireDate,
                                                     interruptionLevel: reminder.interruptionLevel,
                                                     subjectID: reminder.subjectID.rawValue),
                           message: message)
        }
    }

    private struct Prepared: Sendable {
        let input: ObserverSubjectSnapshot
        let items: ReminderSubjects
    }

    /// What `reminder` says, or `nil` when it has nothing honest to say (its item is gone, or a week
    /// ahead with nothing due), so it is not scheduled.
    private static func message(for reminder: PendingFamilyReminder, subject: Prepared, accountKey: AccountKey,
                                format: ReminderTimeFormat) -> FamilyNotificationMessage? {
        let name = StudentNameText.firstName(of: subject.input.name)
        let hide = subject.input.settings.hideStudentNames
        switch reminder.kind {
        case .weekAhead:
            let end = reminder.fireDate.addingTimeInterval(RemindersConfig.weekAheadWindow.timeInterval)
            let due = subject.items.openItems.filter { $0.dueAt > reminder.fireDate && $0.dueAt <= end }
            guard !due.isEmpty else { return nil }
            return FamilyNotificationContentBuilder.weekAhead(studentName: name, hideStudentNames: hide, dueCount: due.count,
                                                              busiestDay: format.busiestDay(of: due.map(\.dueAt)))
        case .missingStillOpen:
            guard let item = item(of: reminder, in: subject, accountKey: accountKey) else { return nil }
            return FamilyNotificationContentBuilder.missingStillOpen(studentName: name, hideStudentNames: hide,
                                                                     assignmentTitle: item.assignment.name,
                                                                     stillAcceptedUntil: item.assignment.lockAt)
        case .dueReminder:
            guard let item = item(of: reminder, in: subject, accountKey: accountKey) else { return nil }
            // The planner marks the last Balanced offset Time Sensitive; that one says "if your
            // student hasn't submitted yet" (§6.5, as the student's own final reminder does).
            return FamilyNotificationContentBuilder.dueReminder(studentName: name, hideStudentNames: hide,
                                                                assignmentTitle: item.assignment.name, dueAt: item.dueAt,
                                                                isFinalReminder: reminder.interruptionLevel == .timeSensitive)
        case .gradePosted:
            guard let code = courseCode(of: reminder, in: subject, accountKey: accountKey) else { return nil }
            return FamilyNotificationContentBuilder.gradePosted(studentName: name, hideStudentNames: hide, courseCode: code)
        case .belowGoal:
            guard let code = courseCode(of: reminder, in: subject, accountKey: accountKey) else { return nil }
            return FamilyNotificationContentBuilder.belowGoal(studentName: name, hideStudentNames: hide, courseCode: code)
        }
    }

    /// The Canvas ID in E1's identifier (`tally.<account>.<subject>.<kind>.<canvasID>.<rule>.<offset>`),
    /// read after the prefix this reminder's own account, subject and kind make (a subject key may
    /// itself contain dots; a Canvas ID does not).
    static func canvasID(of reminder: PendingFamilyReminder, accountKey: AccountKey) -> String? {
        let prefix = "tally.\(accountKey.rawValue).\(reminder.subjectID.rawValue).\(reminder.kind.rawValue)."
        guard reminder.id.hasPrefix(prefix) else { return nil }
        return reminder.id.dropFirst(prefix.count).split(separator: ".", omittingEmptySubsequences: false).first.map(String.init)
    }

    private static func item(of reminder: PendingFamilyReminder, in subject: Prepared, accountKey: AccountKey) -> ReminderSubjects.Item? {
        guard let id = canvasID(of: reminder, accountKey: accountKey) else { return nil }
        return subject.items.openItems.first { $0.assignment.id.rawValue == id }
    }

    private static func courseCode(of reminder: PendingFamilyReminder, in subject: Prepared, accountKey: AccountKey) -> String? {
        guard let id = canvasID(of: reminder, accountKey: accountKey) else { return nil }
        return subject.input.snapshot.courses.first { $0.id.rawValue == id }?.courseCode
    }

    private static func kind(of kind: FamilyNotificationKind) -> NotificationKind {
        switch kind {
        case .weekAhead: .weekAhead
        case .missingStillOpen: .followup
        case .dueReminder: .due
        case .gradePosted: .gradePosted
        case .belowGoal: .belowGoal
        }
    }
}
