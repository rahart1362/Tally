import Foundation
import TallyDomain
import TallySync

/// UX-WP-06 + E04: the one `@Observable` that drives the freshness breadcrumb, "last refreshed"
/// footer and refresh button for a signed-in account (architecture.md §3.1: "A single
/// `RefreshStatusModel` consumes `RefreshCoordinator.events`"). Owns no I/O of its own — it only
/// mirrors whatever `RefreshCoordinator` it is attached to.
///
/// perf-app-runtime.md §7 step 7: it subscribes through `RefreshCoordinator.events()`, a stream of
/// its own (sync hardening SH-1), whose first element is the coordinator's current state, so there
/// is no separate `currentState` read to race and no backlog to replay. The subscription task is
/// owned by a `TaskBox` (`Sendable`, so no unchecked stored task), and releasing the model cancels
/// it. The task captures only the stream, never the coordinator, and the stream finishes when the
/// coordinator shuts down or is released, so the loop always ends.
@MainActor
@Observable
public final class RefreshStatusModel {
    /// Explicit and nonisolated (plan 06 A2). In this default-`MainActor` module the compiler makes an
    /// implicit deinit main-actor isolated, `@MainActor` on the class or not, and an isolated deinit
    /// (`swift_task_deinitOnExecutor`) aborts iOS 26.0-26.3 runtimes when it runs nested or in a
    /// task-local scope (swiftlang/swift#88036; the floor abort in CI run 36390172728). CI's `nm`
    /// gate keeps isolated deinits out of every shipping binary.
    nonisolated deinit {}

    public private(set) var freshness: FreshnessState = .noCache
    public private(set) var lastDigest: ChangeDigest?
    public private(set) var lastDigestAt: Date?

    private var coordinator: RefreshCoordinator? // MUTATION M7b: strong
    private let subscription = TaskBox()

    public init() {}

    /// Starts mirroring `coordinator`. Safe to call again, for the same coordinator or another: the
    /// previous subscription ends first, and the new stream starts with the current state.
    public func attach(to coordinator: RefreshCoordinator) async {
        subscription.cancel()
        self.coordinator = coordinator
        let events = await coordinator.events()
        subscription.replace(with: Task { [weak self] in
            for await event in events {
                // A buffered element can still arrive after `detach()` cancelled this task.
                guard !Task.isCancelled else { break }
                self?.handle(event)
            }
        })
    }

    /// Stops mirroring and forgets the coordinator. `AppModel.signOut()` calls this.
    public func detach() {
        subscription.cancel()
        freshness = .noCache // MUTATION M7b: the coordinator is kept
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
}
