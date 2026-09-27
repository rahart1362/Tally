import Foundation

/// "What should I do next?" (insights-at-a-glance §5.1). A transparent,
/// testable score combining time-to-due, the item's share of the course
/// grade, an overdue-but-still-accepted bonus, and a course-below-goal (or
/// near-boundary) bonus. `GradeEngine` stays authoritative for the real
/// grade; this score is for ranking only (§5.2).
public enum PriorityScore {
    public enum Band: String, Sendable, Equatable, CaseIterable {
        case high, medium, low
    }

    /// The three boolean modifiers §5.1 folds into `S` and `C`.
    public struct Modifiers: Sendable, Equatable {
        /// `S = 1.15`: the item is overdue and still open (`lock_at` nil or
        /// in the future).
        public var overdueStillOpen: Bool
        /// `C = 1.20`: the course is below the student's goal.
        public var courseBelowGoal: Bool
        /// `C = 1.10`: within `InsightsConfig.priorityBoundaryWindow` points
        /// above a letter boundary or the goal. Ignored when `courseBelowGoal`
        /// is set (§5.1: the two `C` values are mutually exclusive).
        public var nearBoundary: Bool

        public init(overdueStillOpen: Bool = false, courseBelowGoal: Bool = false, nearBoundary: Bool = false) {
            self.overdueStillOpen = overdueStillOpen
            self.courseBelowGoal = courseBelowGoal
            self.nearBoundary = nearBoundary
        }
    }

    // MARK: - The §5.1 formula

    /// `h` = hours until due (negative if overdue), nil for an undated item.
    /// `w` = the item's share of the final course grade, in `0...1` (§5.2).
    ///
    /// ```
    /// U = 1.0 if h <= 0 else exp(-h/τ)
    /// I = min(1, sqrt(w/wRef))
    /// P = min(100, 100 * S * C * (α·U + (1−α)·I))
    /// Undated: P = 100 * 0.5 * (1−α) * I
    /// ```
    /// The score itself is never shown to students (§5.1); only the band and
    /// a reason built from `reasonText`.
    public static func score(hoursUntilDue h: Double?, courseWeight w: Double, modifiers: Modifiers = Modifiers()) -> Double {
        let alpha = InsightsConfig.priorityAlpha
        let importance = min(1, (max(0, w) / InsightsConfig.priorityWeightReference).squareRoot())
        guard let h else {
            return 100 * 0.5 * (1 - alpha) * importance
        }
        let urgency = h <= 0 ? 1.0 : exp(-h / InsightsConfig.priorityUrgencyHalfLifeHours)
        let stillAccepted = modifiers.overdueStillOpen ? InsightsConfig.priorityStillAcceptedBonus : 1.0
        let courseFactor: Double =
            if modifiers.courseBelowGoal { InsightsConfig.priorityBelowGoalBonus }
            else if modifiers.nearBoundary { InsightsConfig.priorityNearBoundaryBonus }
            else { 1.0 }
        return min(100, 100 * stillAccepted * courseFactor * (alpha * urgency + (1 - alpha) * importance))
    }

    public static func band(_ p: Double) -> Band {
        if p >= InsightsConfig.priorityHighThreshold { return .high }
        if p >= InsightsConfig.priorityMediumThreshold { return .medium }
        return .low
    }

    // MARK: - §5.1 exclusion rule

    /// Excluded from "Next up" if submitted, graded, excused, marked done, or
    /// overdue-and-locked (that state becomes alert A2 instead). An item whose
    /// `submission_types` are all `none`/`on_paper` (no digital submission
    /// expected) is included only when it has a due date, as an "attend or
    /// prepare" item.
    public static func isExcluded(assignment: Assignment, markedDone: Bool, now: Date) -> Bool {
        if let submission = assignment.submission {
            if submission.isSubmitted || submission.gradedAt != nil || submission.excused { return true }
        }
        if markedDone { return true }
        if let due = assignment.dueAt, due < now, let lock = assignment.lockAt, lock < now { return true }
        if !assignment.submissionTypes.isEmpty,
           assignment.submissionTypes.allSatisfy({ $0 == "none" || $0 == "on_paper" }),
           assignment.dueAt == nil {
            return true
        }
        return false
    }

    // MARK: - §5.2 grade-weight share

    /// The item's approximate share `w` of the final course grade, `0...1`.
    /// This is **ranking only**, never the grade itself:
    /// - weighted groups: `w = group_weight/100 × pointsPossible / Σ pointsPossible(counted items in group)`
    /// - unweighted: `w = pointsPossible / Σ pointsPossible(counted items in course)`
    /// - drop rules: `w × (1 − k/n)` for `drop_lowest = k` (+ `drop_highest`)
    ///   over a group of `n` droppable (non-`never_drop`) counted items; a
    ///   `never_drop` item is not discounted.
    /// - grading periods: when the course has periods, both sums are
    ///   restricted to items that share the assignment's own effective period
    ///   (found by due-date containment, since `GradeInput`'s
    ///   `gradingPeriodID` is sourced from the submission and this is called
    ///   before any submission may exist). An item that cannot be placed in a
    ///   period (no due date) falls back to the whole group/course.
    /// - `omit_from_final_grade`, unpublished, not gradeable, or
    ///   `pointsPossible` nil/0: `w = 0` (ranking is by urgency only).
    public static func weight(
        assignment: Assignment,
        course: Course,
        groups: [AssignmentGroup],
        gradingPeriods: [GradingPeriod] = []
    ) -> Double {
        guard let possible = assignment.pointsPossible, possible > 0 else { return 0 }
        guard assignment.published, assignment.isGradeable, !assignment.omitFromFinalGrade else { return 0 }
        guard let group = groups.first(where: { $0.id == assignment.groupID }) else { return 0 }

        func counted(_ a: Assignment) -> Bool {
            a.published && a.isGradeable && !a.omitFromFinalGrade && (a.pointsPossible ?? 0) > 0
        }

        let usesPeriods = course.hasGradingPeriods && !gradingPeriods.isEmpty
        let ownPeriod = usesPeriods ? effectivePeriod(for: assignment, in: gradingPeriods) : nil
        func inScope(_ a: Assignment) -> Bool {
            guard usesPeriods, let ownPeriod else { return true }
            return effectivePeriod(for: a, in: gradingPeriods) == ownPeriod
        }

        var w: Double
        if course.appliesGroupWeights {
            let groupPossible = group.assignments.filter { counted($0) && inScope($0) }
                .reduce(0.0) { $0 + ($1.pointsPossible ?? 0) }
            guard groupPossible > 0 else { return 0 }
            w = (group.weight ?? 0) / 100 * possible / groupPossible
        } else {
            let coursePossible = groups.flatMap(\.assignments).filter { counted($0) && inScope($0) }
                .reduce(0.0) { $0 + ($1.pointsPossible ?? 0) }
            guard coursePossible > 0 else { return 0 }
            w = possible / coursePossible
        }

        let rules = group.rules
        if !rules.neverDrop.contains(assignment.id) {
            let droppable = group.assignments.filter { counted($0) && !rules.neverDrop.contains($0.id) }
            let n = droppable.count
            let k = max(0, rules.dropLowest) + max(0, rules.dropHighest)
            if n > 0, k > 0 {
                w *= (1 - min(Double(k), Double(n)) / Double(n))
            }
        }
        return max(0, w)
    }

    /// The grading period an assignment falls in by due-date containment
    /// (`start < due <= end`, minute-truncated like `GradeEngine.currentGradingPeriod`).
    /// nil when undated or when no period contains the due date.
    private static func effectivePeriod(for assignment: Assignment, in periods: [GradingPeriod]) -> CanvasID<GradingPeriod>? {
        guard let due = assignment.dueAt else { return nil }
        func minute(_ d: Date) -> Double { (d.timeIntervalSince1970 / 60).rounded(.down) }
        return periods.first { minute($0.startDate) < minute(due) && minute(due) <= minute($0.endDate) }?.id
    }

    // MARK: - Modifier derivation

    /// `C = 1.20` when the course is below `goal`; `C = 1.10` when the course
    /// is within the boundary window above `goal` or a standard letter cutoff.
    public static func courseModifiers(currentScore: Double?, goal: Double?) -> (belowGoal: Bool, nearBoundary: Bool) {
        guard let currentScore else { return (false, false) }
        if let goal, currentScore < goal { return (true, false) }
        if let goal, currentScore - goal <= InsightsConfig.priorityBoundaryWindow, currentScore >= goal {
            return (false, true)
        }
        for boundary in InsightsConfig.standardLetterBoundaries where currentScore >= boundary {
            if currentScore - boundary <= InsightsConfig.priorityBoundaryWindow { return (false, true) }
            break // boundaries are descending; the first one <= currentScore is the nearest below it
        }
        return (false, false)
    }

    // MARK: - Ranking (§5.1 "Ties")

    /// One item's rank inputs: earlier due date, then higher weight, then
    /// course order, then Canvas ID break ties on equal scores.
    public struct RankedItem: Sendable, Equatable {
        public let assignmentID: CanvasID<Assignment>
        public let score: Double
        public let dueAt: Date?
        public let weight: Double
        public let courseOrder: Int

        public init(assignmentID: CanvasID<Assignment>, score: Double, dueAt: Date?, weight: Double, courseOrder: Int) {
            self.assignmentID = assignmentID
            self.score = score
            self.dueAt = dueAt
            self.weight = weight
            self.courseOrder = courseOrder
        }
    }

    /// Highest score first; deterministic under permutation of the input.
    public static func sorted(_ items: [RankedItem]) -> [RankedItem] {
        items.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            switch (a.dueAt, b.dueAt) {
            case let (da?, db?) where da != db: return da < db
            case (nil, .some): return false
            case (.some, nil): return true
            default: break
            }
            if a.weight != b.weight { return a.weight > b.weight }
            if a.courseOrder != b.courseOrder { return a.courseOrder < b.courseOrder }
            return a.assignmentID < b.assignmentID
        }
    }

    // MARK: - Reason text (§0, §1.2: "reason built from the top two contributing factors")

    public enum Factor: Sendable, Equatable {
        case dueIn(hours: Double)
        case overdue
        case stillAccepted
        case courseWeight(Double)
        case courseBelowGoal
        case nearBoundary
        case noDueDate
    }

    /// The due-date clause always leads (context, not counted as one of the
    /// "top two"); then up to two modifier factors, in priority order
    /// (below-goal / near-boundary, then still-accepted, then course weight).
    public static func reasonFactors(hoursUntilDue: Double?, weight: Double, modifiers: Modifiers) -> [Factor] {
        var lead: Factor
        if let h = hoursUntilDue {
            lead = h <= 0 ? .overdue : .dueIn(hours: h)
        } else {
            lead = .noDueDate
        }
        var rest: [Factor] = []
        if modifiers.courseBelowGoal { rest.append(.courseBelowGoal) }
        else if modifiers.nearBoundary { rest.append(.nearBoundary) }
        if modifiers.overdueStillOpen { rest.append(.stillAccepted) }
        if weight >= InsightsConfig.priorityReasonWeightFloor { rest.append(.courseWeight(weight)) }
        return [lead] + Array(rest.prefix(2))
    }

    public static func reasonText(hoursUntilDue: Double?, weight: Double, modifiers: Modifiers, courseCode: String) -> String {
        reasonFactors(hoursUntilDue: hoursUntilDue, weight: weight, modifiers: modifiers)
            .map { describe($0, courseCode: courseCode) }
            .joined(separator: " · ")
    }

    private static func describe(_ factor: Factor, courseCode: String) -> String {
        switch factor {
        case .dueIn(let h):
            if h < 1 { return "Due in \(max(1, Int((h * 60).rounded())))m" }
            return "Due in \(Int(h.rounded()))h"
        case .overdue: return "Overdue"
        case .stillAccepted: return "Still accepted"
        case .courseWeight(let w): return "~\(Int((w * 100).rounded()))% of \(courseCode)"
        case .courseBelowGoal: return "course below your goal"
        case .nearBoundary: return "near a grade boundary"
        case .noDueDate: return "No due date"
        }
    }
}
