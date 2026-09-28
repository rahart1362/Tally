import Foundation
import TallyDomain

/// `POST /api/v1/users/self/observer_pairing_codes` (W1) success body: `{user_id, code,
/// expires_at, workflow_state}` (family-linking.md §2.2, VERIFIED docs: User Observees API).
struct PairingCodeDTO: Decodable {
    let code: String
    let expiresAt: Date
}

enum PairingCodeMapper {
    static func map(_ data: Data) throws -> PairingInvite {
        let decoder = CanvasJSON.decoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try decoder.decode(PairingCodeDTO.self, from: data)
        return PairingInvite(code: dto.code, expiresAt: dto.expiresAt)
    }
}
