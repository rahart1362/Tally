import Foundation

/// insights-at-a-glance §2: one alert taxonomy shared by in-app "Needs
/// attention", pushes and the digest. Every rule here is a pure function of
/// its inputs (a snapshot's facts, user settings/state and `now`) — no I/O,
/// no persisted state read directly (callers pass in whatever prior state a
/// rule needs, e.g. `wasActive` or `previousScore`), per the implementation
/// brief's Canvas-parity and "pure function" requirements.
///
/// Covers the seven categories named in the work package: missing (A1/A2),
/// due soon (A3), grade posted (A4), below goal/threshold (A5, plus the
/// related A6 significant-drop), overload cluster (A7), schedule conflict
/// (A8), and sync/sign-in state (A12). The UX review's A9 (due date moved),
/// A10 (new work) and A11 (announcements) are diff-based alerts not listed
/// in this work package's scope and are not implemented here.
public enum AlertEngine {
    // MARK: - A1/A2: missing

    /// A1 (open) or A2 (closed, grouped per course), or nil if not missing.
    /// Excused submissions never fire. An assignment with no digital
    /// submission expected (`submission_types` all `none`/`on_paper`) only
    /// counts when Canvas itself already flags `missing` (§2.4 A1 params).
    public static func missingAlert(assignment: Assignment, now: Date) -> Alert? {
        guard let submission = assignment.submission, !submission.excused else { return nil }
        let noDigitalSubmissionExpected = !assignment.submissionTypes.isEmpty
            && assignment.submissionTypes.allSatisfy { $0 == "none" || $0 == "on_paper" }
        let isMissing = submission.missing
            || (!noDigitalSubmissionExpected
                && submission.workflowState == "unsubmitted"
                && (assignment.dueAt.map { $0 < now } ?? false))
        guard isMissing else { return nil }

        let isOpen = assignment.lockAt.map { $0 > now } ?? true
        guard isOpen else {
            return Alert(kind: .missingClosed(courseID: assignment.courseID), severity: .medium, courseID: assignment.courseID)
        }
        let withinCriticalWindow = assignment.lockAt.map {
            $0.timeIntervalSince(now) <= InsightsConfig.alertCriticalLockWindow.timeInterval
        } ?? false
        return Alert(
            kind: .missingOpen(assignmentID: assignment.id),
            severity: withinCriticalWindow ? .critical : .high,
            courseID: assignment.courseID)
    }

    // MARK: - A3: due soon

    /// nil when not applicable (submitted/excused/no due date) or outside the
    /// 72 h window and below the medium-weight floor (it still surfaces in
    /// "Next up" via `PriorityScore`, just not as a separate alert, §2.1 A3).
    public static func dueSoonAlert(
        assignment: Assignment, priorityScore: Double, weight: Double, now: Date
    ) -> Alert? {
        guard let due = assignment.dueAt else { return nil }
        guard let submission = assignment.submission, !submission.isSubmitted, !submission.excused else { return nil }
        let hours = due.timeIntervalSince(now) / 3600
        guard hours >= 0 else { return nil } // overdue is A1/A2, not A3

        if hours < InsightsConfig.dueSoonCriticalWindowHours, priorityScore >= InsightsConfig.dueSoonCriticalMinPriority {
            return Alert(kind: .dueSoon(assignmentID: assignment.id), severity: .critical, courseID: assignment.courseID,
                        priority: Int(priorityScore))
        }
        if hours < InsightsConfig.dueSoonHighWindowHours {
            return Alert(kind: .dueSoon(assignmentID: assignment.id), severity: .high, courseID: assignment.courseID,
                        priority: Int(priorityScore))
        }
        if hours < InsightsConfig.dueSoonMediumWindowHours, weight >= InsightsConfig.dueSoonMediumMinWeight {
            return Alert(kind: .dueSoon(assignmentID: assignment.id), severity: .medium, courseID: assignment.courseID,
                        priority: Int(priorityScore))
        }
        return nil
    }

    // MARK: - A4: grade posted

    /// Compares one assignment's submission across two snapshots. nil on the
    /// first snapshot after sign-in (no `previous`), per the architecture's
    /// "no digest or grade alerts on the first snapshot" rule — callers
    /// should not invoke this at all when there is no previous snapshot.
    public static func gradePostedAlert(previous: Assignment?, current: Assignment) -> Alert? {
        guard let submission = current.submission, let postedAt = submission.postedAt, submission.score != nil else {
            return nil
        }
        guard previous?.submission?.postedAt != postedAt else { return nil }
        let submissionID = submission.id ?? CanvasID(current.id.rawValue)
        return Alert(kind: .gradePosted(submissionID: submissionID, postedAt: postedAt), severity: .info, courseID: current.courseID)
    }

    // MARK: - A5/A6: below goal, significant drop

    /// Whether A5 is currently active, applying §2.3's hysteresis: once
    /// active, it takes a rise to `goal + belowGoalHysteresis` to clear,
    /// not just `goal`, so the alert doesn't flicker at the line.
    public static func belowGoalIsActive(currentScore: Double, goal: Double, wasActive: Bool) -> Bool {
        wasActive ? currentScore < goal + InsightsConfig.belowGoalHysteresis : currentScore < goal
    }

    /// nil when the course hides final grades (§2.4 data-quality guard), has
    /// no goal set, or is not below goal.
    public static func belowGoalAlert(
        courseID: CanvasID<Course>, currentScore: Double?, goal: Double?, wasActive: Bool, gradeVisibility: GradeVisibility
    ) -> Alert? {
        guard gradeVisibility == .visible, let currentScore, let goal else { return nil }
        guard belowGoalIsActive(currentScore: currentScore, goal: goal, wasActive: wasActive) else { return nil }
        return Alert(kind: .belowGoal(courseID: courseID), severity: .high, courseID: courseID)
    }

    /// A6, superseded by A5 for the same course (§2.3): pass whether A5 is
    /// already firing for this course and this returns nil when it is.
    /// Fires on a drop of `oneRefreshDropThreshold` in one refresh, or
    /// `fourteenDayDropThreshold` over 14 days (`score14DaysAgo`, when known
    /// — TallyDomain keeps no local score history, PMO R9, so callers supply
    /// this from Canvas's graded-submission history when available).
    public static func significantDropAlert(
        courseID: CanvasID<Course>, currentScore: Double?, previousRefreshScore: Double?, score14DaysAgo: Double?,
        weekOf: Date, belowGoalIsFiring: Bool, gradeVisibility: GradeVisibility
    ) -> Alert? {
        guard !belowGoalIsFiring, gradeVisibility == .visible, let currentScore else { return nil }
        let oneRefreshDrop = previousRefreshScore.map { $0 - currentScore } ?? 0
        let fourteenDayDrop = score14DaysAgo.map { $0 - currentScore } ?? 0
        guard oneRefreshDrop >= InsightsConfig.oneRefreshDropThreshold
            || fourteenDayDrop >= InsightsConfig.fourteenDayDropThreshold else { return nil }
        return Alert(kind: .significantDrop(courseID: courseID, weekOf: weekOf), severity: .medium, courseID: courseID)
    }

    // MARK: - A7: overload cluster

    public struct LoadItem: Sendable, Equatable {
        public let dueAt: Date
        public let weight: Double
        public let courseID: CanvasID<Course>
        public init(dueAt: Date, weight: Double, courseID: CanvasID<Course>) {
            self.dueAt = dueAt
            self.weight = weight
            self.courseID = courseID
        }
    }

    /// Scans every rolling `overloadWindow` inside the next `overloadHorizon`
    /// for either `>= overloadMinItems` open items or a single course's
    /// combined weight `>= overloadMinCourseWeight`. Candidate window starts
    /// are sampled at each item's own due instant: the count/weight inside a
    /// window can only change at those instants, so this finds every
    /// maximal-count window without a continuous scan. Adjacent qualifying
    /// windows are merged into one alert (the first one found) so a single
    /// busy stretch doesn't produce a run of near-duplicate alerts.
    public static func overloadClusters(_ items: [LoadItem], now: Date) -> [Alert] {
        let horizonEnd = now.addingTimeInterval(InsightsConfig.overloadHorizon.timeInterval)
        let inHorizon = items.filter { $0.dueAt >= now && $0.dueAt <= horizonEnd }
        guard !inHorizon.isEmpty else { return [] }

        let candidateStarts = Set(inHorizon.map(\.dueAt)).sorted()
        var alerts: [Alert] = []
        var lastFiredEnd: Date?

        for start in candidateStarts {
            if let lastFiredEnd, start < lastFiredEnd { continue }
            let end = start.addingTimeInterval(InsightsConfig.overloadWindow.timeInterval)
            let windowItems = inHorizon.filter { $0.dueAt >= start && $0.dueAt < end }
            guard !windowItems.isEmpty else { continue }
            let maxCourseWeight = Dictionary(grouping: windowItems, by: \.courseID)
                .mapValues { $0.reduce(0.0) { $0 + $1.weight } }
                .values.max() ?? 0
            guard windowItems.count >= InsightsConfig.overloadMinItems
                || maxCourseWeight >= InsightsConfig.overloadMinCourseWeight else { continue }

            let severity: AlertSeverity = start.timeIntervalSince(now) <= InsightsConfig.overloadHighWindow.timeInterval
                ? .high : .medium
            alerts.append(Alert(kind: .overloadCluster(windowStart: start), severity: severity))
            lastFiredEnd = end
        }
        return alerts
    }

    // MARK: - A8: schedule conflict

    /// A class, exam or due instant. `end == nil` means an instant (a due
    /// time); a real interval carries both `start` and `end`.
    public struct ScheduleItem: Sendable, Equatable {
        public let id: String
        public let start: Date
        public let end: Date?
        public let isExam: Bool
        public init(id: String, start: Date, end: Date? = nil, isExam: Bool = false) {
            self.id = id
            self.start = start
            self.end = end
            self.isExam = isExam
        }
    }

    /// Exam-vs-class or exam-vs-exam overlap is High; an ordinary due time
    /// during a class, or two ordinary due instants within `closeDueGap`, is
    /// Info (§2.1 A8).
    public static func scheduleConflicts(_ items: [ScheduleItem]) -> [Alert] {
        var alerts: [Alert] = []
        for i in items.indices {
            for j in (i + 1)..<items.count {
                let a = items[i]
                let b = items[j]
                guard overlaps(a, b) else { continue }
                let severity: AlertSeverity = (a.isExam || b.isExam) ? .high : .info
                let ids = a.id < b.id ? (a.id, b.id) : (b.id, a.id)
                alerts.append(Alert(kind: .scheduleConflict(idA: ids.0, idB: ids.1), severity: severity))
            }
        }
        return alerts
    }

    private static func overlaps(_ a: ScheduleItem, _ b: ScheduleItem) -> Bool {
        switch (a.end, b.end) {
        case let (ae?, be?):
            return a.start < be && b.start < ae
        case let (ae?, nil):
            return b.start >= a.start && b.start <= ae
        case let (nil, be?):
            return a.start >= b.start && a.start <= be
        case (nil, nil):
            return abs(a.start.timeIntervalSince(b.start)) <= InsightsConfig.closeDueGap.timeInterval
        }
    }

    // MARK: - A12: sync / sign-in state

    /// Reuses the already-verified `FreshnessRules` for `authExpired`/stale
    /// detection rather than re-deriving freshness logic here.
    public static func syncAlerts(
        refresh: RefreshRecord, now: Date,
        notificationsAuthorized: Bool, remindersEnabled: Bool,
        backgroundRefreshEnabled: Bool, schoolEnabled: Bool
    ) -> [Alert] {
        var alerts: [Alert] = []
        switch FreshnessRules.state(of: refresh, now: now) {
        case .authExpired:
            alerts.append(Alert(kind: .sync(.authExpired), severity: .high))
        default:
            if let staleDate = FreshnessRules.staleWarningDate(of: refresh), staleDate <= now {
                alerts.append(Alert(kind: .sync(.staleOver24h), severity: .medium))
            }
        }
        if !notificationsAuthorized, remindersEnabled {
            alerts.append(Alert(kind: .sync(.notificationsOffRulesOn), severity: .medium))
        }
        if !backgroundRefreshEnabled {
            alerts.append(Alert(kind: .sync(.backgroundRefreshOff), severity: .info))
        }
        if !schoolEnabled {
            alerts.append(Alert(kind: .sync(.schoolNotEnabled), severity: .high))
        }
        return alerts
    }

    // MARK: - §2.3 dismiss / worsen / snooze

    /// Whether an alert should be shown given its prior `state`. A snoozed
    /// alert is hidden until the snooze passes. A dismissed alert stays
    /// hidden unless it has worsened: a strictly higher severity than when
    /// dismissed, or (for alerts tracking a numeric gap, e.g. points below
    /// goal) a gap that grew by at least `dismissWorsenGap`. "A new type" of
    /// alert on the same subject (§2.3) needs no special case here: a
    /// different `AlertKind` has a different `dedupeKey`, so it simply has no
    /// prior `state` and is visible by construction.
    public static func isVisible(_ alert: Alert, state: AlertState?, now: Date, gapGrewBy: Double = 0) -> Bool {
        guard let state else { return true }
        if let snoozedUntil = state.snoozedUntil, snoozedUntil > now { return false }
        guard state.dismissedAt != nil else { return true }
        if let dismissedSeverity = state.dismissedSeverity, alert.severity > dismissedSeverity { return true }
        if gapGrewBy >= InsightsConfig.dismissWorsenGap { return true }
        return false
    }
}
