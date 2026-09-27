import Foundation

/// WP-D02 (pure part): the reminder-notification planner. Pure and
/// deterministic: given the candidate items, the student's settings, `now`
/// and a `RefreshRecord`, it returns exactly the set of local notifications
/// that should be pending — no I/O, no `UNUserNotificationCenter`. The app
/// layer diffs this against what is actually scheduled and reconciles
/// (insights-at-a-glance §3.8).
public enum ReminderPlanner {
    // MARK: - Plan

    /// Builds the full desired set of pending reminders:
    /// 1. Reserved account-level reminders (evening digest, week ahead,
    ///    the R17 stale-data sentinel) — each one pending request.
    /// 2. Per-item reminders (due-item offsets or exam reminders, plus the
    ///    missing-still-open follow-up) for every candcandidate that still
    ///    needs action (`PriorityScore.isExcluded` gates this the same way
    ///    "Next up" does: not submitted, graded, excused, marked done, or
    ///    overdue-and-locked).
    /// 3. Quiet-hour shifts (earlier only), a 14-day horizon, and then
    ///    **never exceeding `cap`**: item reminders are sorted soonest-first
    ///    and truncated to whatever budget remains after the reserved ones
    ///    (WP-D02: "keep the soonest").
    ///
    /// The result is idempotent: calling `plan` again with the same inputs
    /// (mainly `now`) produces the same IDs and dates, so reconciling against
    /// the currently-pending set is a plain diff.
    public static func plan(
        accountKey: AccountKey,
        candidates: [ReminderCandidate],
        settings: ReminderSettings,
        now: Date,
        timeZone: TimeZone,
        refresh: RefreshRecord,
        cap: Int = TallyConfig.pendingNotificationCap
    ) -> [PendingReminder] {
        var reserved: [PendingReminder] = []
        if settings.digestEnabled {
            reserved.append(digestReminder(accountKey: accountKey, now: now, timeZone: timeZone))
        }
        if settings.weekAheadEnabled {
            reserved.append(weekAheadReminder(accountKey: accountKey, now: now, timeZone: timeZone))
        }
        if let sentinel = sentinelReminder(accountKey: accountKey, refresh: refresh, quietHours: settings.quietHours, timeZone: timeZone) {
            reserved.append(sentinel)
        }

        let horizonEnd = now.addingTimeInterval(InsightsConfig.reminderHorizon.timeInterval)
        var itemReminders: [PendingReminder] = []
        for candidate in candidates {
            guard !PriorityScore.isExcluded(assignment: candidate.assignment, markedDone: candidate.markedDone, now: now) else { continue }
            itemReminders.append(contentsOf: reminders(for: candidate, settings: settings, accountKey: accountKey, timeZone: timeZone))
        }
        itemReminders = itemReminders
            .filter { $0.fireDate > now && $0.fireDate <= horizonEnd }
            .sorted(by: bySoonestThenID)

        let itemBudget = max(0, cap - reserved.count)
        let kept = Array(itemReminders.prefix(itemBudget))
        return (reserved + kept).sorted(by: bySoonestThenID)
    }

    private static func bySoonestThenID(_ a: PendingReminder, _ b: PendingReminder) -> Bool {
        a.fireDate != b.fireDate ? a.fireDate < b.fireDate : a.id < b.id
    }

    // MARK: - Per-item reminders

    private static func reminders(
        for candidate: ReminderCandidate, settings: ReminderSettings, accountKey: AccountKey, timeZone: TimeZone
    ) -> [PendingReminder] {
        let assignment = candidate.assignment
        guard let due = assignment.dueAt else { return [] }
        var out: [PendingReminder] = []

        if candidate.isExam {
            if settings.examRemindersEnabled {
                out.append(contentsOf: examReminders(assignmentID: assignment.id, dueAt: due, settings: settings,
                                                     accountKey: accountKey, timeZone: timeZone))
            }
        } else {
            out.append(contentsOf: dueReminders(assignmentID: assignment.id, dueAt: due, priority: candidate.priority,
                                                settings: settings, accountKey: accountKey, timeZone: timeZone))
        }

        if settings.missingFollowupEnabled {
            let fire = due.addingTimeInterval(InsightsConfig.missingFollowupOffset.timeInterval)
            let isOpenAtFollowup = assignment.lockAt == nil || assignment.lockAt! > fire
            if isOpenAtFollowup {
                let shifted = shiftOutOfQuietHours(fire, quietHours: settings.quietHours, timeZone: timeZone)
                out.append(PendingReminder(
                    id: NotificationID.make(accountKey: accountKey, kind: .followup, canvasID: assignment.id.rawValue,
                                            ruleID: "followup", offset: "\(Int(InsightsConfig.missingFollowupOffset.timeInterval))"),
                    kind: .followup, fireDate: shifted, interruptionLevel: .active, subjectID: assignment.id.rawValue))
            }
        }
        return out
    }

    /// R14 Balanced: T-24h and T-1h. The soonest-before-due offset (T-1h) is
    /// the "final hour" reminder and is Time Sensitive when the item is
    /// High/Critical priority and the student allows Time Sensitive (§3.5).
    private static func dueReminders(
        assignmentID: CanvasID<Assignment>, dueAt: Date, priority: Double, settings: ReminderSettings,
        accountKey: AccountKey, timeZone: TimeZone
    ) -> [PendingReminder] {
        let offsets = InsightsConfig.balancedDueOffsets
        return offsets.enumerated().map { index, offset in
            let isFinal = index == offsets.count - 1
            let fire = dueAt.addingTimeInterval(-offset.timeInterval)
            let shifted = shiftOutOfQuietHours(fire, quietHours: settings.quietHours, timeZone: timeZone)
            let wantsTimeSensitive = isFinal && priority >= InsightsConfig.dueSoonCriticalMinPriority
            return PendingReminder(
                id: NotificationID.make(accountKey: accountKey, kind: .due, canvasID: assignmentID.rawValue,
                                        ruleID: "due", offset: "\(Int(offset.timeInterval))"),
                kind: .due, fireDate: shifted,
                interruptionLevel: wantsTimeSensitive && settings.timeSensitiveAllowed ? .timeSensitive : .active,
                subjectID: assignmentID.rawValue)
        }
    }

    /// T-3d 18:00, T-1d 18:00, and the morning of at 07:30 (time-sensitive if allowed).
    private static func examReminders(
        assignmentID: CanvasID<Assignment>, dueAt: Date, settings: ReminderSettings, accountKey: AccountKey, timeZone: TimeZone
    ) -> [PendingReminder] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dueDay = calendar.startOfDay(for: dueAt)
        var out: [PendingReminder] = []

        for daysBefore in InsightsConfig.examReminderDaysBefore {
            guard let day = calendar.date(byAdding: .day, value: -daysBefore, to: dueDay),
                  let fire = calendar.date(bySettingHour: InsightsConfig.examReminderHour,
                                           minute: InsightsConfig.examReminderMinute, second: 0, of: day)
            else { continue }
            let shifted = shiftOutOfQuietHours(fire, quietHours: settings.quietHours, timeZone: timeZone)
            out.append(PendingReminder(
                id: NotificationID.make(accountKey: accountKey, kind: .exam, canvasID: assignmentID.rawValue,
                                        ruleID: "t\(daysBefore)d", offset: "1800"),
                kind: .exam, fireDate: shifted, interruptionLevel: .active, subjectID: assignmentID.rawValue))
        }
        if let morning = calendar.date(bySettingHour: InsightsConfig.examMorningOfHour,
                                       minute: InsightsConfig.examMorningOfMinute, second: 0, of: dueDay) {
            let shifted = shiftOutOfQuietHours(morning, quietHours: settings.quietHours, timeZone: timeZone)
            out.append(PendingReminder(
                id: NotificationID.make(accountKey: accountKey, kind: .exam, canvasID: assignmentID.rawValue,
                                        ruleID: "morning", offset: "0730"),
                kind: .exam, fireDate: shifted,
                interruptionLevel: settings.timeSensitiveAllowed ? .timeSensitive : .active,
                subjectID: assignmentID.rawValue))
        }
        return out
    }

    // MARK: - Reserved account-level reminders

    private static func digestReminder(accountKey: AccountKey, now: Date, timeZone: TimeZone) -> PendingReminder {
        let fire = nextOccurrence(hour: InsightsConfig.eveningDigestHour, minute: InsightsConfig.eveningDigestMinute, from: now, timeZone: timeZone)
        return PendingReminder(id: NotificationID.make(accountKey: accountKey, kind: .digest, canvasID: "-", ruleID: "evening", offset: "0"),
                              kind: .digest, fireDate: fire, interruptionLevel: .passive, subjectID: "-")
    }

    private static func weekAheadReminder(accountKey: AccountKey, now: Date, timeZone: TimeZone) -> PendingReminder {
        let fire = nextSunday(hour: InsightsConfig.weekAheadHour, minute: InsightsConfig.weekAheadMinute, from: now, timeZone: timeZone)
        return PendingReminder(id: NotificationID.make(accountKey: accountKey, kind: .weekAhead, canvasID: "-", ruleID: "sunday", offset: "0"),
                              kind: .weekAhead, fireDate: fire, interruptionLevel: .passive, subjectID: "-")
    }

    /// R17: reuses the already-verified `FreshnessRules.staleWarningDate`
    /// (`lastSuccess + TallyConfig.staleWarningAfter`, i.e. 24 h) rather than
    /// re-deriving the same math. nil when there is no successful refresh yet.
    private static func sentinelReminder(
        accountKey: AccountKey, refresh: RefreshRecord, quietHours: QuietHours, timeZone: TimeZone
    ) -> PendingReminder? {
        guard let fireDate = FreshnessRules.staleWarningDate(of: refresh) else { return nil }
        let shifted = shiftOutOfQuietHours(fireDate, quietHours: quietHours, timeZone: timeZone)
        return PendingReminder(id: NotificationID.make(accountKey: accountKey, kind: .sentinel, canvasID: "-", ruleID: "sentinel", offset: "0"),
                              kind: .sentinel, fireDate: shifted, interruptionLevel: .passive, subjectID: "-")
    }

    // MARK: - Quiet hours (§3.5: shift earlier only, never later)

    /// If `fireDate` falls inside `quietHours`, moves it to `quietHoursLeadIn`
    /// (15 min) before quiet hours begin **on the evening that quiet window
    /// started** — so a 2 AM fire time (inside an overnight window that began
    /// the previous evening) moves backward to the previous evening, never
    /// forward into the next night. A `fireDate` outside quiet hours is
    /// returned unchanged: this function only ever moves a date earlier.
    public static func shiftOutOfQuietHours(_ fireDate: Date, quietHours: QuietHours, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let comps = calendar.dateComponents([.hour, .minute], from: fireDate)
        guard let hour = comps.hour, let minute = comps.minute else { return fireDate }
        let minutesOfDay = hour * 60 + minute
        let startMinutes = quietHours.startHour * 60 + quietHours.startMinute
        let endMinutes = quietHours.endHour * 60 + quietHours.endMinute

        let inQuiet: Bool
        if startMinutes > endMinutes {
            inQuiet = minutesOfDay >= startMinutes || minutesOfDay < endMinutes
        } else {
            inQuiet = minutesOfDay >= startMinutes && minutesOfDay < endMinutes
        }
        guard inQuiet else { return fireDate }

        guard var windowStart = calendar.date(bySettingHour: quietHours.startHour, minute: quietHours.startMinute, second: 0, of: fireDate)
        else { return fireDate }
        if minutesOfDay < startMinutes {
            // The early-morning tail of a window that began the previous evening.
            windowStart = calendar.date(byAdding: .day, value: -1, to: windowStart) ?? windowStart
        }
        return windowStart.addingTimeInterval(-InsightsConfig.quietHoursLeadIn.timeInterval)
    }

    // MARK: - Snooze (§2.3)

    public static func snoozeDate(_ option: SnoozeOption, now: Date, dueAt: Date?, timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        switch option {
        case .oneHour:
            return now.addingTimeInterval(3600)
        case .tonight:
            return calendar.date(bySettingHour: InsightsConfig.snoozeTonightHour, minute: InsightsConfig.snoozeTonightMinute, second: 0, of: now)
        case .tomorrowMorning:
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return nil }
            return calendar.date(bySettingHour: InsightsConfig.snoozeTomorrowMorningHour,
                                 minute: InsightsConfig.snoozeTomorrowMorningMinute, second: 0, of: tomorrow)
        case .dayBeforeDue:
            guard let due = dueAt else { return nil }
            return calendar.date(byAdding: .day, value: -1, to: due)
        }
    }

    // MARK: - Calendar helpers

    private static func nextOccurrence(hour: Int, minute: Int, from now: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return now }
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    private static func nextSunday(hour: Int, minute: Int, from now: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let todayWeekday = calendar.component(.weekday, from: now) // Sunday == 1
        let daysUntilSunday = (1 - todayWeekday + 7) % 7
        let candidateDay = calendar.date(byAdding: .day, value: daysUntilSunday, to: calendar.startOfDay(for: now)) ?? now
        guard let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: candidateDay) else { return now }
        if fire > now { return fire }
        return calendar.date(byAdding: .day, value: 7, to: fire) ?? fire
    }
}
