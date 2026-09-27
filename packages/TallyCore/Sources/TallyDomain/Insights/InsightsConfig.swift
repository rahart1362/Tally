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
}
