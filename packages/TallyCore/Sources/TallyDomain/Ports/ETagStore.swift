import Foundation

/// Item 3 (LIVE-FIX-2/LIVE-3, `docs/pmo/reviews/live1-report.md`): one cached conditional-GET
/// entry -- the `ETag` Canvas sent with a response, and that response's own body, so a later
/// `304 Not Modified` can be answered from the cache instead of a fresh fetch (Canvas sends
/// `ETag` + `must-revalidate` on its cacheable GETs). Keyed by the request's own absolute URL
/// (scheme, host, path and query): standard HTTP conditional-request semantics are per-URI, and
/// Canvas's pagination means each page of one endpoint is its own URI with its own entry.
public struct ETagCacheEntry: Codable, Sendable {
    public let etag: String
    public let body: Data
    /// The original 200's own `Link` header, if it had one -- a `304` never repeats it (confirmed
    /// live: Canvas's 304 carries only `ETag`), so pagination needs it cached alongside the body
    /// or a cache hit on a page before the last one would stop there, one page short, exactly the
    /// silent-truncation shape item 5 just fixed. `nil` for an unpaginated resource.
    public let linkHeader: String?
    /// Item 3 round 2 (PMO review of PR #101): when this entry was last written OR served on a
    /// `304`, from `CanvasClient`'s own injected `wallClock` -- never `Date()` directly, so a
    /// test can pin it. `ETagCachePruning` reads this to decide what survives a flush. Defaults
    /// to `Date()` only for callers (tests, mostly) that do not care about recency at all;
    /// `CanvasClient` always passes an explicit value.
    public let lastUsedAt: Date
    public init(etag: String, body: Data, linkHeader: String? = nil, lastUsedAt: Date = Date()) {
        self.etag = etag; self.body = body; self.linkHeader = linkHeader; self.lastUsedAt = lastUsedAt
    }
}

extension ETagCacheEntry: Equatable {
    /// `lastUsedAt` is recency metadata, not cached content: two entries with the same `etag`,
    /// `body` and `linkHeader` are the same cache entry regardless of when each was last used
    /// (and regardless of clock jitter between two independently-constructed values in a test).
    public static func == (lhs: ETagCacheEntry, rhs: ETagCacheEntry) -> Bool {
        lhs.etag == rhs.etag && lhs.body == rhs.body && lhs.linkHeader == rhs.linkHeader
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
    /// Records `entry` in memory. Implementations must NOT write to disk here (item 3 round 2,
    /// "one write per refresh") -- only `flush()` persists.
    func setEntry(_ entry: ETagCacheEntry, for key: String) async
    /// Persists every change since the last flush, pruned (`ETagCachePruning`) and written in
    /// one go. `LiveCanvasGateway.fetchSnapshot` calls this exactly once per snapshot fetch, on
    /// success AND on failure (a `defer`-shaped guarantee), so one refresh costs at most one
    /// disk write no matter how many endpoints it touched.
    func flush() async
    /// Discards every entry, in memory only -- never touches disk itself. EB-26 ("Erase Saved
    /// Data"): the account's existing, still-live `CanvasClient` is never rebuilt by a purge
    /// (only the files change), so without this, a later `flush()` could write this cache's
    /// stale in-memory entries back to disk, and a later `304` could resurrect Canvas-derived
    /// content the purge had just deleted. `RefreshCoordinator.eraseLocalData()` /
    /// `bumpEpochAndCancel()` call this through `CanvasGateway.clearLocalCaches()`.
    func clear() async
}

/// Item 3 round 2: the pure prune-before-flush policy, factored out so it is directly testable
/// with no store, no actor and no I/O.
public enum ETagCachePruning {
    /// 1. Drops every entry whose `lastUsedAt` is more than `maxAge` before `now` -- regardless
    ///    of the byte budget below, since an entry nobody has used in that long (the classic
    ///    shape: yesterday's planner/calendar/announcement URL, which will never be requested
    ///    again) is never coming back.
    /// 2. If what is left still totals more than `maxBytes`, evicts the least-recently-used
    ///    survivors first until it fits.
    public static func pruned(_ entries: [String: ETagCacheEntry], now: Date, maxAge: Duration, maxBytes: Int)
        -> [String: ETagCacheEntry] {
        var kept = entries.filter { now.timeIntervalSince($0.value.lastUsedAt) <= maxAge.timeInterval }
        var totalBytes = kept.values.reduce(0) { $0 + $1.body.count }
        guard totalBytes > maxBytes else { return kept }
        for (key, entry) in kept.sorted(by: { $0.value.lastUsedAt < $1.value.lastUsedAt }) {
            if totalBytes <= maxBytes { break }
            kept.removeValue(forKey: key)
            totalBytes -= entry.body.count
        }
        return kept
    }
}
