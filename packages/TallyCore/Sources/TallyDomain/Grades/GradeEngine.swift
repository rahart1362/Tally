import Foundation

/// One assignment group's sums for one branch (current or final).
public struct GroupScore: Sendable, Equatable {
    public let groupID: CanvasID<AssignmentGroup>
    /// Sum of the kept scores.
    public let score: Decimal
    /// Sum of the kept points possible.
    public let possible: Decimal
    public let weight: Double
    /// Percent, BigDecimal-rounded to 2 places; nil when nothing is possible.
    public let grade: Double?
    public let droppedSubmissionIDs: [CanvasID<Submission>]
    public let keptAssignmentIDs: [CanvasID<Assignment>]
}

/// Current (graded work only) and final (ungraded counts as zero) for one scope.
public struct ScoreSet: Sendable, Equatable {
    public let currentScore: Double?
    public let finalScore: Double?
    public let currentGroups: [GroupScore]
    public let finalGroups: [GroupScore]
}

public struct PeriodScores: Sendable, Equatable {
    public let periodID: CanvasID<GradingPeriod>
    /// What the student sees (unposted work treated as absent).
    public let posted: ScoreSet
    /// Including unposted work (as far as the client can see it).
    public let unposted: ScoreSet
}

/// What Canvas stores for one student enrollment (GradeCalculator#compute_and_save_scores).
public struct EnrollmentScores: Sendable, Equatable {
    /// `computed_current_score`.
    public let currentScore: Double?
    /// `computed_final_score`.
    public let finalScore: Double?
    public let unpostedCurrentScore: Double?
    public let unpostedFinalScore: Double?
    /// The course total is the weighted mean of the rounded period scores.
    public let usesWeightedGradingPeriods: Bool
    /// Course-wide (all periods) branches.
    public let posted: ScoreSet
    public let unposted: ScoreSet
    /// One entry per grading period, in the input's order.
    public let gradingPeriods: [PeriodScores]

    public func period(_ id: CanvasID<GradingPeriod>) -> PeriodScores? { gradingPeriods.first { $0.periodID == id } }
}

/// Canvas's course-score math, ported from tools/canvas-synth/canvas_synth/gradecalc.py
/// (itself a port of canvas-lms lib/grade_calculator.rb @1c9f0bb). Pure and synchronous.
public enum GradeEngine {
    public static func scores(course: Course, groups: [AssignmentGroup], gradingPeriods: [GradingPeriod]) -> EnrollmentScores {
        scores(for: GradeInput(course: course, groups: groups, gradingPeriods: gradingPeriods))
    }

    /// gradecalc.py `compute_enrollment_scores`.
    public static func scores(for input: GradeInput) -> EnrollmentScores {
        let periods = input.periods.map { p in
            PeriodScores(periodID: p.id,
                         posted: scoreSet(input, gradingPeriodID: p.id, ignoreUnposted: true),
                         unposted: scoreSet(input, gradingPeriodID: p.id, ignoreUnposted: false))
        }
        let posted = scoreSet(input, gradingPeriodID: nil, ignoreUnposted: true)
        let unposted = scoreSet(input, gradingPeriodID: nil, ignoreUnposted: false)
        let weighted = input.hasWeightedGradingPeriods && !input.periods.isEmpty
        if weighted {
            let combined = combineWeightedGradingPeriods(
                zip(input.periods, periods).map { (weight: $0.weight, current: $1.posted.currentScore, final: $1.posted.finalScore) })
            // Canvas's hidden-scores branch also reads the posted period columns.
            return EnrollmentScores(currentScore: combined.current, finalScore: combined.final,
                                    unpostedCurrentScore: combined.current, unpostedFinalScore: combined.final,
                                    usesWeightedGradingPeriods: true, posted: posted, unposted: unposted, gradingPeriods: periods)
        }
        return EnrollmentScores(currentScore: posted.currentScore, finalScore: posted.finalScore,
                                unpostedCurrentScore: unposted.currentScore, unpostedFinalScore: unposted.finalScore,
                                usesWeightedGradingPeriods: false, posted: posted, unposted: unposted, gradingPeriods: periods)
    }

    /// Ruby `Float#round(ndigits)` (half up on the decimal literal: 93.825 -> 93.83).
    public static func rubyFloatRound(_ number: Double, _ ndigits: Int = 2) -> Double {
        RubyNumerics.floatRound(number, ndigits)
    }

    /// gradecalc.py `current_grading_period`: `start < now <= end`, each truncated to the minute.
    public static func currentGradingPeriod(in periods: [GradingPeriod], at now: Date) -> GradingPeriod? {
        func minute(_ date: Date) -> Double { (date.timeIntervalSince1970 / 60).rounded(.down) }
        return periods.first { minute($0.startDate) < minute(now) && minute(now) <= minute($0.endDate) }
    }

    // MARK: - gradecalc.py compute_scores

    static func scoreSet(_ input: GradeInput, gradingPeriodID: CanvasID<GradingPeriod>?, ignoreUnposted: Bool) -> ScoreSet {
        let current = groupSums(input, ignoreUngraded: true, ignoreUnposted: ignoreUnposted, gradingPeriodID: gradingPeriodID)
        let final = groupSums(input, ignoreUngraded: false, ignoreUnposted: ignoreUnposted, gradingPeriodID: gradingPeriodID)
        return ScoreSet(currentScore: total(current, input.weighting), finalScore: total(final, input.weighting),
                        currentGroups: current, finalGroups: final)
    }

    // MARK: - gradecalc.py create_group_sums

    private struct Row {
        let assignmentID: CanvasID<Assignment>
        let submissionID: CanvasID<Submission>?
        let hasSubmission: Bool
        let score: Double?
        let total: Double
        let excused: Bool
        let omit: Bool
    }

    static func groupSums(_ input: GradeInput, ignoreUngraded: Bool, ignoreUnposted: Bool,
                          gradingPeriodID: CanvasID<GradingPeriod>?) -> [GroupScore] {
        var byGroup: [CanvasID<AssignmentGroup>: [GradeInput.Item]] = [:]
        for item in input.items where item.isGradeable && item.published {
            if let gradingPeriodID, item.gradingPeriodID != gradingPeriodID { continue }
            byGroup[item.groupID, default: []].append(item)
        }

        return input.groups.map { group in
            var rows = (byGroup[group.id] ?? []).map { item -> Row in
                var submission = item.submission
                // ignore_submission?: with posted scores only, unposted work is absent.
                if ignoreUnposted, submission?.posted == false { submission = nil }
                if ignoreUngraded, submission?.workflowState == "pending_review" { submission = nil }
                // CS-01/CS-03 (crash-safety.md): sanitized again here, not just at the DTO
                // mapping boundary (`GradeSanitizing`'s doc) — `GradeInput` also accepts
                // hand-built values from "what-if" callers (this struct's own doc comment),
                // which never go through a mapper at all.
                return Row(assignmentID: item.id, submissionID: submission?.id, hasSubmission: submission != nil,
                           score: GradeSanitizing.saneScore(submission?.score), total: GradeSanitizing.sanePoints(item.pointsPossible) ?? 0,
                           excused: submission?.excused ?? false, omit: item.omitFromFinalGrade)
            }
            if input.enrollmentCompleted { rows = rows.filter(\.hasSubmission) }
            if ignoreUngraded { rows = rows.filter { $0.score != nil } }
            rows = rows.filter { !$0.excused && !$0.omit }

            let candidates = rows.map {
                DropRuleSelection.Candidate(assignmentID: $0.assignmentID, score: $0.score ?? 0, total: $0.total)
            }
            let kept = DropRuleSelection.keptIndices(candidates, rules: group.rules)
            let keptSet = Set(kept)
            var score = Decimal(0), possible = Decimal(0)
            for i in kept {
                score += RubyNumerics.decimal(candidates[i].score)
                possible += RubyNumerics.decimal(candidates[i].total)
            }
            return GroupScore(
                groupID: group.id, score: score, possible: possible, weight: group.weight,
                grade: possible > 0 ? percent(score, of: possible) : nil,
                droppedSubmissionIDs: rows.indices.filter { !keptSet.contains($0) }.compactMap { rows[$0].submissionID },
                keptAssignmentIDs: kept.map { candidates[$0].assignmentID })
        }
    }

    /// `(score.to_f.to_d / possible * 100).round(2)` in BigDecimal, as a Float.
    private static func percent(_ score: Decimal, of possible: Decimal) -> Double {
        let exactScore = RubyNumerics.decimal(RubyNumerics.double(score))
        return RubyNumerics.double(RubyNumerics.roundHalfUp2(exactScore / possible * 100))
    }

    // MARK: - gradecalc.py total_from_group_sums (calculate_total_from_group_scores)

    static func total(_ groups: [GroupScore], _ weighting: GradeInput.Weighting) -> Double? {
        switch weighting {
        case .percent:
            let relevant = groups.filter { $0.possible != 0 }
            var final = Decimal(0)
            for g in relevant { final += (g.score / g.possible) * RubyNumerics.decimal(GradeSanitizing.saneWeightOrZero(g.weight)) }
            var fullWeight = 0.0
            for g in relevant { fullWeight += g.weight }
            let grade: Decimal
            if fullWeight == 0 { return nil }
            if fullWeight < 100 { grade = final / RubyNumerics.decimal(fullWeight) * 100 } else { grade = final }
            return RubyNumerics.floatRound(RubyNumerics.double(grade), 2)
        case .points:
            var total = Decimal(0), possible = Decimal(0)
            for g in groups { total += g.score; possible += g.possible }
            return possible > 0 ? percent(total, of: possible) : nil
        }
    }

    // MARK: - gradecalc.py combine_weighted_grading_periods

    /// Float arithmetic over the stored, already rounded period scores, in period order.
    static func combineWeightedGradingPeriods(_ rows: [(weight: Double?, current: Double?, final: Double?)])
        -> (current: Double?, final: Double?) {
        var currentWeight = 0.0, currentGrade = 0.0, finalWeight = 0.0, finalGrade = 0.0
        for row in rows {
            let w = row.weight ?? 0.0
            finalWeight += w
            if row.current != nil { currentWeight += w }
            currentGrade += (row.current ?? 0.0) * (w / 100.0)
            finalGrade += (row.final ?? 0.0) * (w / 100.0)
        }
        func scaled(_ grade: Double, _ fullWeight: Double) -> Double {
            guard fullWeight < 100 else { return grade }
            return fullWeight == 0 ? 0.0 : (grade * 100.0) / fullWeight
        }
        let current = scaled(currentGrade, currentWeight)
        let final = scaled(finalGrade, finalWeight)
        let noCurrent = abs(current) < Double.ulpOfOne && rows.allSatisfy { $0.current == nil }
        return (noCurrent ? nil : RubyNumerics.floatRound(current, 2), RubyNumerics.floatRound(final, 2))
    }
}
