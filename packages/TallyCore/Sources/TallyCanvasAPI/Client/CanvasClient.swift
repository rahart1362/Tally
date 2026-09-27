import Foundation
import TallyDomain

/// One account's Canvas REST client (architecture §3.3): attaches the bearer token, the
/// `canvas-string-ids` Accept header and a `User-Agent`, applies the 401/429/403-rate-limited
/// /5xx policy, and follows `Link rel=next` (validated by `PageURLPolicy`) through the shared
/// `RequestScheduler`. Errors are reported as `RefreshFailure` (`TallyDomain`), the same
/// category vocabulary the refresh coordinator and freshness UI already use.
public actor CanvasClient {
    public static let acceptHeader = "application/json+canvas-string-ids"
    public static let userAgent = "Tally/1.0"

    private let host: String
    private let allowedHosts: Set<String>
    private let transport: any HTTPTransport
    private let tokens: TokenCoordinator
    private let scheduler: RequestScheduler
    private let backoff: BackoffPolicy
    private var rng: any RandomNumberGenerator

    /// - Parameters:
    ///   - allowedHosts: hosts a bearer token may be attached to (this account's own host
    ///     plus any redirected-to vanity domain from login). Defaults to just `host`.
    public init(host: String, allowedHosts: Set<String>? = nil, transport: any HTTPTransport, tokens: TokenCoordinator,
               scheduler: RequestScheduler = RequestScheduler(), backoff: BackoffPolicy = BackoffPolicy(),
               rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.host = host
        self.allowedHosts = allowedHosts ?? [host]
        self.transport = transport
        self.tokens = tokens
        self.scheduler = scheduler
        self.backoff = backoff
        self.rng = rng
    }

    private static var baseHeaders: HTTPHeaders { HTTPHeaders(["Accept": acceptHeader, "User-Agent": userAgent]) }

    private func url(path: String, query: [(String, String)]) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) } }
        return components.url! // swiftlint:disable:this force_unwrapping — scheme/host/path are always well-formed here
    }

    /// GET one non-paged resource's body.
    public func fetchOne(path: String, query: [(String, String)] = [],
                         budget: Duration = TallyConfig.liveRefreshBudget) async throws(RefreshFailure) -> Data {
        try await fetchPage(HTTPRequest(url: url(path: path, query: query), headers: Self.baseHeaders), budget: budget).body
    }

    /// GET, following `Link rel=next` until it is absent or `TallyConfig.maxPagesPerResource`
    /// pages have been fetched. Returns every page's raw body, in order.
    public func fetchAllPages(path: String, query: [(String, String)] = [],
                              budget: Duration = TallyConfig.liveRefreshBudget) async throws(RefreshFailure) -> [Data] {
        var bodies: [Data] = []
        var request = HTTPRequest(url: url(path: path, query: query), headers: Self.baseHeaders)
        var pageCount = 0
        while true {
            let response = try await fetchPage(request, budget: budget)
            bodies.append(response.body)
            pageCount += 1
            guard pageCount < TallyConfig.maxPagesPerResource, let next = LinkHeader.nextURL(in: response) else { break }
            guard (try? PageURLPolicy.validate(next, allowedHosts: allowedHosts)) != nil else { break }
            request = HTTPRequest(url: next, headers: Self.baseHeaders)
        }
        return bodies
    }

    /// One request, end to end: attaches the current token; on a 401 carrying
    /// `WWW-Authenticate` refreshes once and retries; on a 401 without it (insufficient
    /// scope) fails without refreshing; on 429 or a rate-limited 403 backs off within
    /// `budget`; on 5xx retries at most twice with `BackoffPolicy`.
    private func fetchPage(_ initialRequest: HTTPRequest, budget: Duration) async throws(RefreshFailure) -> HTTPResponse {
        var request = initialRequest
        var alreadyRefreshed = false
        var serverErrorAttempts = 0
        var rateLimitAttempts = 0
        while true {
            let token: String
            do { token = try await tokens.accessToken() } catch { throw Self.authFailure(error) }
            request.headers["Authorization"] = "Bearer \(token)"

            let response: HTTPResponse
            do {
                response = try await scheduler.perform { [transport, request] in try await transport.send(request) }
            } catch {
                throw .offline // every below-HTTP failure (offline, timed out, cancelled) is reported the same way
            }

            switch ResponseClassifier.classify(response) {
            case .success:
                return response
            case .tokenRejected:
                guard !alreadyRefreshed else { throw .authExpired } // already retried once this call
                alreadyRefreshed = true
                do { _ = try await tokens.tokenAfterRejection(of: token) } catch { throw Self.authFailure(error) }
            case .insufficientScope:
                throw .unknown // the key lacks the scope: the section is unavailable, never refresh
            case .serverError:
                serverErrorAttempts += 1
                guard serverErrorAttempts <= 2,
                      let delay = backoff.delay(attempt: serverErrorAttempts - 1, remainingBudget: budget, using: &rng)
                else { throw .server }
                try? await Task.sleep(for: delay)
            case .rateLimited:
                // Bounded only by the remaining budget (architecture §3.3), not a fixed attempt count.
                guard let delay = backoff.delay(attempt: rateLimitAttempts, remainingBudget: budget, using: &rng) else {
                    throw .rateLimited
                }
                rateLimitAttempts += 1
                try? await Task.sleep(for: delay)
            case .forbidden, .notFound, .unexpected:
                throw .unknown
            }
        }
    }

    private static func authFailure(_ error: AuthError) -> RefreshFailure {
        switch error {
        case .reauthRequired: .authExpired
        case .transient: .server // network/server trouble refreshing the token, not a Canvas API response
        }
    }
}
