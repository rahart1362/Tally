import Foundation
import TallyDomain

/// Item 3 (LIVE-FIX-2/LIVE-3): a plain-JSON, file-backed `ETagStore` for this harness only
/// (`TALLY_LIVE_ETAG_CACHE_FILE`) -- NOT the shipping app's store (that is `TallyStore`'s sealed
/// `SealedETagStore`/`ETagCacheStore`, covered by `TallyStoreTests`; this target has no
/// dependency on `TallyStore` at all). Running `scripts/dev/live-canvas-tests.sh` twice in a row
/// persists the cache across both process invocations, so the second run's live evidence
/// (`LIVE-ETAG`) shows real 304s from Canvas, not an in-memory artifact of one run.
public actor FileETagStore: ETagStore {
    private let url: URL
    private var cache: [String: ETagCacheEntry]?

    public init(path: String) { url = URL(fileURLWithPath: path) }

    public func entry(for key: String) async -> ETagCacheEntry? {
        loaded()[key]
    }

    public func setEntry(_ entry: ETagCacheEntry, for key: String) async {
        var entries = loaded()
        entries[key] = entry
        cache = entries
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func loaded() -> [String: ETagCacheEntry] {
        if let cache { return cache }
        let entries = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: ETagCacheEntry].self, from: $0) } ?? [:]
        cache = entries
        return entries
    }
}
