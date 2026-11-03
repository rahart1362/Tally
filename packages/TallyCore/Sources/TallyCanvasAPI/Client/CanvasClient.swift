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
    /// Item 3 (LIVE-FIX-2/LIVE-3): `nil` (the default) is exactly today's client -- no
    /// `If-None-Match`, no 304 handling, no behaviour change for a caller that does not pass
    /// one.
    private let etags: (any ETagStore)?

    /// - Parameters:
    ///   - allowedHosts: hosts a bearer token may be attached to (this account's own host
    ///     plus any redirected-to vanity domain from login). Defaults to just `host`.
    ///   - clock: measures each request's budget and runs its backoff waits (R-1). Tests pass a
    ///     virtual clock (`TallyTestSupport.VirtualClock`).
    ///   - wallClock: reads an HTTP-date `Retry-After` when the response has no `Date` header.
    ///   - etags: item 3's conditional-request cache (`If-None-Match` per endpoint and request,
    ///     reusing the cached body on a 304). `nil` (the default) disables it entirely.
    public init<C: Clock>(host: String, allowedHosts: Set<String>? = nil, transport: any HTTPTransport, tokens: TokenCoordinator,
                          scheduler: RequestScheduler = RequestScheduler(), backoff: BackoffPolicy = BackoffPolicy(),
                          rng: any RandomNumberGenerator = SystemRandomNumberGenerator(),
                          clock: C = ContinuousClock(), wallClock: any DateProviding = SystemDateProvider(),
                          etags: (any ETagStore)? = nil)
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
        self.etags = etags
    }

    private static var baseHeaders: HTTPHeaders { HTTPHeaders(["Accept": acceptHeader, "User-Agent": userAgent]) }

    /// F3 (`docs/pmo/reviews/live1-report.md`): `host` is expected to already be a bare,
    /// normalized hostname, but nothing here enforced that -- a caller that folds a port (or any
    /// other invalid character) into it made `components.url` return `nil`, and the
    /// force-unwrap below trapped three calls deep inside every public method, from a caller
    /// error, not a hostile input. It now throws `.unknown` instead: a non-retryable, client-side
    /// failure, the same bucket `fetchPage` already uses for `.insufficientScope`/`.forbidden`/
    /// `.notFound`/`.unexpected` -- never worth a token refresh or a backoff retry.
    private func url(path: String, query: [(String, String)]) throws(RefreshFailure) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) } }
        guard let url = components.url else { throw .unknown }
        return url
    }

    /// GET one non-paged resource's body.
    public func fetchOne(path: String, query: [(String, String)] = [],
                         budget: Duration = TallyConfig.liveRefreshBudget) async throws(RefreshFailure) -> Data {
        let request = HTTPRequest(url: try url(path: path, query: query), headers: Self.baseHeaders)
        return try await fetchPage(request, budget: budget).body
    }

    /// GET, following `Link rel=next` until it is absent or `TallyConfig.maxPagesPerResource`
    /// pages have been fetched. Returns every page's raw body, in order.
    public func fetchAllPages(path: String, query: [(String, String)] = [],
                              budget: Duration = TallyConfig.liveRefreshBudget) async throws(RefreshFailure) -> [Data] {
        let request = HTTPRequest(url: try url(path: path, query: query), headers: Self.baseHeaders)
        let first = try await fetchPage(request, budget: budget)
        return try await continuePaginating(firstPageBody: first.body, from: first, budget: budget)
    }

    /// Item 2 (LIVE-FIX-2, live2-security's "enrollment_or_course" finding): like `fetchAllPages`,
    /// except a 403 or 404 on the very FIRST page -- a deleted or forbidden course's own
    /// resource -- is reported back as `.failure` instead of thrown, so a per-course caller
    /// (`CanvasGateway.fetchAssignmentGroups`) can skip just that course and keep the rest of a
    /// required section instead of failing the whole refresh. Any other failure (offline, 5xx,
    /// rate-limited, insufficient scope, a malformed/oversized body, or a 403/404 on a LATER
    /// page once pagination is already under way) still throws exactly as `fetchAllPages` does.
    public func fetchAllPagesOrSkip(path: String, query: [(String, String)] = [],
                                    budget: Duration = TallyConfig.liveRefreshBudget)
        async throws(RefreshFailure) -> Result<[Data], CourseFetchSkipReason> {
        let request = HTTPRequest(url: try url(path: path, query: query), headers: Self.baseHeaders)
        let first = try await fetchPage(request, budget: budget, throwOnClientError: false)
        switch first.status {
        case 403: return .failure(.forbidden)
        case 404: return .failure(.notFound)
        default: break
        }
        guard case .success = ResponseClassifier.classify(first) else {
            // `throwOnClientError: false` also tolerates `.insufficientScope`/`.unexpected`
            // without throwing (so this call can inspect the status itself); neither is a
            // per-course "resource unavailable" shape this caller should skip, so reclassify
            // and fail exactly as `fetchAllPages` would have.
            throw ResponseClassifier.refreshFailure(for: ResponseClassifier.classify(first)) ?? .unknown
        }
        return .success(try await continuePaginating(firstPageBody: first.body, from: first, budget: budget))
    }

    /// Follows `Link rel=next` from `first`'s own headers, starting from its already-fetched
    /// body, until the link is absent or `TallyConfig.maxPagesPerResource` pages have been
    /// fetched.
    ///
    /// Item 5 (LIVE-3, `docs/pmo/reviews/live1-report.md`): a `next` link `PageURLPolicy` rejects
    /// (not https, a foreign host, or embedded credentials) used to `try?`-swallow the rejection
    /// and silently stop, exactly as if pagination had ended naturally -- so a page Canvas really
    /// did have more of was dropped with no error and no trace (reproduced live: Riley's
    /// announcements, 61 of 67, because the dev Link header's scheme is http). Production Canvas
    /// is always https (F2, live1-report.md), so a real rejection there is not an ordinary
    /// end-of-data case but a malformed or suspicious `Link` header; this now throws `.unknown`
    /// instead (the same non-retryable bucket `insufficientScope`/`forbidden`/`notFound` already
    /// use) rather than returning a silently truncated result. For an OPTIONAL section this is
    /// caught by `CanvasGateway.optionalSection` exactly like any other fetch failure, which
    /// already carries the previous value forward flagged `carriedForward` -- so the snapshot is
    /// correctly marked incomplete instead of silently truncated. For a REQUIRED section this
    /// fails the whole refresh, the same as any other required-section failure (offline, a 5xx,
    /// a rate limit) already does.
    private func continuePaginating(firstPageBody: Data, from first: HTTPResponse,
                                    budget: Duration) async throws(RefreshFailure) -> [Data] {
        var bodies = [firstPageBody]
        var response = first
        var pageCount = 1
        while pageCount < TallyConfig.maxPagesPerResource, let next = LinkHeader.nextURL(in: response) {
            do { try PageURLPolicy.validate(next, allowedHosts: allowedHosts) } catch { throw .unknown }
            response = try await fetchPage(HTTPRequest(url: next, headers: Self.baseHeaders), budget: budget)
            bodies.append(response.body)
            pageCount += 1
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
        let request = HTTPRequest(method: method, url: try url(path: path, query: query), headers: headers, body: body)
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
    ///
    /// Item 3 (LIVE-FIX-2/LIVE-3): when `etags` is set and this is a GET with a cached entry for
    /// its exact URL, `If-None-Match` is attached once, up front -- it never changes across this
    /// call's own retries, only whether the token attached alongside it does. A 304 answers from
    /// that cached body (as a synthesized 200, so every caller above this method is unaffected);
    /// a 200 that carries a fresh `ETag` replaces the cache entry.
    private func fetchPage(_ initialRequest: HTTPRequest, budget: Duration,
                           throwOnClientError: Bool = true) async throws(RefreshFailure) -> HTTPResponse {
        var request = initialRequest
        let cacheKey = request.url.absoluteString
        var cachedEntry: ETagCacheEntry?
        if request.method == .get, let etags {
            cachedEntry = await etags.entry(for: cacheKey)
            if let cachedEntry { request.headers["If-None-Match"] = cachedEntry.etag }
        }
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
                if request.method == .get, let etags, let etag = response.headers["ETag"] {
                    await etags.setEntry(ETagCacheEntry(etag: etag, body: response.body, linkHeader: response.headers["Link"],
                                                        lastUsedAt: wallClock.now()),
                                        for: cacheKey)
                }
                return response
            case .notModified:
                // Only ever reached when this call itself sent `If-None-Match` above, which only
                // happens with a `cachedEntry` already in hand -- `.unknown` here is defensive,
                // not a real path (a transport that fabricates a 304 unprompted).
                guard let cachedEntry else { throw .unknown }
                // Item 3 round 2: a 304 is a use, not just a lookup -- without this, an endpoint
                // whose URL never changes (courses, profile, assignment groups) would still look
                // "last used" the day it was first cached, and `ETagCachePruning`'s age check
                // would drop it even though every refresh since has actually reused it.
                if let etags {
                    await etags.setEntry(ETagCacheEntry(etag: cachedEntry.etag, body: cachedEntry.body,
                                                        linkHeader: cachedEntry.linkHeader, lastUsedAt: wallClock.now()),
                                        for: cacheKey)
                }
                // A 304 never repeats `Link` (confirmed live), so pagination's own continuation
                // check reads the cached entry's, not this response's.
                var syntheticHeaders = HTTPHeaders()
                if let link = cachedEntry.linkHeader { syntheticHeaders["Link"] = link }
                return HTTPResponse(status: 200, headers: syntheticHeaders, body: cachedEntry.body)
            case .tokenRejected:
                // LIVE-FIX-2 (EB-26): a second rejection in THIS call means the token this call
                // itself just refreshed (`tokenAfterRejection` below) was rejected again right
                // away -- the same "fresh token rejected" signature `TokenCoordinator`'s own
                // loop guard reports as `.schoolDisabled` for a rejection that arrives via a
                // separate call. `alreadyRefreshed` already guarantees at most one refresh per
                // `fetchPage` call, so this never loops either.
                guard !alreadyRefreshed else { throw .schoolDisabled }
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

    /// Item 3 round 2 ("one write per refresh"): `LiveCanvasGateway.fetchSnapshot` calls this
    /// exactly once, on success and on failure, so every `setEntry` this refresh made lands in
    /// one disk write (pruned first) instead of one write per endpoint. A no-op with no `etags`.
    public func flushETagCache() async {
        await etags?.flush()
    }

    /// EB-26 ("Erase Saved Data"): discards the in-memory conditional-GET cache so a later
    /// refresh cannot serve a `304` from (or flush back to disk) content the purge just erased.
    /// See `CanvasGateway.clearLocalCaches()`. A no-op with no `etags`.
    public func clearETagCache() async {
        await etags?.clear()
    }
}
