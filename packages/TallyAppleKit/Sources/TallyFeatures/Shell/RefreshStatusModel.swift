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
    /// `nonisolated(unsafe)` so the nonisolated `deinit` can cancel it; every write goes through
    /// the `@MainActor` `attach`/`detach`, and `deinit` runs only after the last strong reference is
    /// gone, so no access can race it. perf-app-runtime.md §7 step 7 replaces it with a `TaskBox`.
    ///
    /// Since sync hardening (SH-1) the task captures only this subscriber's own stream, never the
    /// coordinator, and that stream finishes when the coordinator shuts down, signs out or is
    /// released: the loop always ends, and `detach()` then `attach(to:)` on the same coordinator
    /// works (before SH-1, a cancelled consumer killed the one shared stream for good).
    private nonisolated(unsafe) var eventTask: Task<Void, Never>?

    public init() {}

    /// Starts mirroring `coordinator` through a stream of its own (`events()`, sync hardening
    /// SH-1), whose first element is the coordinator's current state: no separate `currentState`
    /// read, so no stale replay after it (perf-app-runtime.md §4.5). Safe to call again, for the
    /// same coordinator or another: the previous subscription ends first.
    public func attach(to coordinator: RefreshCoordinator) async {
        eventTask?.cancel()
        self.coordinator = coordinator
        let events = await coordinator.events()
        eventTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else { break }
                self?.handle(event)
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
