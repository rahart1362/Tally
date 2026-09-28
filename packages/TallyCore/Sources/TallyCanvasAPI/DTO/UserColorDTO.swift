import Foundation
import TallyDomain

/// `GET /api/v1/users/self/colors`: `{"custom_colors": {"course_51842": "#1770AB", "user_...": "#8F3E97"}}`.
struct UserColorsDTO: Decodable {
    let customColors: [String: String]?
}

public enum UserColorMapper {
    private static let coursePrefix = "course_"

    /// Only `course_...` keys are course colors; other contexts (e.g. `user_...`, the
    /// account's own accent) are not part of `CanvasSnapshot.courseColors` and are skipped.
    public static func map(_ data: Data) throws -> [CanvasID<Course>: String] {
        let decoder = CanvasJSON.decoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try decoder.decode(UserColorsDTO.self, from: data)
        var colors: [CanvasID<Course>: String] = [:]
        for (key, value) in dto.customColors ?? [:] where key.hasPrefix(coursePrefix) {
            colors[CanvasID(String(key.dropFirst(coursePrefix.count)))] = value
        }
        return colors
    }
}
