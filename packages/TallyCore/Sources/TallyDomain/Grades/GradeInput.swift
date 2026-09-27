import Foundation

/// Everything Canvas's grade calculator reads for one student in one course, as a
/// client sees it: the Swift form of gradecalc.py `course_input_from_api`.
/// Build it from the snapshot with `init(course:groups:gradingPeriods:)`; what-if
/// callers can edit the values before calling `GradeEngine.scores(for:)`.
public struct GradeInput: Sendable, Equatable {
    public enum Weighting: Sendable, Equatable {
        /// Sum of points across all groups.
        case points
        /// `apply_assignment_group_weights`: groups weighted by `group_weight` percent.
        case percent
    }

    public struct Group: Sendable, Equatable {
        public var id: CanvasID<AssignmentGroup>
        public var weight: Double
        public var rules: DropRules
        public init(id: CanvasID<AssignmentGroup>, weight: Double, rules: DropRules = DropRules()) {
            self.id = id; self.weight = weight; self.rules = rules
        }
    }

    /// The student's submission, reduced to what the calculator reads.
    public struct ScoredSubmission: Sendable, Equatable {
        public var id: CanvasID<Submission>?
        public var score: Double?
        public var excused: Bool
        /// `posted_at != nil`.
        public var posted: Bool
        public var workflowState: String
        public init(id: CanvasID<Submission>? = nil, score: Double?, excused: Bool = false, posted: Bool = true,
                    workflowState: String = "graded") {
            self.id = id; self.score = score; self.excused = excused; self.posted = posted; self.workflowState = workflowState
        }
    }

    public struct Item: Sendable, Equatable {
        public var id: CanvasID<Assignment>
        public var groupID: CanvasID<AssignmentGroup>
        public var pointsPossible: Double?
        public var omitFromFinalGrade: Bool
        public var isGradeable: Bool
        public var published: Bool
        /// From the submission's `grading_period_id` (nil without a submission).
        public var gradingPeriodID: CanvasID<GradingPeriod>?
        public var submission: ScoredSubmission?
        public init(id: CanvasID<Assignment>, groupID: CanvasID<AssignmentGroup>, pointsPossible: Double?,
                    omitFromFinalGrade: Bool = false, isGradeable: Bool = true, published: Bool = true,
                    gradingPeriodID: CanvasID<GradingPeriod>? = nil, submission: ScoredSubmission?) {
            self.id = id; self.groupID = groupID; self.pointsPossible = pointsPossible
            self.omitFromFinalGrade = omitFromFinalGrade; self.isGradeable = isGradeable; self.published = published
            self.gradingPeriodID = gradingPeriodID; self.submission = submission
        }
    }

    public struct Period: Sendable, Equatable {
        public var id: CanvasID<GradingPeriod>
        public var weight: Double?
        public init(id: CanvasID<GradingPeriod>, weight: Double?) { self.id = id; self.weight = weight }
    }

    public var weighting: Weighting
    /// In Canvas's order (the assignment_groups response order).
    public var groups: [Group]
    public var items: [Item]
    /// The course's grading periods, in response order; empty when it has none.
    public var periods: [Period]
    /// `has_weighted_grading_periods`; only applies when `periods` is not empty.
    public var hasWeightedGradingPeriods: Bool
    /// Every student enrollment row is `completed`.
    public var enrollmentCompleted: Bool

    public init(weighting: Weighting, groups: [Group], items: [Item], periods: [Period] = [],
                hasWeightedGradingPeriods: Bool = false, enrollmentCompleted: Bool = false) {
        self.weighting = weighting; self.groups = groups; self.items = items; self.periods = periods
        self.hasWeightedGradingPeriods = hasWeightedGradingPeriods; self.enrollmentCompleted = enrollmentCompleted
    }

    /// gradecalc.py `course_input_from_api` over the mapped snapshot.
    public init(course: Course, groups: [AssignmentGroup], gradingPeriods: [GradingPeriod]) {
        self.init(
            weighting: course.appliesGroupWeights ? .percent : .points,
            groups: groups.map { Group(id: $0.id, weight: $0.weight ?? 0, rules: $0.rules) },
            items: groups.flatMap(\.assignments).map { a in
                Item(id: a.id, groupID: a.groupID, pointsPossible: a.pointsPossible,
                     omitFromFinalGrade: a.omitFromFinalGrade, isGradeable: a.isGradeable, published: a.published,
                     gradingPeriodID: a.submission?.gradingPeriodID,
                     submission: a.submission.map { s in
                         ScoredSubmission(id: s.id, score: s.score, excused: s.excused, posted: s.postedAt != nil,
                                          workflowState: s.workflowState)
                     })
            },
            periods: gradingPeriods.map { Period(id: $0.id, weight: $0.weight) },
            hasWeightedGradingPeriods: course.hasWeightedGradingPeriods,
            enrollmentCompleted: course.studentEnrollmentCompleted)
    }
}
