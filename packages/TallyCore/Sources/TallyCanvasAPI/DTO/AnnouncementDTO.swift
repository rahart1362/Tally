import Foundation
import TallyDomain

/// `GET /api/v1/announcements?context_codes[]=course_…(chunked)&start_date=…`.
struct AnnouncementDTO: Decodable {
    let id: String
    let title: String?
    let postedAt: Date?
    let readState: String?
    let contextCode: String?
    let htmlUrl: URL?
}

public enum AnnouncementMapper {
    private static let coursePrefix = "course_"

    public static func map(_ data: Data) throws -> Mapped<Announcement> {
        let decoder = CanvasJSON.decoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dtos = try decoder.decode([AnnouncementDTO].self, from: data)
        let announcements = dtos.compactMap { dto -> Announcement? in
            // Unlike a calendar event, an announcement without a course context is
            // meaningless in Tally (there is nowhere to show it), so it is dropped.
            guard let contextCode = dto.contextCode, contextCode.hasPrefix(coursePrefix) else { return nil }
            let courseID = CanvasID<Course>(String(contextCode.dropFirst(coursePrefix.count)))
            return Announcement(id: CanvasID(dto.id), courseID: courseID, title: dto.title ?? "",
                                postedAt: dto.postedAt, isRead: dto.readState != "unread", htmlURL: dto.htmlUrl)
        }
        return Mapped(items: announcements, dropped: dtos.count - announcements.count)
    }
}
