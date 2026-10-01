import Foundation

/// One course signal the planner schedules an event-style reminder about (grade posted, below
/// goal): a plain Canvas id and course code, **never** the score, grade or goal value that made
/// the caller decide it applies (family-linking.md §6.5 content table — see
/// `FamilyNotificationContentBuilder`'s doc comment for why that decision stays outside FAM-08
/// entirely).
public struct FamilyCourseSignal: Sendable, Equatable {
    public let courseID: String
    public let courseCode: String
    public init(courseID: String, courseCode: String) {
        self.courseID = courseID
        self.courseCode = courseCode
    }
}

/// One linked student's planning input (family-linking.md §6.5, §7.3 "Notifications for
/// Maya"). `candidates` reuses `TallyDomain/Reminders`' own `ReminderCandidate` (the same
/// "what's open and worth a reminder" shape the student planner already uses) rather than a
/// second, parallel definition of "open item".
public struct FamilySubjectPlanInput: Sendable {
    public let subjectID: SubjectKey
    public let studentName: String
    public let candidates: [ReminderCandidate]
    /// Courses a grade was newly posted in since the last successful refresh. Computing *which*
    /// courses those are is a diff over two refreshes (the established idiom for this kind of
    /// signal is `NewObserverDetector`'s "current vs. previously seen" comparison) — outside
    /// this pure planner's input surface, exactly like `ReminderCandidate.isExam` is decided by
    /// its caller rather than re-derived here.
    public let newlyGradedCourses: [FamilyCourseSignal]
    /// Courses currently below whatever goal the parent set for them. Comparing a score against
    /// a threshold is the caller's job; this planner (and everything downstream of it) never
    /// receives either number.
    public let belowGoalCourses: [FamilyCourseSignal]
    public let settings: FamilySubjectNotificationSettings

    public init(subjectID: SubjectKey, studentName: String, candidates: [ReminderCandidate],
                newlyGradedCourses: [FamilyCourseSignal] = [], belowGoalCourses: [FamilyCourseSignal] = [],
                settings: FamilySubjectNotificationSettings = FamilySubjectNotificationSettings()) {
        self.subjectID = subjectID
        self.studentName = studentName
        self.candidates = candidates
        self.newlyGradedCourses = newlyGradedCourses
        self.belowGoalCourses = belowGoalCourses
        self.settings = settings
    }
}

/// FAM-08's planner (family-linking.md §6.5): given every linked student's candidates and
/// settings, returns exactly the set of parent-facing local notifications that should be
/// pending — no I/O, no `UNUserNotificationCenter`, "beside the existing reminder planner's
/// design" (`TallyDomain/Reminders/ReminderPlanner`), which this reuses for quiet-hours shifting
/// rather than re-deriving it.
///
/// The account-level freshness sentinel is deliberately not produced here — see
/// `FamilyNotificationKind`'s doc comment — so every id this planner emits is a genuine
/// per-subject kind.
public enum FamilyNotificationPlanner {
    /// - Parameters:
    ///   - subjects: every linked student to plan for. An empty list plans nothing (the
    ///     zero-students empty state, family-linking.md §7.6, has nothing to notify about).
    ///   - cap: the total pending-notification budget across every subject on this device
    ///     (`TallyConfig.pendingNotificationCap`, shared with the student planner).
    ///   - floorPerSubject: §6.4's "floor of 4 per subject" (`TallyConfig.
    ///     familyNotificationFloorPerSubject`).
    public static func plan(
        accountKey: AccountKey, subjects: [FamilySubjectPlanInput], now: Date, timeZone: TimeZone,
        quietHours: QuietHours = QuietHours(), cap: Int = TallyConfig.pendingNotificationCap,
        floorPerSubject: Int = TallyConfig.familyNotificationFloorPerSubject
    ) -> [PendingFamilyReminder] {
        guard !subjects.isEmpty else { return [] }

        // §6.4: weighted by due-item count; a subject with nothing due still gets its floor.
        let weights = subjects.map { (subject: $0.subjectID, weight: max(1, $0.candidates.count)) }
        let budgets = FamilySubjectBudget.allocate(weights: weights, cap: cap, floorPerSubject: floorPerSubject)

        var planned: [PendingFamilyReminder] = []
        for subject in subjects {
            let budget = budgets[subject.subjectID] ?? 0
            guard budget > 0 else { continue }
            let desired = desiredReminders(accountKey: accountKey, subject: subject, now: now, timeZone: timeZone, quietHours: quietHours)
                .sorted(by: bySoonestThenID)
            planned += Array(desired.prefix(budget))
        }
        return planned.sorted(by: bySoonestThenID)
    }

    private static func bySoonestThenID(_ a: PendingFamilyReminder, _ b: PendingFamilyReminder) -> Bool {
        a.fireDate != b.fireDate ? a.fireDate < b.fireDate : a.id < b.id
    }

    private static func desiredReminders(
        accountKey: AccountKey, subject: FamilySubjectPlanInput, now: Date, timeZone: TimeZone, quietHours: QuietHours
    ) -> [PendingFamilyReminder] {
        var out: [PendingFamilyReminder] = []

        if subject.settings.weekAheadEnabled {
            out.append(weekAheadReminder(accountKey: accountKey, subject: subject, now: now, timeZone: timeZone, quietHours: quietHours))
        }

        for candidate in subject.candidates {
            guard !PriorityScore.isExcluded(assignment: candidate.assignment, markedDone: candidate.markedDone, now: now),
                  let due = candidate.assignment.dueAt
            else { continue }

            if subject.settings.missingStillOpenEnabled {
                let fire = due.addingTimeInterval(InsightsConfig.missingFollowupOffset.timeInterval)
                let isOpenAtFollowup = candidate.assignment.lockAt.map { $0 > fire } ?? true
                if isOpenAtFollowup {
                    let shifted = ReminderPlanner.shiftOutOfQuietHours(fire, quietHours: quietHours, timeZone: timeZone)
                    out.append(PendingFamilyReminder(
                        id: FamilyNotificationID.make(accountKey: accountKey, subjectKey: subject.subjectID, kind: .missingStillOpen,
                                                      canvasID: candidate.assignment.id.rawValue, ruleID: "followup",
                                                      offset: "\(Int(InsightsConfig.missingFollowupOffset.timeInterval))"),
                        kind: .missingStillOpen, subjectID: subject.subjectID, fireDate: shifted, interruptionLevel: .active))
                }
            }

            if subject.settings.dueRemindersEnabled {
                let offsets = InsightsConfig.balancedDueOffsets
                for (index, offset) in offsets.enumerated() {
                    let isFinal = index == offsets.count - 1
                    let fire = due.addingTimeInterval(-offset.timeInterval)
                    let shifted = ReminderPlanner.shiftOutOfQuietHours(fire, quietHours: quietHours, timeZone: timeZone)
                    out.append(PendingFamilyReminder(
                        id: FamilyNotificationID.make(accountKey: accountKey, subjectKey: subject.subjectID, kind: .dueReminder,
                                                      canvasID: candidate.assignment.id.rawValue, ruleID: "due", offset: "\(Int(offset.timeInterval))"),
                        kind: .dueReminder, subjectID: subject.subjectID, fireDate: shifted,
                        interruptionLevel: isFinal ? .timeSensitive : .active))
                }
            }
        }

        if subject.settings.gradePostedEnabled {
            let shifted = ReminderPlanner.shiftOutOfQuietHours(now, quietHours: quietHours, timeZone: timeZone)
            for course in subject.newlyGradedCourses {
                out.append(PendingFamilyReminder(
                    id: FamilyNotificationID.make(accountKey: accountKey, subjectKey: subject.subjectID, kind: .gradePosted,
                                                  canvasID: course.courseID, ruleID: "posted", offset: "0"),
                    kind: .gradePosted, subjectID: subject.subjectID, fireDate: shifted, interruptionLevel: .active))
            }
        }

        if subject.settings.belowGoalEnabled {
            let shifted = ReminderPlanner.shiftOutOfQuietHours(now, quietHours: quietHours, timeZone: timeZone)
            for course in subject.belowGoalCourses {
                out.append(PendingFamilyReminder(
                    id: FamilyNotificationID.make(accountKey: accountKey, subjectKey: subject.subjectID, kind: .belowGoal,
                                                  canvasID: course.courseID, ruleID: "attention", offset: "0"),
                    kind: .belowGoal, subjectID: subject.subjectID, fireDate: shifted, interruptionLevel: .active))
            }
        }

        // A reminder computed strictly into the past (e.g. "still open" 12h after a due date
        // that has already passed `now` by more than that) is never scheduled — mirrors
        // `ReminderPlanner.plan`'s own horizon filter (it never hands back a stale request).
        // `gradePosted`/`belowGoal` fire at `now` itself (an event detected during this refresh,
        // not a time-of-day schedule), so `now` itself must stay in, not just strictly after it.
        return out.filter { $0.fireDate >= now }
    }

    private static func weekAheadReminder(
        accountKey: AccountKey, subject: FamilySubjectPlanInput, now: Date, timeZone: TimeZone, quietHours: QuietHours
    ) -> PendingFamilyReminder {
        let fire = nextSunday(hour: InsightsConfig.weekAheadHour, minute: InsightsConfig.weekAheadMinute, from: now, timeZone: timeZone)
        let shifted = ReminderPlanner.shiftOutOfQuietHours(fire, quietHours: quietHours, timeZone: timeZone)
        return PendingFamilyReminder(
            id: FamilyNotificationID.make(accountKey: accountKey, subjectKey: subject.subjectID, kind: .weekAhead,
                                          canvasID: "-", ruleID: "sunday", offset: "0"),
            kind: .weekAhead, subjectID: subject.subjectID, fireDate: shifted, interruptionLevel: .passive)
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
