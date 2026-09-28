import Foundation
import Observation
import TallyDomain

/// The what-if sheet's state (ux-ui.md §3.7.3, UX-WP-16). Scores the student types, steps or fills
/// are hypothetical points on ungraded work; the projected grade and the goal answer come from the
/// domain `GradeEngine`/`GoalSeek`, only through `GradeWork`: off the main actor, and each new edit
/// cancels the computation it replaces (a worst-case `GoalSeek` takes 144-268 ms, plan 07/CS-08).
/// Nothing here is written anywhere: Canvas's own What-If API writes to the student's account and
/// "should be used sparingly", so Tally never calls it (ux-ui.md §3.7.3).
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

    private let projection = TaskBox()
    private let goal = TaskBox()
    @ObservationIgnored private var revision: UInt64 = 0
    @ObservationIgnored private var goalRevision: UInt64 = 0
    private let possible: [CanvasID<Assignment>: Double]

    public init(setup: WhatIfSetup) {
        self.setup = setup
        var possible: [CanvasID<Assignment>: Double] = [:]
        for item in setup.groups.flatMap(\.items) { possible[item.id] = item.pointsPossible }
        self.possible = possible
        goalAssignmentID = setup.groups.first?.items.first?.id
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

    /// The toolbar's Reset: every hypothetical score cleared.
    public func reset() {
        guard !scores.isEmpty else { return }
        scores = [:]
        recompute()
        recomputeGoal()
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
        let input = setup.input
        let overrides = overrides
        let needsBaseline = baseline == nil
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
    }

    private func recomputeGoal() {
        goalRevision &+= 1
        let current = goalRevision
        guard let id = goalAssignmentID else {
            goalOutcome = nil
            return
        }
        // Everything else keeps the student's hypothetical scores; the goal item's own is solved for.
        let input = WhatIfSimulator.apply(overrides.filter { $0.assignmentID != id }, to: setup.input)
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
