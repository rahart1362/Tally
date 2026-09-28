import Foundation
import TallyDomain

/// `GET /api/v1/users/self/profile`. Every field except `id` is optional.
struct ProfileDTO: Decodable {
    struct CalendarDTO: Decodable { let ics: String? }
    let id: String
    let name: String?
    let shortName: String?
    let timeZone: String?
    /// The student's personal Canvas calendar feed (PMO R6: calendar subscription).
    let calendar: CalendarDTO?
}

public enum ProfileMapper {
    public static func map(_ data: Data) throws -> UserProfile {
        let decoder = CanvasJSON.decoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try decoder.decode(ProfileDTO.self, from: data)
        return UserProfile(id: CanvasID(dto.id), name: dto.name ?? "", shortName: dto.shortName,
                           timeZone: dto.timeZone, calendarFeedURL: dto.calendar?.ics.flatMap { URL(string: $0) })
    }
}
