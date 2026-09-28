import Foundation
import TallyDomain
import TallySync

/// Sign-in's first sync (perf-app-runtime.md §2.4 S4–S7) as `FirstSyncPublishing`, over the new
/// account's `RefreshCoordinator`. Every `events()` call is a new stream (S4: "a new stream per
/// `events()`, finished on `.finished`/`.failed`"):
/// 1. `prepare` provisions the account (S3) the first time, and returns its coordinator: the same
///    one on a Retry, never a second one;
/// 2. the stream subscribes to the coordinator's own `events()`, **then** starts `run(.manual)`
///    (S5), so the first commit can never be missed; the subscription's first element (the state
///    before this attempt, a previous failure on a Retry) is skipped;
/// 3. `.committed` (S6: snapshot and glance written atomically) completes every phase and
///    `.finished`; a failure state reports `.failed` with its reason. Nothing is committed on a
///    failure: the required sections are all-or-nothing (architecture.md §3.2).
///
/// Per-phase progress needs phase events from `RefreshCoordinator` (ux-ui.md §6, cross-lane with
/// TallySync), which it does not publish yet, so the four phases complete together at the commit
/// rather than being fabricated one by one.
///
/// When the stream ends early (the page went away), its run is cancelled; with no other caller
/// waiting, the coordinator abandons the fetch (SH-2).
public nonisolated struct CoordinatorFirstSyncPublisher: FirstSyncPublishing {
    private let prepare: @Sendable () async -> RefreshCoordinator?

    /// - Parameter prepare: provisions the account (once) and returns its coordinator, or `nil`
    ///   when provisioning failed (the page then shows the failure, with Retry).
    public init(prepare: @escaping @Sendable () async -> RefreshCoordinator?) {
        self.prepare = prepare
    }

    public func events() -> AsyncStream<FirstSyncEvent> {
        let (stream, continuation) = AsyncStream<FirstSyncEvent>.makeStream()
        let prepare = self.prepare
        let work = Task {
            guard let coordinator = await prepare() else {
                continuation.yield(.failed(.unknown))
                continuation.finish()
                return
            }
            let events = await coordinator.events()
            var iterator = events.makeAsyncIterator()
            // SH-1: a subscription's first element is the coordinator's state *before* this run
            // (after a failed attempt, that failure), so it can never end this attempt.
            _ = await iterator.next()
            let run = Task { await coordinator.run(trigger: .manual) }
            while let event = await iterator.next() {
                guard !Task.isCancelled else { break }
                switch event {
                case .committed:
                    for phase in FirstSyncPhase.allCases { continuation.yield(.phaseCompleted(phase)) }
                    continuation.yield(.finished)
                    continuation.finish()
                    return
                case .stateChanged(let state):
                    if let failure = Self.failure(in: state) {
                        continuation.yield(.failed(failure))
                        continuation.finish()
                        return
                    }
                }
            }
            // Cancelled (the page went away), or the coordinator shut down (the sign-in was abandoned).
            run.cancel()
            if !Task.isCancelled { continuation.yield(.failed(.unknown)) }
            continuation.finish()
        }
        continuation.onTermination = { _ in work.cancel() }
        return stream
    }

    /// The states that end a first sync unsuccessfully. `.noCache` (the state before the run
    /// starts), `.refreshing` and `.delayed` (still running; the page's own 10 s notice covers a
    /// slow first sync) do not.
    static func failure(in state: FreshnessState) -> RefreshFailure? {
        switch state {
        case .failed(let failure, _): failure
        case .offline: .offline
        case .authExpired: .authExpired
        case .noCache, .fresh, .refreshing, .delayed: nil
        }
    }
}
