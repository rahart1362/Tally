import Foundation

/// Every tunable number the insights lane introduces (priority score, alerts,
/// reminders), named once — mirroring `TallyConfig`'s rule that no magic
/// number lives inline (implementation brief hard rule 4). Values are taken
/// from `docs/pmo/ux/insights-at-a-glance.md` §5.1/§5.2 unless noted.
public enum InsightsConfig {
    // MARK: - Priority score (§5.1: "What should I do next?")

    /// τ: the urgency half-life in hours. `U = exp(-h/τ)` for an item due in `h` hours.
    public static let priorityUrgencyHalfLifeHours: Double = 48

    /// `wRef`: the course-weight share at which an item is "max important" (`I = 1`).
    public static let priorityWeightReference: Double = 0.10

    /// α: how much urgency counts vs importance in the blended score.
    public static let priorityAlpha: Double = 0.6

    /// `S`: multiplier for an item that is overdue but still open (`lock_at`
    /// nil or in the future) — "late beats zero".
    public static let priorityStillAcceptedBonus: Double = 1.15

    /// `C`: multiplier when the course is below the student's goal.
    public static let priorityBelowGoalBonus: Double = 1.20

    /// `C`: multiplier when the course is within `priorityBoundaryWindow`
    /// points *above* a letter boundary or the goal (and not already below it).
    public static let priorityNearBoundaryBonus: Double = 1.10

    /// The "near a boundary" window, in percentage points.
    public static let priorityBoundaryWindow: Double = 1.5

    /// Band cutoffs: High >= 60, Medium in [35, 60), Low < 35.
    public static let priorityHighThreshold: Double = 60
    public static let priorityMediumThreshold: Double = 35

    /// A reason clause is shown for the item's course-weight share only when
    /// it clears this floor, so a 0.1%-of-course reading list doesn't get a
    /// "~0% of BIO 101" clause. Engineering choice (half of `wRef`), not from
    /// the UX doc, which does not specify a reason-text cutoff.
    public static let priorityReasonWeightFloor: Double = priorityWeightReference / 2

    /// Standard 10-point US letter scale (A 93 / A- 90 / B+ 87 / …), used only
    /// to approximate "near a letter boundary" for the priority score's `C`
    /// modifier and for course-health "near a boundary" checks.
    /// **UNVERIFIED as a stand-in for a real course's grading scheme**:
    /// `Course` carries no `gradingScheme`/`grading_scheme` field today (see
    /// the PMO report for the priority-score work package), so a course using
    /// a custom scale gets an approximate boundary check against this default
    /// rather than its own cutoffs.
    public static let standardLetterBoundaries: [Double] = [97, 93, 90, 87, 83, 80, 77, 73, 70, 67, 63, 60]

    // MARK: - Course health (§5.4)

    /// "At risk": current score at least this many points below the goal.
    public static let courseHealthAtRiskGoalGap: Double = 3.0
    /// "At risk": at least this many open missing items each worth >= `courseHealthAtRiskMissingWeight`.
    public static let courseHealthAtRiskMissingCount: Int = 2
    public static let courseHealthAtRiskMissingWeight: Double = 0.02
    /// "Needs attention": within this many points of the goal or a boundary.
    public static let courseHealthNeedsAttentionWindow: Double = 1.5
    /// "Needs attention": a drop of at least this many points over 14 days.
    public static let courseHealthDropWindowPoints: Double = 3.0

    // MARK: - Alert rules (§2.4 "Rule inputs")

    /// A1/A2: an open missing item within this long of `lock_at` is Critical
    /// instead of High.
    public static let alertCriticalLockWindow: Duration = .seconds(24 * 60 * 60)

    /// A3 "due soon" windows, in hours: Critical < 3h (and priority >= 60),
    /// High < 24h, Medium < 72h (and weight >= `dueSoonMediumMinWeight`).
    public static let dueSoonCriticalWindowHours: Double = 3
    public static let dueSoonHighWindowHours: Double = 24
    public static let dueSoonMediumWindowHours: Double = 72
    public static let dueSoonCriticalMinPriority: Double = 60
    public static let dueSoonMediumMinWeight: Double = 0.05

    /// A5: once below the goal, the alert only resolves after rising this
    /// many points *above* the goal (hysteresis against flicker at the line).
    public static let belowGoalHysteresis: Double = 0.5

    /// A6: a course score drop of at least this many points in one refresh…
    public static let oneRefreshDropThreshold: Double = 3.0
    /// …or at least this many points over a rolling 14 days.
    public static let fourteenDayDropThreshold: Double = 5.0

    /// A7 overload cluster: a rolling window this wide, scanned across this
    /// many days ahead; fires at >= `overloadMinItems` open items or a single
    /// course's combined weight share >= `overloadMinCourseWeight` in the
    /// window. A window starting within `overloadHighWindow` is High instead
    /// of Medium.
    public static let overloadWindow: Duration = .seconds(48 * 60 * 60)
    public static let overloadHorizon: Duration = .seconds(10 * 24 * 60 * 60)
    public static let overloadMinItems: Int = 4
    public static let overloadMinCourseWeight: Double = 0.15
    public static let overloadHighWindow: Duration = .seconds(48 * 60 * 60)

    /// A8: two due instants (no class/exam interval involved) within this
    /// close together are flagged Info.
    public static let closeDueGap: Duration = .seconds(30 * 60)

    /// §2.3: a dismissed alert is worsened (and so re-shown) when its
    /// tracked numeric gap (e.g. points below goal) grows by at least this much.
    public static let dismissWorsenGap: Double = 2.0

    // MARK: - ReminderPlanner (WP-D02; PMO R14 "Balanced", §3 of insights-at-a-glance)

    /// R14 Balanced: due-item reminders fire this long before `due_at`,
    /// largest offset first. The **last** (soonest-before-due) offset is the
    /// "final hour" reminder (§3.5: Time Sensitive for a High/Critical item).
    public static let balancedDueOffsets: [Duration] = [.seconds(24 * 60 * 60), .seconds(60 * 60)]

    /// §3.3 #2: the missing-and-still-open follow-up fires once, this long after `due_at`.
    public static let missingFollowupOffset: Duration = .seconds(12 * 60 * 60)

    /// §1.3/§3.3 #3: exam reminders fire at 18:00 local on each of these
    /// days before the exam, plus a time-sensitive morning-of reminder.
    public static let examReminderDaysBefore: [Int] = [3, 1]
    public static let examReminderHour = 18
    public static let examReminderMinute = 0
    public static let examMorningOfHour = 7
    public static let examMorningOfMinute = 30

    /// §3.3 #4/#5: the evening digest and Sunday week-ahead default times.
    public static let eveningDigestHour = 19
    public static let eveningDigestMinute = 0
    public static let weekAheadHour = 18
    public static let weekAheadMinute = 0

    /// §3.5 default quiet hours.
    public static let defaultQuietHoursStart = (hour: 23, minute: 0)
    public static let defaultQuietHoursEnd = (hour: 7, minute: 0)
    /// Quiet-hour shifts land this long before quiet hours begin (§3.5 example: 23:30 -> 22:45).
    public static let quietHoursLeadIn: Duration = .seconds(15 * 60)

    /// §2.3 snooze options' fixed local times.
    public static let snoozeTonightHour = 19
    public static let snoozeTonightMinute = 0
    public static let snoozeTomorrowMorningHour = 8
    public static let snoozeTomorrowMorningMinute = 0

    /// §3.8: nothing is scheduled more than this far ahead.
    public static let reminderHorizon: Duration = .seconds(14 * 24 * 60 * 60)
}
