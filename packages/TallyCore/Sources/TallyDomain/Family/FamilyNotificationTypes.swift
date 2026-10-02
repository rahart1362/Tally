import Foundation

/// One request the parent notification planner wants pending (family-linking.md §6.5, FAM-08).
/// Mirrors `TallyDomain/Reminders/PendingReminder`'s shape ("beside the existing reminder
/// planner's design", FAM-08's brief) but is keyed per **subject** (observee), never per
/// account alone: a parent account can hold several subjects at once (R8a), and each
/// subject's reminders form their own Notification Center thread.
public struct PendingFamilyReminder: Sendable, Equatable {
    public let id: String
    public let kind: FamilyNotificationKind
    public let subjectID: SubjectKey
    public let fireDate: Date
    public let interruptionLevel: InterruptionLevel

    public init(id: String, kind: FamilyNotificationKind, subjectID: SubjectKey, fireDate: Date,
                interruptionLevel: InterruptionLevel) {
        self.id = id
        self.kind = kind
        self.subjectID = subjectID
        self.fireDate = fireDate
        self.interruptionLevel = interruptionLevel
    }

    /// `threadIdentifier = subjectKey` (family-linking.md §6.5): every notification about one
    /// student groups into one Notification Center thread, however many kinds fire for them.
    public var threadIdentifier: String { subjectID.rawValue }
}

/// The parent-facing notification kinds FAM-08 plans (family-linking.md §6.5's table). The
/// account-level freshness sentinel is not repeated here: it carries no student data at all, so
/// it schedules unchanged through the existing `ReminderPlanner`/`NotificationMessage.sentinel`
/// machinery — nothing to re-prove about it per subject.
public enum FamilyNotificationKind: String, Sendable, Equatable, CaseIterable {
    case weekAhead, missingStillOpen, dueReminder, gradePosted, belowGoal
}

/// `tally.<accountKey>.<subjectKey>.<kind>.<canvasID>.<ruleID>.<offset>` (family-linking.md
/// §6.5's ID scheme): the student scheme (`NotificationID`, `TallyDomain/Reminders`) with one
/// extra `subjectKey` segment, so a parent's per-subject reminders can never collide with each
/// other, or with that same device's own student-side reminders when an account has both
/// capabilities (§4.3 "both → parent mode with a Me entry").
public enum FamilyNotificationID {
    public static func make(accountKey: AccountKey, subjectKey: SubjectKey, kind: FamilyNotificationKind,
                            canvasID: String, ruleID: String, offset: String) -> String {
        "tally.\(accountKey.rawValue).\(subjectKey.rawValue).\(kind.rawValue).\(canvasID).\(ruleID).\(offset)"
    }
}

/// Per-subject notification toggles (family-linking.md §6.5, owner decision F7(a) "Week-ahead +
/// missing-still-open on, others off, names shown with a Hide student names toggle"). Each
/// linked student gets their own settings (§7.3 "Notifications for Maya").
public struct FamilySubjectNotificationSettings: Sendable, Equatable {
    public var weekAheadEnabled: Bool
    public var missingStillOpenEnabled: Bool
    /// The 24h/1h due reminders: off by default ("the student's own reminders do this", §6.5).
    public var dueRemindersEnabled: Bool
    public var gradePostedEnabled: Bool
    public var belowGoalEnabled: Bool
    /// "Hide student names" (§6.5, default off): replaces every name with "Your student".
    public var hideStudentNames: Bool

    public init(weekAheadEnabled: Bool = true, missingStillOpenEnabled: Bool = true, dueRemindersEnabled: Bool = false,
                gradePostedEnabled: Bool = false, belowGoalEnabled: Bool = false, hideStudentNames: Bool = false) {
        self.weekAheadEnabled = weekAheadEnabled
        self.missingStillOpenEnabled = missingStillOpenEnabled
        self.dueRemindersEnabled = dueRemindersEnabled
        self.gradePostedEnabled = gradePostedEnabled
        self.belowGoalEnabled = belowGoalEnabled
        self.hideStudentNames = hideStudentNames
    }
}
