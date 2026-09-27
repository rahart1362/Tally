import Foundation
import TallySync
import TallyDomain

/// UX-WP-06 + E04: the one `@Observable` that drives the freshness breadcrumb, "last refreshed"
/// footer and refresh button everywhere (architecture.md §3.1: "A single `RefreshStatusModel`
/// consumes `RefreshCoordinator.events`"). Owns no I/O of its own — it only mirrors whatever
/// `RefreshCoordinator` it is attached to.
@MainActor
@Observable
public final class RefreshStatusModel {
    public private(set) var freshness: FreshnessState = .noCache
    public private(set) var lastDigest: ChangeDigest?
    public private(set) var lastDigestAt: Date?

    private weak var coordinator: RefreshCoordinator?
    /// `nonisolated(unsafe)`, deliberately kept rather than dropping `deinit`'s cancellation
    /// entirely: `deinit` on a `@MainActor` class always runs in a nonisolated context (teardown
    /// isn't guaranteed to happen on the main actor), so it cannot touch a MainActor-isolated
    /// stored property through the type system's normal isolation checking.
    ///
    /// This is provably race-free, not merely "probably fine": every *write* to `eventTask` goes
    /// through `attach`/`detach`, both `@MainActor`-isolated, so they're already serialized with
    /// each other. `deinit`'s read-then-cancel is the one nonisolated access, and it can only ever
    /// run after the very last strong reference to `self` is gone — by definition, at that point
    /// no `attach`/`detach` call can still be in flight or start later, since both need a live
    /// `self` to be reached at all. There is no window where `deinit` and a MainActor mutation
    /// observe or race the same value.
    ///
    /// Skipping this and just letting the task dangle is not the safer option here: `attach`'s
    /// `Task` closure captures `coordinator` *strongly* (only `self` is weak), which is required
    /// so the loop can keep draining `coordinator.events` after this object might briefly go
    /// unretained elsewhere. `RefreshCoordinator.events` never completes on its own, so an
    /// uncancelled task would keep that actor (and whatever it owns — the gateway, the snapshot
    /// store) alive indefinitely past this object's own deallocation whenever a caller forgets to
    /// call `detach()` first — a real leak, not a cosmetic one. Cancelling here is what makes
    /// `detach()` optional-but-not-load-bearing for correctness, rather than mandatory.
    private nonisolated(unsafe) var eventTask: Task<Void, Never>?

    public init() {}

    /// Starts mirroring `coordinator`'s state and event stream. Safe to call again (e.g. once a
    /// real account replaces sample mode, or vice versa): the previous subscription is torn down
    /// first, and `freshness` resets to whatever `coordinator.currentState` is right now.
    public func attach(to coordinator: RefreshCoordinator) async {
        eventTask?.cancel()
        self.coordinator = coordinator
        freshness = await coordinator.currentState
        eventTask = Task { [weak self] in
            for await event in coordinator.events {
                guard !Task.isCancelled else { break }
                await self?.handle(event)
            }
        }
    }

    public func detach() {
        eventTask?.cancel()
        eventTask = nil
        coordinator = nil
        freshness = .noCache
        lastDigest = nil
        lastDigestAt = nil
    }

    /// Pull-to-refresh and the footer's refresh button both call this (ux-ui.md §3.3: "Both call
    /// the same single-flight refresh").
    public func refresh() async {
        await coordinator?.run(trigger: .manual)
    }

    private func handle(_ event: RefreshCoordinator.Event) {
        switch event {
        case .stateChanged(let state):
            freshness = state
        case .committed(_, let digest):
            guard !digest.isEmpty else { return }
            lastDigest = digest
            lastDigestAt = Date()
        }
    }

    deinit {
        eventTask?.cancel()
    }
}
