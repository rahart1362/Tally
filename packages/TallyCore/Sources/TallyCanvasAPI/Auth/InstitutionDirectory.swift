import Foundation

/// `GET https://canvas.instructure.com/api/v1/accounts/search?name=…` (unauthenticated,
/// architecture §3.5). UNVERIFIED shape (not in the REST docs): observed live 2026-09-26,
/// `id` a string because Tally sends `Accept: application/json+canvas-string-ids`.
struct AccountSearchDTO: Decodable {
    let id: String
    let name: String?
    let domain: String?
    let authenticationProvider: String?
}

/// One search result, its host normalized (the same `InstitutionHost` login uses).
public struct InstitutionMatch: Sendable, Equatable {
    public let id: String
    public let name: String
    public let host: String
    public let authenticationProvider: String?

    public init(id: String, name: String, host: String, authenticationProvider: String?) {
        self.id = id; self.name = name; self.host = host; self.authenticationProvider = authenticationProvider
    }
}

/// "Tally isn't enabled at <school> yet" (architecture §3.5): a host with no `ClientRegistry`
/// entry never shows a broken login, it shows that and an admin-request path. The words are the
/// app's (onboarding's `SchoolSearchViewModel` maps this to `.notEnabled(school:)`); plan 08
/// §3.2 (L10N-02) removed the English `message` this type used to carry, which nothing read.
public enum InstitutionEnablementError: Error, Sendable, Equatable {
    case notEnabled(school: String)
}

public enum InstitutionDirectory {
    /// Parses the account-search response. A row without a name or a host that fails
    /// `InstitutionHost` normalization is dropped (it cannot be signed into), never fatal.
    public static func search(_ data: Data) throws -> [InstitutionMatch] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dtos = try decoder.decode([AccountSearchDTO].self, from: data)
        return dtos.compactMap { dto in
            guard let name = dto.name, let domain = dto.domain,
                  let host = try? InstitutionHost.normalize(domain) else { return nil }
            return InstitutionMatch(id: dto.id, name: name, host: host, authenticationProvider: dto.authenticationProvider)
        }
    }

    /// The registry entry for a search result's host, or `.notEnabled` with the school's name
    /// for display, never a broken login flow.
    public static func registration(for match: InstitutionMatch,
                                    in registry: ClientRegistry) throws(InstitutionEnablementError) -> ClientRegistration {
        guard let registration = registry.registration(for: match.host) else {
            throw .notEnabled(school: match.name)
        }
        return registration
    }
}
