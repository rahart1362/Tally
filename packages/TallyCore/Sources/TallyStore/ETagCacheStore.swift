import Foundation
import TallyDomain

public enum ETagCacheLoadResult: Equatable, Sendable {
    case loaded([String: ETagCacheEntry])
    /// Never written, or discarded (an old version, or an undecodable blob): start empty.
    case absent
    /// Device locked, or an unclassified I/O error; the file is left as it is.
    case unavailable(VaultDisposition)
}

/// The store side of `etag-cache.sealed` (item 3, LIVE-FIX-2/LIVE-3): the conditional-GET cache
/// `CanvasClient`'s `ETagStore` reads and writes, one entry per request URL. It holds the same
/// Canvas-derived content the sealed snapshot does (just keyed by endpoint instead of by
/// section), so it is sealed with the app key, in the account's own private-store directory
/// (SEC1-09) -- never the shared App Group container, and never a Keychain item (there can be
/// many entries, one per endpoint and page, unlike the one credential `KeychainCredentialStore`
/// holds). Sign-out's purge (`AccountPurger`) deletes it with every other account file; the
/// orphan sweep keeps it (`StoreLayout.allFileNames`).
///
/// Rederivable: a blob that cannot be read or decoded is discarded, and the next request simply
/// gets no `If-None-Match` and a full 200 -- exactly `CanvasClient`'s own behaviour with no
/// `ETagStore` at all. A struct, not an actor, mirroring `RefreshStateStore`: callers that need
/// actor isolation (`SealedETagStore`, the async `ETagStore` adapter) provide their own.
public struct ETagCacheStore: Sendable {
    /// Bumped to 2 (item 3 round 2, PMO review of PR #101): `ETagCacheEntry` gained
    /// `lastUsedAt`, a required field with no meaningful default to migrate an old blob to, so
    /// any version 1 blob is discarded like any other incompatible shape -- rederivable, same as
    /// every other store file.
    public static let currentVersion = 2

    private let layout: StoreLayout
    private let access: SealedFileAccess
    private let isOwner: Bool

    public init(root: URL, accountKey: AccountKey, sealer: any SnapshotSealer, isOwner: Bool = true) {
        layout = StoreLayout(root: root, accountKey: accountKey)
        access = SealedFileAccess(sealer: sealer, isOwner: isOwner)
        self.isOwner = isOwner
    }

    public func load() -> ETagCacheLoadResult {
        let url = layout.url(for: .etagCache)
        switch access.read(.etagCache, at: url) {
        case .absent:
            return .absent
        case .failed(_, let disposition):
            return disposition == .discardAndRebuild ? .absent : .unavailable(disposition)
        case .plaintext(let data):
            guard let stored = try? JSONDecoder().decode(StoredETagCache.self, from: data),
                  stored.version == Self.currentVersion else {
                if isOwner { ProtectedFile.remove(url) }
                return .absent
            }
            return .loaded(stored.entries)
        }
    }

    /// The cached entries, or an empty dictionary whenever `load()` has none to give (absent,
    /// discarded, or unavailable -- `CanvasClient` degrades the same way for all three: no
    /// conditional header this time).
    public func loadEntries() -> [String: ETagCacheEntry] {
        if case .loaded(let entries) = load() { return entries }
        return [:]
    }

    public func save(_ entries: [String: ETagCacheEntry]) throws {
        try ProtectedFile.prepareDirectory(layout.accountDirectory, excludeFromBackup: true)
        let data = try JSONEncoder().encode(StoredETagCache(version: Self.currentVersion, entries: entries))
        try access.write(data, .etagCache, to: layout.url(for: .etagCache), excludeFromBackup: true)
    }
}

/// The file's JSON: a version, then every cached entry.
private struct StoredETagCache: Codable {
    let version: Int
    let entries: [String: ETagCacheEntry]
}

/// The async `ETagStore` (`TallyDomain`) `CanvasClient` actually talks to, backed by
/// `ETagCacheStore`'s synchronous whole-file load/save. An actor so its own in-memory copy
/// cannot race a concurrent `fetchAllPages`/`fetchOne` pair's read-modify-write of the same file
/// (`LiveCanvasGateway`'s assignment-groups loop, and its `async let` optional sections, both
/// call through the one `CanvasClient` that owns this store).
///
/// Item 3 round 2 (PMO review of PR #101, "one write per refresh" and "bound it"): `setEntry`
/// only ever updates the in-memory copy and marks it dirty; `flush()` -- called exactly once per
/// `LiveCanvasGateway.fetchSnapshot`, win or lose -- is the only thing that prunes
/// (`ETagCachePruning`) and writes to disk. Before this, every `ETag`-bearing response in a
/// refresh (12-20 of them) resealed and rewrote the WHOLE file, and nothing ever dropped an
/// entry: the planner/calendar/announcement queries key by a UTC calendar day
/// (`CanvasEndpoints.swift`'s `CanvasDateWindow`), so those entries' URLs -- and so their cache
/// keys -- change every day, and the orphaned previous days' entries just accumulated forever.
public actor SealedETagStore: ETagStore {
    private let store: ETagCacheStore
    private let clock: any DateProviding
    private let maxAge: Duration
    private let maxBytes: Int
    private var cache: [String: ETagCacheEntry]?
    private var isDirty = false

    public init(_ store: ETagCacheStore, clock: any DateProviding = SystemDateProvider(),
               maxAge: Duration = TallyConfig.etagCacheEntryMaxAge, maxBytes: Int = TallyConfig.etagCacheMaxBodyBytes) {
        self.store = store
        self.clock = clock
        self.maxAge = maxAge
        self.maxBytes = maxBytes
    }

    public func entry(for key: String) async -> ETagCacheEntry? {
        loaded()[key]
    }

    public func setEntry(_ entry: ETagCacheEntry, for key: String) async {
        var entries = loaded()
        entries[key] = entry
        cache = entries
        isDirty = true
    }

    public func flush() async {
        guard isDirty, let entries = cache else { isDirty = false; return }
        let pruned = ETagCachePruning.pruned(entries, now: clock.now(), maxAge: maxAge, maxBytes: maxBytes)
        try? store.save(pruned)
        cache = pruned
        isDirty = false
    }

    /// EB-26 ("Erase Saved Data"): empties the in-memory copy without touching disk (the caller,
    /// `AccountPurger.eraseCanvasData`, deletes the file itself) and clears the dirty flag, so a
    /// `flush()` that happens to run afterwards with nothing new written does not resurrect the
    /// erased entries. Setting `cache` to `[:]`, not `nil`, matters: `nil` would make the next
    /// `entry`/`setEntry` call re-read whatever is on disk at that moment, which is safe once the
    /// purge has actually run but not if this lands first (the actual call order in
    /// `RefreshCoordinator.eraseLocalData()`/`AppModel.eraseSavedData()`) -- `[:]` never re-reads.
    public func clear() async {
        cache = [:]
        isDirty = false
    }

    /// Reads the file at most once per `SealedETagStore` instance (one per account's
    /// `CanvasClient`, built fresh each sign-in/launch): every entry after the first came from
    /// this actor's own prior `setEntry`, which already kept `cache` current, so there is never
    /// a reason to re-read a file only this actor ever writes.
    private func loaded() -> [String: ETagCacheEntry] {
        if let cache { return cache }
        let entries = store.loadEntries()
        cache = entries
        return entries
    }
}
