import Foundation
import TallyDomain

/// `GET /api/v1/planner/items?start_date=…&end_date=…&per_page=100` (paged; `CanvasClient`
/// follows `Link` `rel="next"`, this mapper decodes one page).
struct PlannerItemDTO: Decodable {
    struct PlannableDTO: Decodable {
        let title: String?
        let pointsPossible: Double?
    }
    /// Canvas emits either `false` (nothing to submit: a calendar event, announcement or
    /// planner note) or a submission-flags object. Every flag defaults to `false`.
    struct SubmissionsDTO: Decodable {
        let submitted: Bool
        let excused: Bool
        let graded: Bool
        let missing: Bool
        let late: Bool

        private enum CodingKeys: String, CodingKey { case submitted, excused, graded, missing, late }

        init(from decoder: any Decoder) throws {
            // Canvas only ever sends `false` here; a stray `true` would still mean "no flags".
            if (try? decoder.singleValueContainer().decode(Bool.self)) != nil {
                (submitted, excused, graded, missing, late) = (false, false, false, false, false)
                return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            submitted = try c.decodeIfPresent(Bool.self, forKey: .submitted) ?? false
            excused = try c.decodeIfPresent(Bool.self, forKey: .excused) ?? false
            graded = try c.decodeIfPresent(Bool.self, forKey: .graded) ?? false
            missing = try c.decodeIfPresent(Bool.self, forKey: .missing) ?? false
            late = try c.decodeIfPresent(Bool.self, forKey: .late) ?? false
        }
    }
    struct OverrideDTO: Decodable { let markedComplete: Bool? }

    let courseId: String?
    let plannableId: String?
    let plannableType: String?
    /// The date Canvas itself places this item on in the planner: `due_at` for an assignment
    /// or quiz, `todo_date` for a planner note, `start_at` for a calendar event, the posting
    /// date for an announcement. Using this one field (rather than a field per plannable type)
    /// matches every persona and scenario fixture exactly.
    let plannableDate: Date?
    let plannable: PlannableDTO?
    let submissions: SubmissionsDTO?
    let plannerOverride: OverrideDTO?
    let htmlUrl: String?
}

/// `html_url` on a planner item is sometimes host-relative (e.g. a submission page),
/// sometimes already absolute (a calendar event or a planner note's API URL).
enum CanvasRelativeURL {
    static func resolve(_ raw: String?, host: String) -> URL? {
        guard let raw else { return nil }
        if raw.hasPrefix("/") { return URL(string: "https://\(host)\(raw)") }
        return URL(string: raw)
    }
}

public enum PlannerItemMapper {
    /// An item without both a plannable id and type cannot form the stable
    /// `"<plannable_type>:<plannable_id>"` id and is dropped and counted.
    public static func map(_ data: Data, host: String) throws -> Mapped<PlannerItem> {
        let decoder = CanvasJSON.decoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dtos = try decoder.decode([PlannerItemDTO].self, from: data)
        let items = dtos.compactMap { dto -> PlannerItem? in
            guard let plannableId = dto.plannableId, let plannableType = dto.plannableType else { return nil }
            let submissions = dto.submissions
            return PlannerItem(
                id: "\(plannableType):\(plannableId)",
                courseID: dto.courseId.map { CanvasID($0) },
                title: dto.plannable?.title ?? "",
                plannableType: plannableType,
                dueAt: dto.plannableDate,
                pointsPossible: dto.plannable?.pointsPossible,
                submitted: submissions?.submitted ?? false,
                graded: submissions?.graded ?? false,
                missing: submissions?.missing ?? false,
                late: submissions?.late ?? false,
                excused: submissions?.excused ?? false,
                markedComplete: dto.plannerOverride?.markedComplete ?? false,
                htmlURL: CanvasRelativeURL.resolve(dto.htmlUrl, host: host))
        }
        return Mapped(items: items, dropped: dtos.count - items.count)
    }
}
