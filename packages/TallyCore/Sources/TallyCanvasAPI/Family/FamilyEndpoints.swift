import Foundation

/// The scope string for each family-linking endpoint (family-linking.md §6.1's table;
/// format `url:<VERB>|<path>` per architecture §3.3/security §3.2.11). W1, W2 and W3 are
/// the only three writes anywhere in Tally (proposed ruling R16a) — every other family
/// endpoint is a plain read reusing scopes the student-facing catalogue already requests.
public enum FamilyScopes {
    /// S1: student — "Who can see my Canvas".
    public static let listObservers = "url:GET|/api/v1/users/:user_id/observers"
    /// O1: parent — "Linked students".
    public static let listObservees = "url:GET|/api/v1/users/:user_id/observees"
    /// W1: student — create a pairing code (R16a write).
    public static let createPairingCode = "url:POST|/api/v1/users/:user_id/observer_pairing_codes"
    /// W2: parent — add a student by code (R16a write).
    public static let addObservee = "url:POST|/api/v1/users/:user_id/observees"
    /// W3: parent — unlink (R16a write).
    public static let removeObservee = "url:DELETE|/api/v1/users/:user_id/observees/:id"

    public static let all: [String] = [listObservers, listObservees, createPairingCode, addObservee, removeObservee]
}

/// Request shapes (family-linking.md §6.1). Paths and queries only — `CanvasClient` attaches
/// auth, retry and backoff; see `LinkManagementUseCases.swift`.
enum FamilyEndpoints {
    static let observersPath = "/api/v1/users/self/observers"
    static let observeesPath = "/api/v1/users/self/observees"
    static let pairingCodesPath = "/api/v1/users/self/observer_pairing_codes"
    static func observeePath(_ canvasUserID: String) -> String { "/api/v1/users/self/observees/\(canvasUserID)" }

    /// S1 and O1 share this query (both return the same "User" shape, §6.1).
    static let observedUsersQuery: [(String, String)] = [("include[]", "avatar_url"), ("per_page", "100")]

    /// R-1 (resilience.md): the budget every family-linking request gets. No refresh coordinator
    /// sits above these calls to cancel a runaway retry, so this budget is their ceiling:
    /// `CanvasClient` measures it on its clock, never backs off past it, retries a rate limit at
    /// most `CanvasClient.maxRateLimitRetries` times, and ends a persistent 429 as
    /// `.network(.rateLimited)`. 10 s, like a live refresh: each call is a tap the user waits on.
    static let requestBudget: Duration = .seconds(10)
}

/// `application/x-www-form-urlencoded` body encoding. W2 sends `pairing_code` in the
/// **form body**, never the query string (family-linking.md §4.3: "the body keeps a live
/// bearer secret out of URL logs" — Instructure's own app puts it in the query, per §6.1).
enum FormBody {
    static func encode(_ pairs: [(String, String)]) -> Data {
        var components = URLComponents()
        components.queryItems = pairs.map { URLQueryItem(name: $0.0, value: $0.1) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    static let contentType = "application/x-www-form-urlencoded"
}
