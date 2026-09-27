import Foundation
import TallyCanvasAPI
import TallyDomain

/// One course exactly as the client receives it (courses, assignment_groups and,
/// when present, grading_periods responses), mapped by the production mappers.
public struct GradeFixtureCourse: Sendable {
    public let label: String
    public let course: Course
    public let groups: [AssignmentGroup]
    public let gradingPeriods: [GradingPeriod]
    /// Items the mappers could not map; the parity test requires 0.
    public let unmapped: Int
}

/// `expected/grades/<persona>.json` and each entry of `expected/grades/scenarios.json`.
public struct ExpectedCourseGrades: Decodable, Sendable {
    public struct Branch: Decodable, Sendable {
        public let score: Double
        public let possible: Double
        public let grade: Double?
        public let droppedSubmissionIds: [String]
    }
    public struct Group: Decodable, Sendable {
        public let id: String
        public let current: Branch
        public let final: Branch
    }
    public struct Period: Decodable, Sendable {
        public let id: String
        public let weight: Double?
        public let currentScore: Double?
        public let finalScore: Double?
    }
    public let courseId: String
    public let weightedGradingPeriods: Bool
    public let currentScore: Double?
    public let finalScore: Double?
    public let unpostedCurrentScore: Double?
    public let unpostedFinalScore: Double?
    public let currentGradingPeriodId: String?
    public let gradingPeriods: [Period]
    public let assignmentGroups: [Group]
}

public struct ExpectedGrades: Decodable, Sendable {
    public let tolerance: Double
    public let capturedAt: Date
    public let courses: [ExpectedCourseGrades]
}

public struct ExpectedScenarioGrades: Decodable, Sendable {
    public let tolerance: Double
    public let capturedAt: Date
    public let scenarios: [String: ExpectedCourseGrades]
}

public struct FixtureError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

public enum GradeFixtures {
    private static let host = "canvas.fixtures.example"

    private static func decoder() -> JSONDecoder {
        let decoder = CanvasJSON.decoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    public static func expected(persona: String) throws -> ExpectedGrades {
        try decoder().decode(ExpectedGrades.self, from: Fixtures.data("expected/grades/\(persona).json"))
    }

    public static func expectedScenarios() throws -> ExpectedScenarioGrades {
        try decoder().decode(ExpectedScenarioGrades.self, from: Fixtures.data("expected/grades/scenarios.json"))
    }

    /// Every course in `personas/<persona>/courses.json` with its per-course responses.
    public static func courses(persona: String) throws -> [GradeFixtureCourse] {
        let mapped = try CourseMapper.map(Fixtures.data("personas/\(persona)/courses.json"), host: host)
        return try mapped.items.map { course in
            try load(label: "\(persona)/\(course.id)", course: course, unmapped: mapped.dropped,
                     groups: "personas/\(persona)/assignment_groups/\(course.id).json",
                     periods: "personas/\(persona)/grading_periods/\(course.id).json")
        }
    }

    /// The grade scenario `name` (scenarios/{courses,assignment_groups,grading_periods}/<name>.json).
    public static func scenario(_ name: String) throws -> GradeFixtureCourse {
        let mapped = try CourseMapper.map(Fixtures.data("scenarios/courses/\(name).json"), host: host)
        guard mapped.items.count == 1 else { throw FixtureError(message: "scenario \(name): expected one course") }
        return try load(label: "scenario/\(name)", course: mapped.items[0], unmapped: mapped.dropped,
                        groups: "scenarios/assignment_groups/\(name).json",
                        periods: "scenarios/grading_periods/\(name).json")
    }

    private static func load(label: String, course: Course, unmapped: Int, groups: String, periods: String) throws
        -> GradeFixtureCourse {
        let mappedGroups = try AssignmentGroupMapper.map(Fixtures.data(groups), courseID: course.id)
        // Grading periods are only requested for courses that have them (architecture 3.3 row 4).
        let periodsURL = Fixtures.root().appendingPathComponent(periods)
        let mappedPeriods = FileManager.default.fileExists(atPath: periodsURL.path)
            ? try GradingPeriodMapper.map(Data(contentsOf: periodsURL)) : nil
        return GradeFixtureCourse(label: label, course: course, groups: mappedGroups.items,
                                  gradingPeriods: mappedPeriods?.items ?? [],
                                  unmapped: unmapped + mappedGroups.dropped + (mappedPeriods?.dropped ?? 0))
    }
}
