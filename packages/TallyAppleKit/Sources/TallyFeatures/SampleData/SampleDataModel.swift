import Foundation
import TallyDomain

/// ASC-14: the main-actor face of a `SampleSession` (perf-app-runtime.md §7 step 5). A thin
/// adapter: it constructs nothing that does I/O, computes no digest, and only assigns the small
/// values a `HomeUpdate` carries. The session actor does the bundle I/O, the replay, the mapping,
/// the rebase and the digest, all off the main actor.
///
/// Sample data never reaches `AppModel`'s `RefreshCoordinator`, the background task or the
/// "Refresh Tally" intent (ASC-14's "no network calls in sample mode").
@MainActor
@Observable
public final class SampleDataModel {
    public enum Phase: Equatable, Sendable {
        /// Created, or loading its first snapshot: the shell shows its skeleton.
        case loading
        case loaded
        /// The first load failed (the bundled fixtures are a packaging bug if this ever happens).
        case failed
    }

    public private(set) var phase: Phase = .loading
    /// Replaced only when a new generation arrives, so an unchanged refresh never touches it.
    public private(set) var snapshot: CanvasSnapshot?
    public private(set) var freshness: FreshnessState = .noCache
    public private(set) var digest: ChangeDigest?
    public private(set) var digestAsOf: Date?

    /// Internal so `LifecycleLeakTests` can hold a weak reference to it.
    let session: SampleSession
    private let subscription = TaskBox()
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var hasStarted = false

    public init(session: SampleSession = SampleSession()) {
        self.session = session
    }

    public var studentDisplayName: String? { snapshot?.profile.shortName ?? snapshot?.profile.name }

    /// Subscribes to the session and loads the first snapshot. Runs once, from the shell's `.task`.
    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        let updates = await session.updates()
        subscription.replace(with: Task { [weak self] in
            for await update in updates {
                self?.apply(update)
            }
        })
        await session.refresh(.launch)
    }

    /// Pull-to-refresh and the refresh button: one single-flight refresh on the session.
    public func refresh() async {
        await session.refresh(.manual)
    }

    /// Ends the subscription and the session: its streams finish and its snapshot is released.
    public func end() async {
        subscription.cancel()
        await session.end()
    }

    private func apply(_ update: HomeUpdate) {
        if update.generation != generation {
            generation = update.generation
            snapshot = update.snapshot
            phase = .loaded
        } else if update.snapshot == nil, case .failed = update.freshness {
            phase = .failed
        }
        freshness = update.freshness
        digest = update.digest
        digestAsOf = update.digestAsOf
    }
}
