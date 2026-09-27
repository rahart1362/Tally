import Foundation

/// One request `ReminderPlanner` wants pending. A repeating request (digest,
/// week-ahead) still counts as exactly one entry here, matching how it counts
/// as one against iOS's pending-notification cap (insights-at-a-glance §3.8).
public struct PendingReminder: Sendable, Equatable {
    public let id: String
    public let kind: NotificationKind
    public let fireDate: Date
    public let interruptionLevel: InterruptionLevel
    /// The assignment/course/etc. this concerns, for the app layer to resolve
    /// display content from the current snapshot. Opaque Canvas ID or "-" for
    /// account-level reminders (digest, week ahead, sentinel).
    public let subjectID: String

    public init(id: String, kind: NotificationKind, fireDate: Date, interruptionLevel: InterruptionLevel, subjectID: String) {
        self.id = id
        self.kind = kind
        self.fireDate = fireDate
        self.interruptionLevel = interruptionLevel
        self.subjectID = subjectID
    }
}

/// `UNNotificationInterruptionLevel` (iOS 15+), without importing UserNotifications.
public enum InterruptionLevel: String, Sendable, Equatable, CaseIterable {
    case passive, active, timeSensitive
}

public enum NotificationKind: String, Sendable, Equatable, CaseIterable {
    case due, followup, exam, digest, weekAhead, gradePosted, belowGoal, sentinel
}

/// Builds the deterministic `tally.<accountKey>.<kind>.<canvasID>.<ruleID>.<offset>`
/// notification IDs (WP-D02), so the reconciler (ARC) can diff pending
/// requests against this planner's desired set idempotently.
public enum NotificationID {
    public static func make(accountKey: AccountKey, kind: NotificationKind, canvasID: String, ruleID: String, offset: String) -> String {
        "tally.\(accountKey.rawValue).\(kind.rawValue).\(canvasID).\(ruleID).\(offset)"
    }
}

/// A local reminder's quiet-hours window: `start...end` may wrap midnight
/// (the default 23:00-07:00 does).
public struct QuietHours: Sendable, Equatable {
    public let startHour: Int
    public let startMinute: Int
    public let endHour: Int
    public let endMinute: Int

    public init(
        startHour: Int = InsightsConfig.defaultQuietHoursStart.hour,
        startMinute: Int = InsightsConfig.defaultQuietHoursStart.minute,
        endHour: Int = InsightsConfig.defaultQuietHoursEnd.hour,
        endMinute: Int = InsightsConfig.defaultQuietHoursEnd.minute
    ) {
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }
}

public enum ReminderPreset: String, Sendable, Equatable, CaseIterable {
    case light, balanced, intense
}

/// Student-configurable reminder settings (`user-state`, ENC D-E4). Defaults
/// are exactly PMO R14 "Balanced": both due-item offsets on, the missing
/// follow-up on, exam reminders on, digest and week-ahead on, default quiet
/// hours, Time Sensitive allowed.
public struct ReminderSettings: Sendable, Equatable {
    public var preset: ReminderPreset
    public var quietHours: QuietHours
    public var digestEnabled: Bool
    public var weekAheadEnabled: Bool
    public var missingFollowupEnabled: Bool
    public var examRemindersEnabled: Bool
    /// The student can turn Time Sensitive off entirely (§3.5); when false,
    /// every reminder that would otherwise be `.timeSensitive` is `.active`.
    public var timeSensitiveAllowed: Bool
    public var hideCourseNames: Bool

    public init(
        preset: ReminderPreset = .balanced,
        quietHours: QuietHours = QuietHours(),
        digestEnabled: Bool = true,
        weekAheadEnabled: Bool = true,
        missingFollowupEnabled: Bool = true,
        examRemindersEnabled: Bool = true,
        timeSensitiveAllowed: Bool = true,
        hideCourseNames: Bool = false
    ) {
        self.preset = preset
        self.quietHours = quietHours
        self.digestEnabled = digestEnabled
        self.weekAheadEnabled = weekAheadEnabled
        self.missingFollowupEnabled = missingFollowupEnabled
        self.examRemindersEnabled = examRemindersEnabled
        self.timeSensitiveAllowed = timeSensitiveAllowed
        self.hideCourseNames = hideCourseNames
    }
}

/// One item `ReminderPlanner` may schedule reminders for. Wraps `Assignment`
/// (the verified domain model) rather than duplicating its fields; adds only
/// what the planner needs beyond it.
public struct ReminderCandidate: Sendable, Equatable {
    public let assignment: Assignment
    public let isExam: Bool
    /// The §5 priority score (0...100); gates whether the final due-item
    /// reminder is Time Sensitive (§3.5: "the final reminder of a High/
    /// Critical item").
    public let priority: Double
    public let markedDone: Bool

    public init(assignment: Assignment, isExam: Bool = false, priority: Double = 0, markedDone: Bool = false) {
        self.assignment = assignment
        self.isExam = isExam
        self.priority = priority
        self.markedDone = markedDone
    }
}

/// §2.3 snooze options (due-item reminders only; "1 day before it's due" needs a due date).
public enum SnoozeOption: Sendable, Equatable {
    case oneHour
    case tonight
    case tomorrowMorning
    case dayBeforeDue
}
