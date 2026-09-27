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
    /// `nonisolated(unsafe)`: `deinit` on a `@MainActor` class runs in a nonisolated context (it
    /// can be torn down from any thread), so it cannot touch a MainActor-isolated stored property
    /// — but cancelling a `Task` is itself thread-safe, so this narrow escape hatch is safe here.
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
