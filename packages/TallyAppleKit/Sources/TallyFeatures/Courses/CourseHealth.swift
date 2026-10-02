import Foundation
import TallyDomain
import TallyStrings

/// A course's health (insights-at-a-glance.md §5.4), shown on the course card as a chip with an
/// icon and a word, never colour alone (ux-ui.md §3.1 rule 4).
public nonisolated enum CourseHealth: String, Equatable, Sendable, CaseIterable {
    case onTrack, needsAttention, atRisk, noGradeYet
    /// Plan 08 §4.4 row 4 (XG-03): the course's grades are kept outside Canvas and nothing else
    /// needs attention. Missing work still makes it "Needs attention" or "At risk".
    case gradeNotInCanvas

    /// The chip's words; VoiceOver reads the same text.
    public var label: String {
        switch self {
        case .onTrack: L10n.string(L10n.Courses.healthOnTrack)
        case .needsAttention: L10n.string(L10n.Courses.healthNeedsAttention)
        case .atRisk: L10n.string(L10n.Courses.healthAtRisk)
        case .noGradeYet: L10n.string(L10n.Grades.noGradeYet)
        case .gradeNotInCanvas: L10n.string(L10n.Grades.notInCanvasStatus)
        }
    }

    /// The chip's SF Symbol (ux-ui.md §3.7.2). The two "no grade" states share `minus.circle`
    /// (plan 08 §4.4 row 4); their words differ.
    public var symbol: String {
        switch self {
        case .onTrack: "checkmark.circle"
        case .needsAttention: "exclamationmark.circle"
        case .atRisk: "exclamationmark.triangle"
        case .noGradeYet, .gradeNotInCanvas: "minus.circle"
        }
    }

    /// The states the grade's own place already says ("No grade yet", the dash and "Not in
    /// Canvas"): a card or hero shows no chip for them, and VoiceOver does not hear them twice.
    public var isSaidByTheGrade: Bool {
        switch self {
        case .noGradeYet, .gradeNotInCanvas: true
        case .onTrack, .needsAttention, .atRisk: false
        }
    }
}

/// §5.4's course-health rules, evaluated from one snapshot. Pure; the rule inputs are named in
/// `InsightsConfig` (the domain lane's constants):
/// - **At risk**: current score more than `courseHealthAtRiskGoalGap` below the student's goal, or
///   at least `courseHealthAtRiskMissingCount` open missing items each worth at least
///   `courseHealthAtRiskMissingWeight` of the course.
/// - **Needs attention**: within `courseHealthNeedsAttentionWindow` points above the goal or a
///   letter cutoff, or at least one open missing item.
/// - **No grade yet**: nothing above applies and there is no grade the student can see (hidden
///   totals, or no score yet).
/// - **Grade not in Canvas** (plan 08 §4.4 row 4): nothing above applies and the course's grades
///   are kept outside Canvas.
/// - **On track**: otherwise.
///
/// Plan 08 §4.4 rows 4 and 10: the score (and so every grade and goal rule) is used only for a
/// course whose grades are in Canvas as percentages (`.available`); for every other course only
/// the missing-work rules run.
///
/// Two §5.4 inputs are not available to this build, so their rules cannot fire: the student's
/// goals (no goal is stored in `UserState`), and "a drop of 3 points over 14 days" (TallyCore keeps
/// no score history, R9, and deriving one here would mean grade math outside `GradeWork`). The
/// letter cutoffs are `InsightsConfig.standardLetterBoundaries`, which that config marks UNVERIFIED
/// as a stand-in for a course's own grading scheme.
public nonisolated enum CourseHealthRules {
    public nonisolated struct Evaluation: Equatable, Sendable {
        public let health: CourseHealth
        /// Why, in plain words, strongest first (Insights shows them; empty when on track).
        public let reasons: [String]
        /// Open missing items (still accepted), for the To-Do and the reasons.
        public let openMissingCount: Int
    }

    /// - Parameter availability: the course's state in the projection's `GradeAvailabilityIndex`;
    ///   `nil` classifies the course here, at `formatter.now`, with no override.
    public static func evaluate(
        course: Course, groups: [AssignmentGroup], gradingPeriods: [GradingPeriod], goal: Double? = nil,
        availability: GradeAvailability? = nil, formatter: ScreenFormatter
    ) -> Evaluation {
        let availability = availability
            ?? GradeAvailabilityRules.classify(course: course, groups: groups, now: formatter.now, override: nil)
        let weights = PriorityScore.WeightContext(course: course, groups: groups, gradingPeriods: gradingPeriods)
        var openMissing = 0
        var heavyOpenMissing = 0
        for assignment in groups.flatMap(\.assignments) where assignment.published {
            guard let alert = AlertEngine.missingAlert(assignment: assignment, now: formatter.now),
                  case .missingOpen = alert.kind else { continue }
            openMissing += 1
            if weights.weight(of: assignment) >= InsightsConfig.courseHealthAtRiskMissingWeight {
                heavyOpenMissing += 1
            }
        }
        let score = availability == .available ? course.scores?.currentScore : nil
        let missingReason = L10n.string(L10n.Courses.missingItemsStillAccepted, openMissing)

        if let score, let goal, score < goal - InsightsConfig.courseHealthAtRiskGoalGap {
            let reason = L10n.string(L10n.Courses.belowGoalReason, formatter.trimmedPercentText(goal))
            return Evaluation(health: .atRisk, reasons: [reason]
                              + (openMissing > 0 ? [missingReason] : []), openMissingCount: openMissing)
        }
        if heavyOpenMissing >= InsightsConfig.courseHealthAtRiskMissingCount {
            return Evaluation(health: .atRisk, reasons: [missingReason], openMissingCount: openMissing)
        }

        var reasons: [String] = []
        if openMissing > 0 { reasons.append(missingReason) }
        // A pass/fail course has no letter cutoffs to be near (only its goal, if one is set).
        let passFail = course.scores?.currentGrade.map {
            [.passing, .failing].contains(GradeBand.from(letterOrPassFail: $0))
        } ?? false
        if let score, let cutoff = nearCutoff(score: score, goal: goal, letterCutoffs: !passFail, formatter: formatter) {
            reasons.append(cutoff)
        }
        if !reasons.isEmpty {
            return Evaluation(health: .needsAttention, reasons: reasons, openMissingCount: openMissing)
        }
        if case .keptOutsideCanvas = availability {
            return Evaluation(health: .gradeNotInCanvas, reasons: [], openMissingCount: openMissing)
        }
        guard score != nil else {
            return Evaluation(health: .noGradeYet, reasons: [], openMissingCount: openMissing)
        }
        return Evaluation(health: .onTrack, reasons: [], openMissingCount: openMissing)
    }

    /// "0.1 points above the 90% cutoff": the score sits within the window above the goal, or above
    /// the nearest standard cutoff at or below it. `nil` otherwise.
    static func nearCutoff(score: Double, goal: Double?, letterCutoffs: Bool = true, formatter: ScreenFormatter) -> String? {
        let window = InsightsConfig.courseHealthNeedsAttentionWindow
        if let goal, score >= goal, score - goal <= window {
            return L10n.string(L10n.Courses.aboveGoalReason, gapText(score - goal, formatter), formatter.trimmedPercentText(goal))
        }
        // Descending, so the first cutoff at or below the score is the nearest one below it.
        guard letterCutoffs,
              let cutoff = InsightsConfig.standardLetterBoundaries.first(where: { score >= $0 }),
              score - cutoff <= window else { return nil }
        return L10n.string(L10n.Courses.aboveCutoffReason, gapText(score - cutoff, formatter), formatter.trimmedPercentText(cutoff))
    }

    /// "0.4 points above", "1 point above", or "Just above" under a tenth of a point. `tenths == 1`
    /// is a fixed pair with `pointsAboveCount`, not a catalog plural (the same choice L10N-03a
    /// documented for settings.threshold.pointsOne/pointsOther): `gap` is an unrounded Double, not a
    /// clean plural count.
    private static func gapText(_ gap: Double, _ formatter: ScreenFormatter) -> String {
        let tenths = (gap * 10).rounded() / 10
        if tenths < 0.1 { return L10n.string(L10n.Courses.justAbove) }
        return tenths == 1
            ? L10n.string(L10n.Courses.pointAbove)
            : L10n.string(L10n.Courses.pointsAboveCount, formatter.pointsText(tenths))
    }
}
