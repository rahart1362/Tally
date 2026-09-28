import Foundation
import TallyDomain

/// A course's health (insights-at-a-glance.md §5.4), shown on the course card as a chip with an
/// icon and a word, never colour alone (ux-ui.md §3.1 rule 4).
public nonisolated enum CourseHealth: String, Equatable, Sendable, CaseIterable {
    case onTrack, needsAttention, atRisk, noGradeYet

    /// The chip's words; VoiceOver reads the same text.
    public var label: String {
        switch self {
        case .onTrack: "On track"
        case .needsAttention: "Needs attention"
        case .atRisk: "At risk"
        case .noGradeYet: "No grade yet"
        }
    }

    /// The chip's SF Symbol (ux-ui.md §3.7.2): a distinct shape per state.
    public var symbol: String {
        switch self {
        case .onTrack: "checkmark.circle"
        case .needsAttention: "exclamationmark.circle"
        case .atRisk: "exclamationmark.triangle"
        case .noGradeYet: "minus.circle"
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
/// - **On track**: otherwise.
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

    public static func evaluate(
        course: Course, groups: [AssignmentGroup], gradingPeriods: [GradingPeriod], goal: Double? = nil,
        formatter: ScreenFormatter
    ) -> Evaluation {
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
        let score = course.gradeVisibility == .visible ? course.scores?.currentScore : nil
        let missingReason = openMissing == 1
            ? "1 missing item is still accepted"
            : "\(openMissing) missing items are still accepted"

        if let score, let goal, score < goal - InsightsConfig.courseHealthAtRiskGoalGap {
            return Evaluation(health: .atRisk, reasons: ["Below your \(formatter.pointsText(goal))% goal"]
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
            return "\(gapText(score - goal, formatter)) your \(formatter.pointsText(goal))% goal"
        }
        // Descending, so the first cutoff at or below the score is the nearest one below it.
        guard letterCutoffs,
              let cutoff = InsightsConfig.standardLetterBoundaries.first(where: { score >= $0 }),
              score - cutoff <= window else { return nil }
        return "\(gapText(score - cutoff, formatter)) the \(formatter.pointsText(cutoff))% cutoff"
    }

    /// "0.4 points above", "1 point above", or "Just above" under a tenth of a point.
    private static func gapText(_ gap: Double, _ formatter: ScreenFormatter) -> String {
        let tenths = (gap * 10).rounded() / 10
        if tenths < 0.1 { return "Just above" }
        return tenths == 1 ? "1 point above" : "\(formatter.pointsText(tenths)) points above"
    }
}
