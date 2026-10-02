import Foundation
import Observation
import TallyDomain
import TallyStrings

/// The what-if sheet's state (ux-ui.md §3.7.3, UX-WP-16). Scores the student types, steps or fills
/// are hypothetical points on ungraded work; the projected grade and the goal answer come from the
/// domain `GradeEngine`/`GoalSeek`, only through `GradeWork`: off the main actor, and each new edit
/// cancels the computation it replaces (a worst-case `GoalSeek` takes 144-268 ms, plan 07/CS-08).
/// Nothing here is written anywhere: Canvas's own What-If API writes to the student's account and
/// "should be used sparingly", so Tally never calls it (ux-ui.md §3.7.3).
///
/// Plan 08 XG-06: for a course whose grades are kept outside Canvas (`setup.estimate`), the scores
/// are the student's real ones (the school's grade portal) and the answer is an estimate; the
/// student may also set each category's weight. Scores and weights alike live in this model only:
/// it has no store, so they are never saved, and they are gone when the sheet closes (the owner's
/// "session-only" decision), because Course Detail drops the model then.
@MainActor
@Observable
public final class WhatIfModel {
    /// Explicit and nonisolated (plan 06 A2; swiftlang/swift#88036).
    nonisolated deinit {}

    /// The quick-fill chips (ux-ui.md §3.7.3: "100 / 90 / 80 / 70%").
    public static let quickFillPercents: [Double] = [100, 90, 80, 70]
    /// The stepper's step, in points.
    public static let stepPoints: Double = 1
    /// Goal mode's default target, a percentage.
    public static let defaultGoalPercent: Double = 90
    /// XG-06: how far above 100 the weights' total may be before the sheet says it is over 100: half
    /// of the last digit the total shows, so a total of defaults that is 100 up to rounding is 100.
    public static let weightTotalTolerance: Double = 0.005

    public let setup: WhatIfSetup
    /// The student's hypothetical points, per assignment.
    public private(set) var scores: [CanvasID<Assignment>: Double] = [:]
    /// The current grade from the engine, the baseline the projection is compared with.
    public private(set) var baseline: Double?
    /// The grade with every hypothetical score applied; the baseline when there are none.
    public private(set) var projected: Double?
    public private(set) var isComputing = false

    public private(set) var goalAssignmentID: CanvasID<Assignment>?
    public private(set) var goalPercent: Double = WhatIfModel.defaultGoalPercent
    public private(set) var goalOutcome: GoalSeek.Result.Outcome?
    /// Whether the first answer has landed: before that a missing grade means "working it out".
    public private(set) var hasSettled = false

    // MARK: XG-06: the categories' weights (an estimate only; session only)

    /// What the student typed in a weight field.
    public nonisolated enum WeightEntry: Equatable, Sendable {
        /// Nothing: the category keeps its default.
        case blank
        case number(Double)
        /// Not a number at all.
        case unreadable
    }

    /// The weights the student set, by category, in percent. Only valid ones
    /// (`OutsideCanvasEstimate.isValidWeight`).
    public private(set) var weights: [CanvasID<AssignmentGroup>: Double] = [:]
    /// Categories whose entry could not be used (not a number, below 0 or above 100). The sheet
    /// says so under the field; the category keeps its default meanwhile, never a clamped value.
    public private(set) var invalidWeights: Set<CanvasID<AssignmentGroup>> = []
    /// What the estimate did with `weights`: `.allZero` keeps Canvas's setting, and the sheet says so.
    public private(set) var weightsOutcome: OutsideCanvasEstimate.WeightsOutcome = .canvasSetting
    /// Every category's weight (set or default) added up, in percent.
    public private(set) var weightTotal: Double = 0
    /// Bumped by `reset()`, so each weight field clears what it shows.
    public private(set) var resetCount = 0
    /// The input every computation runs on: `setup.input`, with the student's weights applied.
    @ObservationIgnored private var input: GradeInput

    private let projection = TaskBox()
    private let goal = TaskBox()
    @ObservationIgnored private var revision: UInt64 = 0
    @ObservationIgnored private var goalRevision: UInt64 = 0
    private let possible: [CanvasID<Assignment>: Double]

    public init(setup: WhatIfSetup) {
        self.setup = setup
        input = setup.input
        var possible: [CanvasID<Assignment>: Double] = [:]
        for item in setup.groups.flatMap(\.items) { possible[item.id] = item.pointsPossible }
        self.possible = possible
        goalAssignmentID = setup.groups.first?.items.first?.id
        if setup.estimate != nil { applyWeights() }
    }

    /// The baseline and the first goal answer (the sheet's `.task`).
    public func start() async {
        recompute()
        recomputeGoal()
        await projection.value()
        await goal.value()
    }

    // MARK: - Editing

    /// Sets (or, with `nil`, clears) the hypothetical points for `id`, kept within 0...points possible.
    public func setScore(_ points: Double?, for id: CanvasID<Assignment>) {
        guard let maximum = possible[id] else { return }
        if let points, points.isFinite {
            scores[id] = min(max(0, points), maximum)
        } else {
            scores[id] = nil
        }
        recompute()
        recomputeGoal()
    }

    /// The stepper (and VoiceOver's adjustable action): one point up or down. An empty field
    /// counts as 0 going up and as the maximum going down.
    public func step(_ id: CanvasID<Assignment>, up: Bool) {
        guard let maximum = possible[id] else { return }
        let current = scores[id] ?? (up ? 0 : maximum)
        setScore(current + (up ? Self.stepPoints : -Self.stepPoints), for: id)
    }

    /// A quick-fill chip: `percent` of the points possible.
    public func fill(_ id: CanvasID<Assignment>, percent: Double) {
        guard let maximum = possible[id] else { return }
        setScore(maximum * percent / 100, for: id)
    }

    /// The toolbar's Reset: every hypothetical score cleared, and every weight back to its default.
    public func reset() {
        guard canReset else { return }
        scores = [:]
        if !weights.isEmpty || !invalidWeights.isEmpty {
            weights = [:]
            invalidWeights = []
            applyWeights()
        }
        resetCount &+= 1
        recompute()
        recomputeGoal()
    }

    /// Whether Reset has anything to clear.
    public var canReset: Bool {
        !scores.isEmpty || !weights.isEmpty || !invalidWeights.isEmpty
    }

    /// XG-06: what the student typed for a category's weight. A valid number (0 to 100) is used; a
    /// blank field goes back to the default; anything else is refused and flagged
    /// (`invalidWeights`), so it is never accepted silently. Only a category of an estimate.
    public func setWeight(_ entry: WeightEntry, for id: CanvasID<AssignmentGroup>) {
        guard let estimate = setup.estimate, estimate.categories.contains(where: { $0.id == id }) else { return }
        var updated = weights
        var invalid = invalidWeights
        switch entry {
        case .blank:
            updated[id] = nil
            invalid.remove(id)
        case .number(let weight) where OutsideCanvasEstimate.isValidWeight(weight):
            updated[id] = weight
            invalid.remove(id)
        case .number, .unreadable:
            updated[id] = nil
            invalid.insert(id)
        }
        if invalid != invalidWeights { invalidWeights = invalid }
        guard updated != weights else { return }
        weights = updated
        applyWeights()
        recompute()
        recomputeGoal()
    }

    /// The weight field's text, read in the student's locale: blank, a number, or unreadable.
    public nonisolated static func weightEntry(_ text: String, locale: Locale) -> WeightEntry {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .blank }
        guard let weight = try? Double(trimmed, format: .number.locale(locale)) else { return .unreadable }
        return .number(weight)
    }

    /// Whether the weights add up to more than 100 (the engine then uses them as given, Canvas's rule).
    public var weightTotalIsOverHundred: Bool {
        weightTotal > OutsideCanvasEstimate.maximumWeight + Self.weightTotalTolerance
    }

    /// The input the estimate runs on (tests: "the estimate equals `GradeWork` over it").
    var estimateInput: GradeInput { input }

    /// Every computation's input from the student's weights (`OutsideCanvasEstimate.applying`).
    private func applyWeights() {
        let (applied, outcome) = OutsideCanvasEstimate.applying(weights, to: setup.input)
        input = applied
        if weightsOutcome != outcome { weightsOutcome = outcome }
        let total = OutsideCanvasEstimate.resolvedWeights(weights, in: setup.input).values.reduce(0, +)
        if weightTotal != total { weightTotal = total }
    }

    public func setGoal(assignment id: CanvasID<Assignment>) {
        guard possible[id] != nil, id != goalAssignmentID else { return }
        goalAssignmentID = id
        recomputeGoal()
    }

    public func setGoal(percent: Double) {
        let clamped = min(max(0, percent), 100)
        guard clamped != goalPercent else { return }
        goalPercent = clamped
        recomputeGoal()
    }

    /// The points possible on one of the sheet's items.
    public func pointsPossible(for id: CanvasID<Assignment>) -> Double? {
        possible[id]
    }

    /// The projected grade minus the baseline, when both exist.
    public var delta: Double? {
        guard let projected, let baseline else { return nil }
        return projected - baseline
    }

    /// The answers have landed and there is no grade to show: an estimate before any score is
    /// typed, or a course with no graded work yet. The summary then says so instead of "working
    /// it out".
    public var hasNoGrade: Bool {
        hasSettled && !isComputing && projected == nil
    }

    /// Waits for the computations in flight (tests).
    func settle() async {
        await projection.value()
        await goal.value()
    }

    // MARK: - Computation (GradeWork only)

    private var overrides: [WhatIfSimulator.Override] {
        scores.sorted { $0.key < $1.key }.map { WhatIfSimulator.Override(assignmentID: $0.key, score: $0.value) }
    }

    private func recompute() {
        revision &+= 1
        let current = revision
        let input = input
        let overrides = overrides
        // An estimate (XG-06) has no baseline: its input holds none of Canvas's scores.
        let needsBaseline = baseline == nil && setup.estimate == nil
        isComputing = true
        projection.replace(with: Task { [weak self] in
            do {
                var base: Double?
                if needsBaseline { base = try await GradeWork.scores(for: input).currentScore }
                var projected: Double?
                if !overrides.isEmpty {
                    projected = try await GradeWork.scores(applying: overrides, to: input).currentScore
                }
                self?.finish(current, baseline: base, projected: projected, hasOverrides: !overrides.isEmpty)
            } catch {
                return // cancelled: a newer edit replaced this computation
            }
        })
    }

    private func finish(_ revision: UInt64, baseline base: Double?, projected: Double?, hasOverrides: Bool) {
        if let base { baseline = base }
        guard revision == self.revision else { return }
        self.projected = hasOverrides ? projected : baseline
        isComputing = false
        if !hasSettled { hasSettled = true }
    }

    private func recomputeGoal() {
        goalRevision &+= 1
        let current = goalRevision
        guard let id = goalAssignmentID else {
            goalOutcome = nil
            return
        }
        // Everything else keeps the student's hypothetical scores; the goal item's own is solved for.
        let input = WhatIfSimulator.apply(overrides.filter { $0.assignmentID != id }, to: input)
        let target = goalPercent
        goal.replace(with: Task { [weak self] in
            do {
                let result = try await GradeWork.goalSeek(assignmentID: id, targetPercent: target, in: input)
                self?.finishGoal(current, outcome: result.outcome)
            } catch {
                return
            }
        })
    }

    private func finishGoal(_ revision: UInt64, outcome: GoalSeek.Result.Outcome) {
        guard revision == goalRevision else { return }
        goalOutcome = outcome
    }
}

/// The what-if summary's words (UX-WP-16): the projected grade, its change, and the one sentence
/// VoiceOver reads for both. Pure, so the spoken form is unit-tested.
public nonisolated enum WhatIfCopy {
    /// "Simulation — not your real grade" (ux-ui.md §3.7.3), shown with the `flask` symbol.
    public static let simulationLabel = "Simulation \u{2014} not your real grade"

    /// "91.4%", or "…" while the first answer is being worked out.
    public static func percent(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ?? "\u{2026}"
    }

    /// XG-06: the summary when there is no grade to show (`WhatIfModel.hasNoGrade`): a dash on
    /// screen, and words for VoiceOver.
    public static let noGradeDash = GradeNotInCanvas.dash
    public static var noGradeSpoken: String { String(localized: L10n.WhatIfEstimate.noEstimate()) }

    /// XG-06: the weights' total as a percentage in `locale` ("100%", "116.67%"); the sign's place
    /// and spacing are the locale's.
    public static func weightTotal(_ total: Double, locale: Locale) -> String {
        total.formatted(.percent.scale(1).precision(.fractionLength(0...2)).locale(locale))
    }

    /// "▲ 1.3" / "▼ 0.4"; nothing when the change rounds to zero.
    public static func change(_ delta: Double?) -> String? {
        guard let delta, abs(delta) >= 0.05 else { return nil }
        return (delta > 0 ? "\u{25B2} " : "\u{25BC} ") + abs(delta).formatted(.number.precision(.fractionLength(1)))
    }

    /// The summary as one sentence: "Projected 91.4 percent, up 1.3 points from your current 90.1
    /// percent", or "…, the same as your current grade".
    public static func spoken(projected: Double?, baseline: Double?) -> String {
        guard let projected else { return "Projected grade: working it out" }
        let value = projected.formatted(.number.precision(.fractionLength(1)))
        guard let baseline else { return "Projected \(value) percent" }
        let delta = projected - baseline
        guard abs(delta) >= 0.05 else { return "Projected \(value) percent, the same as your current grade" }
        let points = abs(delta).formatted(.number.precision(.fractionLength(1)))
        return "Projected \(value) percent, \(delta > 0 ? "up" : "down") \(points) points from your current "
            + "\(baseline.formatted(.number.precision(.fractionLength(1)))) percent"
    }
}
