import Foundation
import TallyDomain
import TallySync

/// The signed-in Home's data source (perf-app-runtime.md §2.1): the account's `RefreshCoordinator`,
/// reached through `AccountRuntime`, turned into `HomeUpdate`s.
///
/// Sync hardening makes this a thin adapter with no fan-out of its own (plan 06 §5):
/// - every `updates()` call subscribes with the coordinator's own `events()`, a stream per
///   subscriber whose first element is the current state;
/// - each update carries `committedSnapshot`: the value the coordinator committed, sharing its
///   storage, never decoded again from disk (perf-app-runtime.md §2.2 rule 1);
/// - the stream ends when the coordinator shuts down (sign-out) or is released.
public actor AccountHomeSource: HomeDataSource {
    private let runtime: AccountRuntime

    public init(runtime: AccountRuntime) {
        self.runtime = runtime
    }

    public func updates() async -> AsyncStream<HomeUpdate> {
        let (stream, continuation) = AsyncStream<HomeUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1))
        guard let coordinator = await runtime.coordinator() else {
            // No account: nothing will ever arrive, so the honest state is final.
            continuation.yield(HomeUpdate(generation: 0, snapshot: nil, digest: nil, digestAsOf: nil, freshness: .noCache))
            continuation.finish()
            return stream
        }
        let events = await coordinator.events()
        let forwarding = Task { [weak coordinator] in
            var digest: ChangeDigest?
            var digestAsOf: Date?
            var digestIsNew = false
            for await event in events {
                switch event {
                case .committed(_, let newDigest):
                    if !newDigest.isEmpty {
                        digest = newDigest
                        digestIsNew = true
                    }
                case .stateChanged(let freshness):
                    // Every state change re-reads the committed value (the coordinator emits
                    // `.committed` and then the state, and adopting a newer generation from the
                    // store emits the state alone). `HomeModel` projects each generation once.
                    let snapshot = await coordinator?.committedSnapshot
                    if digestIsNew {
                        digestAsOf = snapshot?.fetchedAt
                        digestIsNew = false
                    }
                    continuation.yield(HomeUpdate(generation: snapshot?.generation ?? 0, snapshot: snapshot,
                                                  digest: digest, digestAsOf: digestAsOf, freshness: freshness))
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in forwarding.cancel() }
        return stream
    }

    public func refresh(_ trigger: RefreshTrigger) async {
        await runtime.coordinator()?.run(trigger: trigger)
    }

    /// Leaving the Home view is not signing out: the runtime keeps the account's coordinator.
    public func end() async {}
}
