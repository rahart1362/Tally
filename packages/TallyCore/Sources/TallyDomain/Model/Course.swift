import Foundation

public struct Term: Codable, Sendable, Equatable {
    public let id: CanvasID<Term>
    public let name: String
    public let startAt: Date?
    public let endAt: Date?
    public init(id: CanvasID<Term>, name: String, startAt: Date?, endAt: Date?) {
        self.id = id; self.name = name; self.startAt = startAt; self.endAt = endAt
    }
}

public struct Teacher: Codable, Sendable, Equatable {
    public let id: CanvasID<Teacher>
    public let displayName: String
    public init(id: CanvasID<Teacher>, displayName: String) { self.id = id; self.displayName = displayName }
}

/// Canvas's own computed scores for one grading scope (whole course or current period).
public struct ComputedScores: Codable, Sendable, Equatable {
    /// Graded work only (`computed_current_score`).
    public let currentScore: Double?
    /// Ungraded work counts as zero (`computed_final_score`).
    public let finalScore: Double?
    public let currentGrade: String?
    public let finalGrade: String?
    public init(currentScore: Double?, finalScore: Double?, currentGrade: String?, finalGrade: String?) {
        self.currentScore = currentScore; self.finalScore = finalScore
        self.currentGrade = currentGrade; self.finalGrade = finalGrade
    }
}

/// Whether the course lets the student see totals. Tally never shows "0%" for a hidden grade.
public enum GradeVisibility: String, Codable, Sendable {
    case visible
    /// `hide_final_grades`: totals are withheld by the teacher.
    case hiddenTotals
    /// `restrict_quantitative_data`: only letter grades may be shown.
    case lettersOnly
}

public struct Course: Codable, Sendable, Equatable, Identifiable {
    public let id: CanvasID<Course>
    public let name: String
    public let courseCode: String
    public let term: Term?
    public let teachers: [Teacher]
    public let timeZone: String?
    public let appliesGroupWeights: Bool
    public let hasGradingPeriods: Bool
    public let currentGradingPeriodID: CanvasID<GradingPeriod>?
    public let gradeVisibility: GradeVisibility
    /// The student's own enrollment scores; nil when Canvas returned none.
    public let scores: ComputedScores?
    public let currentPeriodScores: ComputedScores?
    public let htmlURL: URL?
    /// The course total is the weighted mean of the grading-period scores.
    public let hasWeightedGradingPeriods: Bool
    /// Every student enrollment row is `completed` (concluded course): Canvas then
    /// grades only assignments that have a visible submission.
    public let studentEnrollmentCompleted: Bool

    public init(id: CanvasID<Course>, name: String, courseCode: String, term: Term?, teachers: [Teacher],
                timeZone: String?, appliesGroupWeights: Bool, hasGradingPeriods: Bool,
                currentGradingPeriodID: CanvasID<GradingPeriod>?, gradeVisibility: GradeVisibility,
                scores: ComputedScores?, currentPeriodScores: ComputedScores?, htmlURL: URL?,
                hasWeightedGradingPeriods: Bool = false, studentEnrollmentCompleted: Bool = false) {
        self.id = id; self.name = name; self.courseCode = courseCode; self.term = term; self.teachers = teachers
        self.timeZone = timeZone; self.appliesGroupWeights = appliesGroupWeights
        self.hasGradingPeriods = hasGradingPeriods; self.currentGradingPeriodID = currentGradingPeriodID
        self.gradeVisibility = gradeVisibility; self.scores = scores
        self.currentPeriodScores = currentPeriodScores; self.htmlURL = htmlURL
        self.hasWeightedGradingPeriods = hasWeightedGradingPeriods
        self.studentEnrollmentCompleted = studentEnrollmentCompleted
    }
}
