import Foundation

extension PriorityScore {
    /// PERF-05 PA-2 (docs/pmo/reviews/perf-algorithms.md): everything
    /// `weight(assignment:course:groups:gradingPeriods:)` reads from one course, computed once.
    ///
    /// `weight` on its own re-filters the item's whole group (weighted courses) or whole course
    /// (unweighted) and, in a course with grading periods, recomputes every one of those items'
    /// effective period — O(n·p) per call, so weighing all n items of a course was O(n²·p). This
    /// context walks the course once, in O(n·p): each counted assignment's effective period is
    /// computed exactly once and folded into the per-group and per-course counted-points sums for
    /// that period (plus an all-periods sum), and each group's droppable count is taken once.
    /// `weight(of:)` is then O(p) per item, with no per-item allocation.
    ///
    /// Results are bit-identical to the per-call derivation: every sum is accumulated from `0.0`
    /// in the same order the original `filter`/`reduce` visited its items (groups in order,
    /// assignments in order within each group), and floating-point addition is not associative,
    /// so a different order could change the last bit and flip a ranking tie. `PriorityWeightDifferentialTests`
    /// holds this to `==` (and to the same bit pattern) against the original implementation.
    ///
    /// Build one per course and reuse it for every item in that course (as `DashboardBuilder`
    /// does); for a single lookup, `weight(assignment:course:groups:gradingPeriods:)` is fine.
    public struct WeightContext: Sendable {
        /// Counted-points sums for one scope (a group, or the whole course).
        struct Sums: Sendable {
            /// Every counted item: the scope when the course uses no grading periods, or when the
            /// assignment being weighed has no effective period of its own.
            var all = 0.0
            /// Counted items per effective period, indexed by `WeightContext.periodKey`.
            var byPeriod: [Double]

            init(periodCount: Int) { byPeriod = Array(repeating: 0.0, count: periodCount) }

            mutating func add(_ points: Double, periodKey: Int?) {
                all += points
                if let periodKey { byPeriod[periodKey] += points }
            }

            func total(periodKey: Int?) -> Double {
                guard let periodKey else { return all }
                return byPeriod[periodKey]
            }
        }

        struct Group: Sendable {
            let weight: Double?
            let rules: DropRules
            /// `rules.neverDrop` as a set: the same membership as the array's `contains`.
            let neverDrop: Set<CanvasID<Assignment>>
            /// Counted items not in `never_drop`, over the whole group (period-independent,
            /// exactly as `weight` counts them).
            let droppableCount: Int
            let possible: Sums
        }

        /// A grading period's bounds, minute-truncated once instead of once per comparison.
        struct PeriodBounds: Sendable {
            let startMinute: Double
            let endMinute: Double
            /// Index of the first period with this period's ID: two periods that share an ID
            /// are one scope, because `weight` compares periods by ID.
            let key: Int
        }

        private let appliesGroupWeights: Bool
        /// Empty unless the course has grading periods and some were supplied, which is
        /// exactly when `weight` scopes its sums by period.
        private let periods: [PeriodBounds]
        /// The first group with each ID, matching `groups.first(where:)`.
        private let groupIndex: [CanvasID<AssignmentGroup>: Int]
        private let groups: [Group]
        private let coursePossible: Sums

        public init(course: Course, groups: [AssignmentGroup], gradingPeriods: [GradingPeriod] = []) {
            appliesGroupWeights = course.appliesGroupWeights
            let usesPeriods = course.hasGradingPeriods && !gradingPeriods.isEmpty
            var firstIndexOfPeriodID: [CanvasID<GradingPeriod>: Int] = [:]
            var bounds: [PeriodBounds] = []
            if usesPeriods {
                for (index, period) in gradingPeriods.enumerated() {
                    if firstIndexOfPeriodID[period.id] == nil { firstIndexOfPeriodID[period.id] = index }
                    bounds.append(PeriodBounds(startMinute: Self.minute(period.startDate), endMinute: Self.minute(period.endDate),
                                               key: firstIndexOfPeriodID[period.id] ?? index))
                }
            }
            periods = bounds

            var groupIndex: [CanvasID<AssignmentGroup>: Int] = [:]
            var built: [Group] = []
            built.reserveCapacity(groups.count)
            var courseSums = Sums(periodCount: bounds.count)
            for (index, group) in groups.enumerated() {
                if groupIndex[group.id] == nil { groupIndex[group.id] = index }
                let neverDrop = Set(group.rules.neverDrop)
                var possible = Sums(periodCount: bounds.count)
                var droppable = 0
                for assignment in group.assignments where Self.isCounted(assignment) {
                    let points = assignment.pointsPossible ?? 0
                    let key = Self.periodKey(dueAt: assignment.dueAt, in: bounds)
                    possible.add(points, periodKey: key)
                    courseSums.add(points, periodKey: key)
                    if !neverDrop.contains(assignment.id) { droppable += 1 }
                }
                built.append(Group(weight: group.weight, rules: group.rules, neverDrop: neverDrop,
                                   droppableCount: droppable, possible: possible))
            }
            self.groupIndex = groupIndex
            self.groups = built
            coursePossible = courseSums
        }

        /// `PriorityScore.weight`'s §5.2 share for `assignment`, from this course's
        /// precomputed sums. See `weight(assignment:course:groups:gradingPeriods:)` for the rules.
        public func weight(of assignment: Assignment) -> Double {
            guard let possible = assignment.pointsPossible, possible > 0 else { return 0 }
            guard assignment.published, assignment.isGradeable, !assignment.omitFromFinalGrade else { return 0 }
            guard let index = groupIndex[assignment.groupID] else { return 0 }
            let group = groups[index]
            let ownPeriod = Self.periodKey(dueAt: assignment.dueAt, in: periods)

            var w: Double
            if appliesGroupWeights {
                let groupPossible = group.possible.total(periodKey: ownPeriod)
                guard groupPossible > 0 else { return 0 }
                w = (group.weight ?? 0) / 100 * possible / groupPossible
            } else {
                let coursePossible = self.coursePossible.total(periodKey: ownPeriod)
                guard coursePossible > 0 else { return 0 }
                w = possible / coursePossible
            }

            let rules = group.rules
            if !group.neverDrop.contains(assignment.id) {
                let n = group.droppableCount
                // CS-07: both counts are raw Canvas integers, and `+` overflowed (and trapped)
                // past Int.max. Saturating leaves the only use below, `min(k, n)`, unchanged.
                let (sum, overflowed) = max(0, rules.dropLowest).addingReportingOverflow(max(0, rules.dropHighest))
                let k = overflowed ? Int.max : sum
                if n > 0, k > 0 {
                    w *= (1 - min(Double(k), Double(n)) / Double(n))
                }
            }
            return max(0, w)
        }

        /// `weight`'s `counted`: published, gradeable, not omitted, and worth points.
        static func isCounted(_ a: Assignment) -> Bool {
            a.published && a.isGradeable && !a.omitFromFinalGrade && (a.pointsPossible ?? 0) > 0
        }

        /// The grading period an assignment falls in by due-date containment
        /// (`start < due <= end`, minute-truncated like `GradeEngine.currentGradingPeriod`),
        /// as that period's scope key. nil when undated, when no period contains the due date,
        /// or when the course does not scope by period (`periods` empty).
        static func periodKey(dueAt: Date?, in periods: [PeriodBounds]) -> Int? {
            guard let due = dueAt, !periods.isEmpty else { return nil }
            let dueMinute = minute(due)
            return periods.first { $0.startMinute < dueMinute && dueMinute <= $0.endMinute }?.key
        }

        static func minute(_ d: Date) -> Double { (d.timeIntervalSince1970 / 60).rounded(.down) }
    }
}
