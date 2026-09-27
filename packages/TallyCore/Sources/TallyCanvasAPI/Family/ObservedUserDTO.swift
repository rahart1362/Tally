import Foundation
import TallyDomain

/// The "User" shape Canvas returns from `GET /users/self/observers` (S1), `GET
/// /users/self/observees` (O1), and the single-object response of `POST
/// /users/self/observees` (W2) — matching `fixtures/canvas/schemas/Observee.schema.json`
/// (id, name, avatar_url, …). Only the observees shape (O1) has a recorded fixture; the
/// observers endpoint (S1) is the same "User" object per Instructure's own docs (family
/// -linking.md §2.4), but that specific response is UNVERIFIED against hosted Canvas
/// pending FAM-01.
struct ObservedUserDTO: Decodable {
    let id: String
    let name: String
    let avatarUrl: String?
}

enum ObservedUserMapper {
    static func map(_ data: Data) throws -> [ObservedUser] {
        let decoder = CanvasJSON.decoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([ObservedUserDTO].self, from: data).map(Self.user)
    }

    /// W2's success response is a single object, not an array (family-linking.md §6.1 W2).
    static func mapOne(_ data: Data) throws -> ObservedUser {
        let decoder = CanvasJSON.decoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return Self.user(try decoder.decode(ObservedUserDTO.self, from: data))
    }

    private static func user(_ dto: ObservedUserDTO) -> ObservedUser {
        ObservedUser(canvasUserID: dto.id, name: dto.name, avatarURL: dto.avatarUrl.flatMap(URL.init(string:)))
    }
}
