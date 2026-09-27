import Foundation
import TallyDomain

/// `GET /api/v1/courses/:id/assignment_groups?include[]=assignments&include[]=submission`.
struct AssignmentGroupDTO: Decodable {
    struct RulesDTO: Decodable { let dropLowest: Int?; let dropHighest: Int?; let neverDrop: [String]? }
    struct SubmissionDTO: Decodable {
        let id: String?
        let score: Double?, grade: String?
        let submittedAt: Date?, gradedAt: Date?, postedAt: Date?
        let excused: Bool?, missing: Bool?, late: Bool?
        let workflowState: String?
        let gradingPeriodId: String?
    }
    struct AssignmentDTO: Decodable {
        let id: String
        let name: String?
        let courseId: String?
        let dueAt: Date?, lockAt: Date?
        let pointsPossible: Double?
        let gradingType: String?
        let omitFromFinalGrade: Bool?
        let htmlUrl: URL?
        let submission: SubmissionDTO?
        let published: Bool?
        let submissionTypes: [String]?
    }
    let id: String
    let name: String?
    let position: Int?
    let groupWeight: Double?
    let rules: RulesDTO?
    let assignments: [AssignmentDTO]?
}

public enum AssignmentGroupMapper {
    public static func map(_ data: Data, courseID: CanvasID<Course>) throws -> Mapped<AssignmentGroup> {
        let decoder = CanvasJSON.decoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dtos = try decoder.decode([AssignmentGroupDTO].self, from: data)
        var dropped = 0
        let groups = dtos.map { dto -> AssignmentGroup in
            let groupID = CanvasID<AssignmentGroup>(dto.id)
            let assignments = (dto.assignments ?? []).compactMap { a -> Assignment? in
                guard let name = a.name else { dropped += 1; return nil }
                return Assignment(
                    id: CanvasID(a.id), courseID: a.courseId.map { CanvasID($0) } ?? courseID, groupID: groupID,
                    name: name, dueAt: a.dueAt, lockAt: a.lockAt, pointsPossible: a.pointsPossible,
                    gradingType: a.gradingType.flatMap(GradingType.init(rawValue:)) ?? .points,
                    omitFromFinalGrade: a.omitFromFinalGrade ?? false, htmlURL: a.htmlUrl,
                    submission: a.submission.map { s in
                        Submission(score: s.score, grade: s.grade, submittedAt: s.submittedAt, gradedAt: s.gradedAt,
                                   postedAt: s.postedAt, excused: s.excused ?? false, missing: s.missing ?? false,
                                   late: s.late ?? false, workflowState: s.workflowState ?? "unsubmitted",
                                   id: s.id.map { CanvasID($0) }, gradingPeriodID: s.gradingPeriodId.map { CanvasID($0) })
                    },
                    published: a.published ?? true, submissionTypes: a.submissionTypes ?? [])
            }
            return AssignmentGroup(
                id: groupID, name: dto.name ?? "", position: dto.position ?? 0, weight: dto.groupWeight,
                rules: DropRules(dropLowest: dto.rules?.dropLowest ?? 0, dropHighest: dto.rules?.dropHighest ?? 0,
                                 neverDrop: (dto.rules?.neverDrop ?? []).map { CanvasID($0) }),
                assignments: assignments)
        }
        return Mapped(items: groups, dropped: dropped)
    }
}
