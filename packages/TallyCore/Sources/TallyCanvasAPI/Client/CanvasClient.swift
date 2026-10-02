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

    /// R-1 (resilience.md): the most times one request is retried while Canvas rate-limits it (429,
    /// or 403 "Rate Limit Exceeded"), so a persistent rate limit costs at most `1 +
    /// maxRateLimitRetries` requests per call. Canvas's API policy expects clients to back off, and
    /// hammering can get an institution's developer key throttled for every user of it. Each retry
    /// also has to fit in the request's budget (`fetchPage`).
    public static let maxRateLimitRetries = 4

    /// R-5 (resilience.md): the most times one request is retried after a 5xx (architecture §3.3:
    /// "at most twice"). With `maxRateLimitRetries` and the single token refresh, it bounds
    /// `fetchPage`'s loop at 1 + 1 + 2 + 4 = 8 requests, whatever the server answers.
    public static let maxServerErrorRetries = 2

    private let host: String
    private let allowedHosts: Set<String>
    private let transport: any HTTPTransport
    private let tokens: TokenCoordinator
    private let scheduler: RequestScheduler
    private let backoff: BackoffPolicy
    private var rng: any RandomNumberGenerator
    /// R-1: monotonic time since this client was made, from the injected `Clock`. Budgets are
    /// measured on it.
    private let elapsed: @Sendable () -> Duration
    /// R-1: every backoff wait goes through the same `Clock`, so a test clock can skip it.
    private let sleep: @Sendable (Duration) async throws -> Void
    /// R-1: "now" for an HTTP-date `Retry-After` on a response without a `Date` header.
    private let wallClock: any DateProviding

    /// - Parameters:
    ///   - allowedHosts: hosts a bearer token may be attached to (this account's own host
    ///     plus any redirected-to vanity domain from login). Defaults to just `host`.
    ///   - clock: measures each request's budget and runs its backoff waits (R-1). Tests pass a
    ///     virtual clock (`TallyTestSupport.VirtualClock`).
    ///   - wallClock: reads an HTTP-date `Retry-After` when the response has no `Date` header.
    public init<C: Clock>(host: String, allowedHosts: Set<String>? = nil, transport: any HTTPTransport, tokens: TokenCoordinator,
                          scheduler: RequestScheduler = RequestScheduler(), backoff: BackoffPolicy = BackoffPolicy(),
                          rng: any RandomNumberGenerator = SystemRandomNumberGenerator(),
                          clock: C = ContinuousClock(), wallClock: any DateProviding = SystemDateProvider())
        where C.Duration == Duration {
        self.host = host
        self.allowedHosts = allowedHosts ?? [host]
        self.transport = transport
        self.tokens = tokens
        self.scheduler = scheduler
        self.backoff = backoff
        self.rng = rng
        let origin = clock.now
        elapsed = { origin.duration(to: clock.now) }
        sleep = { try await clock.sleep(for: $0) }
        self.wallClock = wallClock
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

    /// One request whose non-2xx statuses are meaningful application responses the caller
    /// must inspect directly — e.g. the family-linking writes (family-linking.md §6.1
    /// W1-W3): a 422 invalid pairing code, or a 401 that only the caller's own institution
    /// registry can tell apart as "self-registration is off" vs "this key lacks the scope"
    /// (security.md §3.2's 401 table doesn't distinguish those; Canvas sends the same
    /// shape for both). Auth attach, the single 401-refresh-retry, and 5xx/429 backoff are
    /// exactly `fetchOne`'s; only a genuine transport/auth/server failure throws.
    public func perform(method: HTTPMethod, path: String, query: [(String, String)] = [],
                        body: Data? = nil, contentType: String? = nil,
                        budget: Duration = TallyConfig.liveRefreshBudget) async throws(RefreshFailure) -> HTTPResponse {
        var headers = Self.baseHeaders
        if let contentType { headers["Content-Type"] = contentType }
        let request = HTTPRequest(method: method, url: url(path: path, query: query), headers: headers, body: body)
        return try await fetchPage(request, budget: budget, throwOnClientError: false)
    }

    /// One request, end to end: attaches the current token; on a 401 carrying
    /// `WWW-Authenticate` refreshes once and retries; on a 401 without it (insufficient
    /// scope) fails without refreshing; on 429 or a rate-limited 403 backs off within
    /// `budget`; on 5xx retries at most `maxServerErrorRetries` (2) times with `BackoffPolicy`.
    ///
    /// R-1 (resilience.md): `budget` is measured from this call's start, on the injected clock, and
    /// a backoff wait is started only if it ends inside what is left of it. A call therefore
    /// overruns its budget by at most its last request's own duration. A rate limit is retried at
    /// most `maxRateLimitRetries` times, never sooner than the response's `Retry-After` or the
    /// policy's exponential floor (`BackoffPolicy.rateLimitDelay`). When the cap is reached, or the
    /// next wait would not fit (a `Retry-After` longer than the budget, say), the call throws
    /// `.rateLimited` at once rather than wait. A cancelled wait throws `.offline`, like every
    /// other below-HTTP interruption, instead of sending another request.
    ///
    /// `throwOnClientError` (added for `perform`, defaults `true` so `fetchOne`/
    /// `fetchAllPages` are unchanged): when `false`, `.insufficientScope`, `.forbidden`,
    /// `.notFound` and `.unexpected` return the raw response instead of throwing `.unknown`
    /// — the caller inspects the status/body itself rather than losing that distinction.
    private func fetchPage(_ initialRequest: HTTPRequest, budget: Duration,
                           throwOnClientError: Bool = true) async throws(RefreshFailure) -> HTTPResponse {
        var request = initialRequest
        var alreadyRefreshed = false
        var serverErrorAttempts = 0
        var rateLimitRetries = 0
        let deadline = elapsed() + budget
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

            // What is left of the budget: a retry's wait must end inside it.
            let retryBudget = deadline - elapsed()
            switch ResponseClassifier.classify(response) {
            case .success:
                // CS-05: a response body past this size never reaches a mapper — this bounds
                // memory from a misbehaving server or a hostile man-in-the-middle before JSON
                // decoding (and whatever a mapper does with the result) even starts. A real
                // Canvas page is nowhere close (see `TallyConfig.maxResponseBodyBytes`'s doc).
                guard response.body.count <= TallyConfig.maxResponseBodyBytes else { throw .contract }
                return response
            case .tokenRejected:
                guard !alreadyRefreshed else { throw .authExpired } // already retried once this call
                alreadyRefreshed = true
                do { _ = try await tokens.tokenAfterRejection(of: token) } catch { throw Self.authFailure(error) }
            case .insufficientScope:
                if !throwOnClientError { return response }
                throw .unknown // the key lacks the scope: the section is unavailable, never refresh
            case .serverError:
                serverErrorAttempts += 1
                guard serverErrorAttempts <= Self.maxServerErrorRetries,
                      let delay = backoff.delay(attempt: serverErrorAttempts - 1, remainingBudget: retryBudget, using: &rng)
                else { throw .server }
                try await pause(for: delay)
            case .rateLimited:
                // R-1: bounded by a retry cap and by what is left of the budget. It used to get the
                // whole budget on every attempt, so a persistent 429 retried until cancelled
                // (crash-safety-2.md F-6: 1,520 requests in 4 s).
                rateLimitRetries += 1
                guard rateLimitRetries <= Self.maxRateLimitRetries,
                      let delay = backoff.rateLimitDelay(attempt: rateLimitRetries - 1,
                                                         retryAfter: RetryAfter.delay(in: response, now: wallClock.now()),
                                                         remainingBudget: retryBudget, using: &rng)
                else { throw .rateLimited }
                try await pause(for: delay)
            case .forbidden, .notFound, .unexpected:
                if !throwOnClientError { return response }
                throw .unknown
            }
        }
    }

    /// A backoff wait on the injected clock. Cancelled, it ends the request as `.offline` (the
    /// report every below-HTTP interruption gets) rather than go on to send another request.
    private func pause(for delay: Duration) async throws(RefreshFailure) {
        do { try await sleep(delay) } catch { throw .offline }
    }

    private static func authFailure(_ error: AuthError) -> RefreshFailure {
        switch error {
        case .reauthRequired: .authExpired
        case .transient: .server // network/server trouble refreshing the token, not a Canvas API response
        case .schoolDisabled: .schoolDisabled // PAY-10: the school turned off Tally's developer key
        }
    }
}
