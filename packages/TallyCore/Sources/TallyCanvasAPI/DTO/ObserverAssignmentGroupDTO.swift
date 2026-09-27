import Foundation
import TallyDomain

/// FAM-03 (stretch): the observer shape of
/// `GET /api/v1/courses/:id/assignment_groups?include[]=assignments&include[]=submission&include[]=observed_users`.
///
/// Canvas embeds one `submission` entry **per observee** as an array on this call —
/// `assignment_groups_controller.rb:112`: "submissions for observed users will also be
/// included as an array" (family-linking.md §6.1, VERIFIED against OSS) — instead of the
/// single object a student's own call gets (`AssignmentGroupDTO`, WP-B04). A separate DTO
/// (rather than widening `AssignmentGroupDTO.AssignmentDTO.submission`'s type) keeps that
/// already-shipped, already-tested mapper untouched.
///
/// This does not itself resolve the disputed `observed_user` question in family-linking.md
/// §6.1's table (whether the *courses* endpoint also embeds `observed_user`, vs. only the
/// Enrollments API): the fixture (`personas/parent-observer/northfield/courses.json`) shows
/// **neither**. Each course's plain `enrollments` array simply gains a second row: the
/// observer's own (`type: "observer"`, `associated_user_id` naming the observee) alongside
/// the observee's ordinary `student` row (with `computed_current_score` etc., exactly as a
/// self-view response has it). No `observed_user` key appears anywhere in that response.
/// `CourseMapper` (WP-B03) already selects the first `student`-type enrollment regardless of
/// caller, so it maps an observer's courses response correctly unchanged — verified by
/// `ObserverMappingTests.courseMapperAlreadyHandlesTheObserverCoursesResponse`.
struct ObserverAssignmentGroupDTO: Decodable {
    struct RulesDTO: Decodable { let dropLowest: Int?; let dropHighest: Int?; let neverDrop: [String]? }
    struct SubmissionDTO: Decodable {
        let id: String?
        /// Which observee this array entry belongs to.
        let userId: String?
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
        /// An array here (one entry per observee sharing this call), never a single object.
        let submission: [SubmissionDTO]?
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

public enum ObserverAssignmentGroupMapper {
    /// Maps one observee's assignment groups out of an observer's combined response,
    /// selecting the `submission` array entry whose `user_id` matches `observeeUserID`.
    /// An assignment with no entry for that observee (e.g. it predates their enrollment)
    /// simply has `submission == nil`, same as an ungraded item in the student's own view.
    public static func map(_ data: Data, courseID: CanvasID<Course>, observeeUserID: String) throws -> Mapped<AssignmentGroup> {
        let decoder = CanvasJSON.decoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dtos = try decoder.decode([ObserverAssignmentGroupDTO].self, from: data)
        var dropped = 0
        let groups = dtos.map { dto -> AssignmentGroup in
            let groupID = CanvasID<AssignmentGroup>(dto.id)
            let assignments = (dto.assignments ?? []).compactMap { a -> Assignment? in
                guard let name = a.name else { dropped += 1; return nil }
                let mine = a.submission?.first { $0.userId == observeeUserID }
                return Assignment(
                    id: CanvasID(a.id), courseID: a.courseId.map { CanvasID($0) } ?? courseID, groupID: groupID,
                    name: name, dueAt: a.dueAt, lockAt: a.lockAt, pointsPossible: a.pointsPossible,
                    gradingType: a.gradingType.flatMap(GradingType.init(rawValue:)) ?? .points,
                    omitFromFinalGrade: a.omitFromFinalGrade ?? false, htmlURL: a.htmlUrl,
                    submission: mine.map { s in
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
