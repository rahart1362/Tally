import Foundation
import TallyDomain

/// `GET /api/v1/calendar_events?type=event&context_codes[]=course_…(≤10)&start_date=…&end_date=…`.
/// Chunking the context codes to at most `TallyConfig.contextCodesPerRequest` is the request
/// builder's job (`CanvasClient`); this mapper only decodes one response body.
struct CalendarEventDTO: Decodable {
    let id: String
    let title: String?
    let startAt: Date?
    let endAt: Date?
    let allDay: Bool?
    let locationName: String?
    /// e.g. `"course_51843"`; only course contexts are requested, so this is always present
    /// in practice, but a missing or non-course context is dropped defensively.
    let contextCode: String?
    let htmlUrl: URL?
}

public enum CalendarEventMapper {
    private static let coursePrefix = "course_"

    public static func map(_ data: Data) throws -> Mapped<CalendarEvent> {
        let decoder = CanvasJSON.decoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dtos = try decoder.decode([CalendarEventDTO].self, from: data)
        let events = dtos.compactMap { dto -> CalendarEvent? in
            // `start_at` is the one field every Canvas calendar event has; without it the
            // item cannot be placed and is dropped and counted.
            guard let startAt = dto.startAt else { return nil }
            let courseID = dto.contextCode.flatMap { code -> CanvasID<Course>? in
                guard code.hasPrefix(coursePrefix) else { return nil }
                return CanvasID(String(code.dropFirst(coursePrefix.count)))
            }
            return CalendarEvent(id: CanvasID(dto.id), courseID: courseID, title: dto.title ?? "",
                                 startAt: startAt, endAt: dto.endAt, allDay: dto.allDay ?? false,
                                 locationName: dto.locationName, htmlURL: dto.htmlUrl)
        }
        return Mapped(items: events, dropped: dtos.count - events.count)
    }
}
