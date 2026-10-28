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
    public init(etag: String, body: Data) { self.etag = etag; self.body = body }
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
