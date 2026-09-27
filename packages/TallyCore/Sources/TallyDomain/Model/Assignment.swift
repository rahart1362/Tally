import Foundation

public enum GradingType: String, Codable, Sendable {
    case points, percent, letterGrade = "letter_grade", gpaScale = "gpa_scale"
    case passFail = "pass_fail", notGraded = "not_graded"
}

/// The student's submission, reduced to what grading and alerts need.
public struct Submission: Codable, Sendable, Equatable {
    public let score: Double?
    public let grade: String?
    public let submittedAt: Date?
    public let gradedAt: Date?
    /// nil = not yet posted to the student: excluded from displayed grades.
    public let postedAt: Date?
    public let excused: Bool
    public let missing: Bool
    public let late: Bool
    public let workflowState: String
    /// Reported in the grade engine's dropped-submission lists.
    public let id: CanvasID<Submission>?
    /// The period Canvas files this submission under; grading-period scores filter on it.
    public let gradingPeriodID: CanvasID<GradingPeriod>?

    public init(score: Double?, grade: String?, submittedAt: Date?, gradedAt: Date?, postedAt: Date?,
                excused: Bool, missing: Bool, late: Bool, workflowState: String,
                id: CanvasID<Submission>? = nil, gradingPeriodID: CanvasID<GradingPeriod>? = nil) {
        self.score = score; self.grade = grade; self.submittedAt = submittedAt; self.gradedAt = gradedAt
        self.postedAt = postedAt; self.excused = excused; self.missing = missing; self.late = late
        self.workflowState = workflowState; self.id = id; self.gradingPeriodID = gradingPeriodID
    }

    public var isSubmitted: Bool { submittedAt != nil }
}

public struct Assignment: Codable, Sendable, Equatable, Identifiable {
    public let id: CanvasID<Assignment>
    public let courseID: CanvasID<Course>
    public let groupID: CanvasID<AssignmentGroup>
    public let name: String
    public let dueAt: Date?
    public let lockAt: Date?
    public let pointsPossible: Double?
    public let gradingType: GradingType
    public let omitFromFinalGrade: Bool
    public let htmlURL: URL?
    public let submission: Submission?
    /// Unpublished assignments never count (Canvas omits them for students; defaults to true).
    public let published: Bool
    /// Canvas `submission_types`, e.g. `online_upload`, `not_graded`, `wiki_page`.
    public let submissionTypes: [String]

    public init(id: CanvasID<Assignment>, courseID: CanvasID<Course>, groupID: CanvasID<AssignmentGroup>, name: String,
                dueAt: Date?, lockAt: Date?, pointsPossible: Double?, gradingType: GradingType,
                omitFromFinalGrade: Bool, htmlURL: URL?, submission: Submission?,
                published: Bool = true, submissionTypes: [String] = []) {
        self.id = id; self.courseID = courseID; self.groupID = groupID; self.name = name; self.dueAt = dueAt
        self.lockAt = lockAt; self.pointsPossible = pointsPossible; self.gradingType = gradingType
        self.omitFromFinalGrade = omitFromFinalGrade; self.htmlURL = htmlURL; self.submission = submission
        self.published = published; self.submissionTypes = submissionTypes
    }

    /// Canvas's `gradeable` scope: `not_graded` and `wiki_page` items never enter a grade.
    public var isGradeable: Bool { !submissionTypes.contains("not_graded") && !submissionTypes.contains("wiki_page") }
}

public struct DropRules: Codable, Sendable, Equatable {
    public let dropLowest: Int
    public let dropHighest: Int
    public let neverDrop: [CanvasID<Assignment>]
    public init(dropLowest: Int = 0, dropHighest: Int = 0, neverDrop: [CanvasID<Assignment>] = []) {
        self.dropLowest = dropLowest; self.dropHighest = dropHighest; self.neverDrop = neverDrop
    }
}

public struct AssignmentGroup: Codable, Sendable, Equatable, Identifiable {
    public let id: CanvasID<AssignmentGroup>
    public let name: String
    public let position: Int
    /// Percent of the course grade when the course applies group weights.
    public let weight: Double?
    public let rules: DropRules
    public let assignments: [Assignment]

    public init(id: CanvasID<AssignmentGroup>, name: String, position: Int, weight: Double?, rules: DropRules, assignments: [Assignment]) {
        self.id = id; self.name = name; self.position = position; self.weight = weight
        self.rules = rules; self.assignments = assignments
    }
}

public struct GradingPeriod: Codable, Sendable, Equatable, Identifiable {
    public let id: CanvasID<GradingPeriod>
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let closeDate: Date?
    public let weight: Double?
    public let isClosed: Bool

    public init(id: CanvasID<GradingPeriod>, title: String, startDate: Date, endDate: Date,
                closeDate: Date?, weight: Double?, isClosed: Bool) {
        self.id = id; self.title = title; self.startDate = startDate; self.endDate = endDate
        self.closeDate = closeDate; self.weight = weight; self.isClosed = isClosed
    }
}
