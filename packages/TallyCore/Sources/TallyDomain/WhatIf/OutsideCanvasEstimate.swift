import Foundation

/// Plan 08 XG-06 (owner decision, 2026-10-01): the what-if for a course whose grades are kept
/// outside Canvas (`GradeAvailability.keptOutsideCanvas`). The student types their real scores,
/// for example from the school's grade portal, and sees an estimated course grade over the
/// course's Canvas categories, whose weights they may set.
///
/// This type only prepares the engine's input; the grade itself is `GradeEngine`'s, through
/// `WhatIfSimulator` (no new grade math). Pure and nonisolated. Nothing here is stored: the
/// student's scores and weights live in the what-if sheet for the session only.
public nonisolated enum OutsideCanvasEstimate {
    /// The largest weight one category may have, in percent: a category cannot count for more
    /// than the whole grade. Weights still need not add up to 100: the engine applies Canvas's
    /// own rule (a total under 100 is scaled up; one over 100 is used as given, as Canvas does for
    /// extra credit), and the sheet shows the total, with a note when it is over 100.
    public static let maximumWeight: Double = 100

    /// The input the estimate starts from: the course's categories (with their drop rules) and
    /// its assignments, with every Canvas submission removed, so only the scores the student
    /// types count. Canvas holds no grades for such a course, or (with the student's "Yes"
    /// override) grades the student says are not the real ones, and the estimate must never show
    /// a grade Tally hides everywhere else. Grading periods are left out: the estimate is over
    /// the whole course, by category, which is what the disclaimer tells the student.
    public static func estimateInput(from input: GradeInput) -> GradeInput {
        var estimate = input
        estimate.items = input.items.map { item in
            var item = item
            item.submission = nil
            return item
        }
        estimate.periods = []
        estimate.hasWeightedGradingPeriods = false
        return estimate
    }

    /// An item the student can score and the engine counts: published, gradeable, not omitted
    /// from the final grade, and worth points. (Course Detail's `counts` applies the same rule to
    /// the assignments the sheet lists.)
    static func counts(_ item: GradeInput.Item) -> Bool {
        item.published && item.isGradeable && !item.omitFromFinalGrade
            && (GradeSanitizing.sanePoints(item.pointsPossible) ?? 0) > 0
    }

    /// The categories the student can weigh: every group with at least one item that counts, in
    /// Canvas's order.
    public static func weighableGroups(in input: GradeInput) -> [CanvasID<AssignmentGroup>] {
        let counted = Set(input.items.filter(counts).map(\.groupID))
        var seen = Set<CanvasID<AssignmentGroup>>()
        return input.groups.map(\.id).filter { counted.contains($0) && seen.insert($0).inserted }
    }

    /// Each weighable category's weight when the student has not set one, in percent: **the one
    /// place this default is decided** (the PMO's reading of the owner's "universal default";
    /// the owner may change it). A course whose Canvas groups are weighted
    /// (`appliesGroupWeights`, `.percent`) uses those weights. Otherwise Canvas counts each
    /// assignment by its points, and a category's default is its share of the points possible:
    /// used only once the student sets another category's weight, since with no weight set the
    /// estimate keeps Canvas's points rule exactly (`applying`).
    public static func defaultWeights(for input: GradeInput) -> [CanvasID<AssignmentGroup>: Double] {
        let groups = weighableGroups(in: input)
        switch input.weighting {
        case .percent:
            var byGroup: [CanvasID<AssignmentGroup>: Double] = [:]
            for group in input.groups where byGroup[group.id] == nil {
                byGroup[group.id] = GradeSanitizing.saneWeightOrZero(group.weight)
            }
            return Dictionary(groups.map { ($0, max(0, byGroup[$0] ?? 0)) }, uniquingKeysWith: { first, _ in first })
        case .points:
            var points: [CanvasID<AssignmentGroup>: Double] = [:]
            var seenItems = Set<CanvasID<Assignment>>()
            for item in input.items where counts(item) && seenItems.insert(item.id).inserted {
                points[item.groupID, default: 0] += GradeSanitizing.sanePoints(item.pointsPossible) ?? 0
            }
            let total = groups.reduce(0) { $0 + (points[$1] ?? 0) }
            guard total > 0, total.isFinite else { return Dictionary(groups.map { ($0, 0) }, uniquingKeysWith: { first, _ in first }) }
            return Dictionary(groups.map { ($0, (points[$0] ?? 0) / total * 100) }, uniquingKeysWith: { first, _ in first })
        }
    }

    /// Whether `weight` is one the student may set: a finite number from 0 to `maximumWeight`.
    /// NaN, infinities and negative weights are refused (never silently clamped), and so is a
    /// weight above the whole grade.
    public static func isValidWeight(_ weight: Double) -> Bool {
        (0...maximumWeight).contains(weight) // NaN and the infinities are outside every range
    }

    /// What `applying` did with the student's weights.
    public nonisolated enum WeightsOutcome: Equatable, Sendable {
        /// No weight set: Canvas's own rule (the group weights, or points).
        case canvasSetting
        /// The student's weights, with the default for each category they left blank.
        case custom
        /// Every weighable category would weigh 0, which leaves no grade to estimate: the
        /// weights are not applied, Canvas's own rule is, and the sheet says so.
        case allZero
    }

    /// The student's usable entries: those for a weighable category with a valid weight
    /// (`isValidWeight`). The sheet refuses invalid ones before they get here.
    static func usableWeights(_ weights: [CanvasID<AssignmentGroup>: Double],
                              in input: GradeInput) -> [CanvasID<AssignmentGroup>: Double] {
        let groups = Set(weighableGroups(in: input))
        return weights.filter { groups.contains($0.key) && isValidWeight($0.value) }
    }

    /// Every weighable category's weight, in percent: the student's where they set a usable one,
    /// otherwise the default (`defaultWeights`). The sheet shows their total.
    public static func resolvedWeights(_ weights: [CanvasID<AssignmentGroup>: Double],
                                       in input: GradeInput) -> [CanvasID<AssignmentGroup>: Double] {
        let set = usableWeights(weights, in: input)
        let defaults = defaultWeights(for: input)
        return Dictionary(weighableGroups(in: input).map { ($0, set[$0] ?? defaults[$0] ?? 0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The estimate's input with the student's `weights` (percent, by category); entries that are
    /// not usable are ignored. With no usable weight: `input` unchanged (`.canvasSetting`).
    /// Otherwise the input weighs categories by percent (`.percent`), each weighable category at
    /// its `resolvedWeights` value; other categories keep theirs (they have nothing to count).
    /// If every weighable category would weigh 0: `input` unchanged (`.allZero`).
    public static func applying(_ weights: [CanvasID<AssignmentGroup>: Double],
                                to input: GradeInput) -> (input: GradeInput, outcome: WeightsOutcome) {
        guard !usableWeights(weights, in: input).isEmpty else { return (input, .canvasSetting) }
        let resolved = resolvedWeights(weights, in: input)
        guard resolved.values.contains(where: { $0 > 0 }) else { return (input, .allZero) }
        var weighted = input
        weighted.weighting = .percent
        weighted.groups = input.groups.map { group in
            guard let weight = resolved[group.id] else { return group }
            var group = group
            group.weight = weight
            return group
        }
        return (weighted, .custom)
    }
}
