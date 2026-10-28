import Foundation

/// Item 3 (LIVE-FIX-2/LIVE-3, `docs/pmo/reviews/live1-report.md`): one cached conditional-GET
/// entry -- the `ETag` Canvas sent with a response, and that response's own body, so a later
/// `304 Not Modified` can be answered from the cache instead of a fresh fetch (Canvas sends
/// `ETag` + `must-revalidate` on its cacheable GETs). Keyed by the request's own absolute URL
/// (scheme, host, path and query): standard HTTP conditional-request semantics are per-URI, and
/// Canvas's pagination means each page of one endpoint is its own URI with its own entry.
public struct ETagCacheEntry: Codable, Sendable, Equatable {
    public let etag: String
    public let body: Data
    /// The original 200's own `Link` header, if it had one -- a `304` never repeats it (confirmed
    /// live: Canvas's 304 carries only `ETag`), so pagination needs it cached alongside the body
    /// or a cache hit on a page before the last one would stop there, one page short, exactly the
    /// silent-truncation shape item 5 just fixed. `nil` for an unpaginated resource.
    public let linkHeader: String?
    public init(etag: String, body: Data, linkHeader: String? = nil) {
        self.etag = etag; self.body = body; self.linkHeader = linkHeader
    }
}

/// Where `CanvasClient` reads and writes `ETagCacheEntry` values, one per request URL. The
/// production conformance (`TallyStore`'s `SealedETagStore`) keeps every entry in the account's
/// own private store (SEC1-09) -- never the shared App Group container, since this cache holds
/// the same Canvas-derived content the sealed snapshot does, just keyed differently and rebuilt
/// incrementally. `nil` in `CanvasClient`'s own init (the default): no conditional requests, no
/// behaviour change, exactly today's client.
public protocol ETagStore: Sendable {
    func entry(for key: String) async -> ETagCacheEntry?
    func setEntry(_ entry: ETagCacheEntry, for key: String) async
}
