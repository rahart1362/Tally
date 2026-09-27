import Foundation
import TallyDomain

/// `GET /api/v1/courses?include[]=total_scores&include[]=current_grading_period_scores&include[]=term&include[]=teachers`.
/// Every field except `id` is optional because Canvas omits fields by permission.
struct CourseDTO: Decodable {
    struct TermDTO: Decodable { let id: String; let name: String?; let startAt: Date?; let endAt: Date? }
    struct TeacherDTO: Decodable { let id: String; let displayName: String? }
    struct EnrollmentDTO: Decodable {
        let type: String?
        let computedCurrentScore: Double?, computedFinalScore: Double?
        let computedCurrentGrade: String?, computedFinalGrade: String?
        let currentGradingPeriodId: String?
        let currentPeriodComputedCurrentScore: Double?, currentPeriodComputedFinalScore: Double?
        let currentPeriodComputedCurrentGrade: String?, currentPeriodComputedFinalGrade: String?
    }
    let id: String
    let name: String?
    let courseCode: String?
    let term: TermDTO?
    let teachers: [TeacherDTO]?
    let timeZone: String?
    let applyAssignmentGroupWeights: Bool?
    let hasGradingPeriods: Bool?
    let hideFinalGrades: Bool?
    let restrictQuantitativeData: Bool?
    let accessRestrictedByDate: Bool?
    let enrollments: [EnrollmentDTO]?
}

/// Items that could not be mapped are dropped and counted, never fatal (architecture §3.3).
public struct Mapped<Item: Sendable>: Sendable {
    public let items: [Item]
    public let dropped: Int
}

public enum CourseMapper {
    public static func map(_ data: Data, host: String) throws -> Mapped<Course> {
        let decoder = CanvasJSON.decoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dtos = try decoder.decode([CourseDTO].self, from: data)
        let courses = dtos.compactMap { course(from: $0, host: host) }
        return Mapped(items: courses, dropped: dtos.count - courses.count)
    }

    static func course(from dto: CourseDTO, host: String) -> Course? {
        guard dto.accessRestrictedByDate != true, let name = dto.name else { return nil }
        let student = dto.enrollments?.first { $0.type == "student" && $0.computedCurrentScore != nil }
            ?? dto.enrollments?.first { $0.type == "student" }
        let visibility: GradeVisibility = dto.hideFinalGrades == true ? .hiddenTotals
            : dto.restrictQuantitativeData == true ? .lettersOnly : .visible
        return Course(
            id: CanvasID(dto.id), name: name, courseCode: dto.courseCode ?? name,
            term: dto.term.map { Term(id: CanvasID($0.id), name: $0.name ?? "", startAt: $0.startAt, endAt: $0.endAt) },
            teachers: (dto.teachers ?? []).map { Teacher(id: CanvasID($0.id), displayName: $0.displayName ?? "") },
            timeZone: dto.timeZone,
            appliesGroupWeights: dto.applyAssignmentGroupWeights ?? false,
            hasGradingPeriods: dto.hasGradingPeriods ?? false,
            currentGradingPeriodID: student?.currentGradingPeriodId.map { CanvasID($0) },
            gradeVisibility: visibility,
            scores: student.map { ComputedScores(currentScore: $0.computedCurrentScore, finalScore: $0.computedFinalScore,
                                                 currentGrade: $0.computedCurrentGrade, finalGrade: $0.computedFinalGrade) },
            currentPeriodScores: student.flatMap { e in
                e.currentGradingPeriodId == nil ? nil
                    : ComputedScores(currentScore: e.currentPeriodComputedCurrentScore, finalScore: e.currentPeriodComputedFinalScore,
                                     currentGrade: e.currentPeriodComputedCurrentGrade, finalGrade: e.currentPeriodComputedFinalGrade)
            },
            htmlURL: URL(string: "https://\(host)/courses/\(dto.id)"))
    }
}
