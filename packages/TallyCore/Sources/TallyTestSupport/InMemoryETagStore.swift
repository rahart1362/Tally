import Synchronization
import TallyDomain

/// Item 3 (LIVE-FIX-2/LIVE-3): an in-memory `ETagStore`, for tests that only need the
/// conditional-request behaviour, not a real persisted cache (`TallyStoreTests` exercises the
/// real, file-backed `SealedETagStore` separately).
public final class InMemoryETagStore: ETagStore {
    private let entries: Mutex<[String: ETagCacheEntry]>
    public init(_ seed: [String: ETagCacheEntry] = [:]) { entries = Mutex(seed) }

    public func entry(for key: String) async -> ETagCacheEntry? { entries.withLock { $0[key] } }
    public func setEntry(_ entry: ETagCacheEntry, for key: String) async { entries.withLock { $0[key] = entry } }

    /// Tests: every entry currently cached, for an assertion on what got stored.
    public var all: [String: ETagCacheEntry] { entries.withLock { $0 } }
}
