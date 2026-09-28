import Foundation
import TallyDomain

/// One published state of a Home data source (perf-app-runtime.md §2.1). The snapshot is the
/// source's own value (copy-on-write storage, shared, never decoded again); `generation` goes up
/// with every new snapshot, so a consumer can drop work built from an older one.
public nonisolated struct HomeUpdate: Sendable {
    public let generation: UInt64
    public let snapshot: CanvasSnapshot?
    public let digest: ChangeDigest?
    public let digestAsOf: Date?
    public let freshness: FreshnessState

    public init(generation: UInt64, snapshot: CanvasSnapshot?, digest: ChangeDigest?, digestAsOf: Date?,
                freshness: FreshnessState) {
        self.generation = generation
        self.snapshot = snapshot
        self.digest = digest
        self.digestAsOf = digestAsOf
        self.freshness = freshness
    }
}

/// What the Home shell reads from (perf-app-runtime.md §2.1): sample data today
/// (`SampleSession`), a signed-in account's session later. Conformers are actors, so every fetch,
/// mapping and digest runs off the main actor.
public nonisolated protocol HomeDataSource: Sendable {
    /// A new, independent stream per call, buffering only the newest update. Its first element is
    /// the current state; `end()` finishes it.
    func updates() async -> AsyncStream<HomeUpdate>
    /// Starts a refresh, or joins the one in flight; returns when it has settled.
    func refresh(_ trigger: RefreshTrigger) async
    /// Cancels work in flight, finishes every stream and releases the snapshot. Idempotent.
    func end() async
}
