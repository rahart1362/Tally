import Foundation
import TallyCanvasAPI

/// Looks up institutions by name (ux-ui.md §3.2.1). Behind a protocol, per
/// the implementation brief, so `SchoolSearchViewModel` can be UI-tested
/// against fixtures instead of the network.
public protocol InstitutionSearching: Sendable {
    func search(name: String) async throws -> [InstitutionMatch]
}

/// `GET https://canvas.instructure.com/api/v1/accounts/search?name=`
/// (ux-ui.md §3.2.1: "observed live 2026-09-26 returning HTTP 200 without
/// auth"; `InstitutionDirectory`'s own header: "UNVERIFIED shape, not in the
/// REST docs"; security.md D4 flags this as legal/ARC to clear before
/// public launch). Composes the request with `TallyCore`'s existing,
/// Linux-tested `InstitutionDirectory.search(_:)` parser — the only new
/// code here is building the request and reading the status.
///
/// Depends only on `any HTTPTransport` (`TallyCanvasAPI`), never a concrete
/// `URLSession` type: the ephemeral, no-cache-or-cookies transport (SEC-08)
/// is the platform-adapters team's work package (`URLSessionTransport`),
/// not this one. Until that adapter is wired at the composition root, this
/// type has no production instance — exactly like `WebAuthPresenter`'s
/// stubbed token endpoint (UX-WP-09), this is the seam the PMO connects
/// when the M2-B branches merge.
public struct CanvasAccountSearch: InstitutionSearching {
    private static let searchHost = "canvas.instructure.com"
    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport) {
        self.transport = transport
    }

    public func search(name: String) async throws -> [InstitutionMatch] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.searchHost
        components.path = "/api/v1/accounts/search"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = components.url else { return [] }
        let request = HTTPRequest(url: url, headers: HTTPHeaders(["Accept": "application/json"]))
        let response = try await transport.send(request)
        guard (200..<300).contains(response.status) else {
            throw InstitutionSearchError.rejected(status: response.status)
        }
        return try InstitutionDirectory.search(response.body)
    }
}

public enum InstitutionSearchError: Error, Sendable, Equatable {
    case rejected(status: Int)
    /// No live `HTTPTransport` is wired in yet (see `CanvasAccountSearch`'s doc comment).
    case transportNotConfigured
}

/// The default until the composition root can supply a real `HTTPTransport`
/// (`URLSessionTransport`, a platform-adapters work package not yet merged
/// into this worktree). Mirrors `TallyApp.swift`'s own background-task
/// handler, which "intentionally does nothing rather than simulate a
/// refresh result: the implementation brief forbids fabricating data in
/// shipping code paths" — this does the same for search: it fails
/// honestly (`.searchFailed` in the UI) instead of returning fake schools.
public struct UnavailableInstitutionSearch: InstitutionSearching {
    public init() {}
    public func search(name: String) async throws -> [InstitutionMatch] {
        throw InstitutionSearchError.transportNotConfigured
    }
}
