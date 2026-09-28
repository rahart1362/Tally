import Foundation
import TallyDomain
import TallySync

/// The signed-in account's one `RefreshCoordinator` (perf-app-runtime.md §2.1, §7 step 7). The
/// foreground Home (`AccountHomeSource`), `.backgroundTask(.appRefresh)` and the sign-out path all
/// reach the account through this actor, so an account never has two coordinators and
/// single-flight holds across every trigger.
///
/// Construction is pure (`AppEnvironment.live()` builds it). The coordinator is resolved lazily,
/// at most once, from `resolve`; sign-in installs one with `install(_:)`. Until then there is no
/// account, so `backgroundRefresh()` is an honest no-op, exactly as before.
public actor AccountRuntime {
    public typealias Resolver = @Sendable () async -> RefreshCoordinator?

    private let resolve: Resolver
    private var resolution: Task<RefreshCoordinator?, Never>?
    private var installed: RefreshCoordinator?
    /// Bumped by `install(_:)` and `end()`, so a resolution that finishes after either never
    /// installs its (now stale) answer.
    private var epoch: UInt64 = 0

    /// - Parameter resolve: finds the signed-in account's coordinator (the launch bootstrapper,
    ///   perf-app-runtime.md §7 step 8). The default finds none: there is no account store yet.
    public init(resolve: @escaping Resolver = { nil }) {
        self.resolve = resolve
    }

    /// The account's coordinator: the installed one, or the resolver's answer, asked at most once
    /// even when several callers arrive together.
    public func coordinator() async -> RefreshCoordinator? {
        if let installed { return installed }
        let resolving: Task<RefreshCoordinator?, Never>
        if let resolution {
            resolving = resolution
        } else {
            resolving = Task { [resolve] in await resolve() }
            resolution = resolving
        }
        let asked = epoch
        let resolved = await resolving.value
        if installed == nil, epoch == asked { installed = resolved }
        return installed
    }

    /// Sign-in: the new account's coordinator replaces any earlier one.
    public func install(_ coordinator: RefreshCoordinator) {
        epoch &+= 1
        installed = coordinator
        resolution = nil
    }

    /// `.backgroundTask(.appRefresh)`: one run through the account's one coordinator, joining a
    /// run already in flight. The system's cancellation (out of background time) reaches the fetch
    /// (SH-2). A no-op without an account.
    public func backgroundRefresh() async {
        await coordinator()?.run(trigger: .background)
    }

    /// Sign-out (perf-app-runtime.md §4.3 step 5): `bumpEpochAndCancel()` discards any run in
    /// flight, publishes `.noCache` to every subscriber and shuts the coordinator down (its streams
    /// finish, its snapshot is released, later runs never fetch). Then it is forgotten. Idempotent.
    public func end() async {
        epoch &+= 1
        let ending = installed
        installed = nil
        resolution = nil
        await ending?.bumpEpochAndCancel()
    }
}
