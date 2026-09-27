import Foundation
import TallySync

/// E04: the composition root's top-level app state (architecture.md §3.1: "`AppModel` and
/// `RefreshStatusModel` (`@MainActor @Observable`), consuming `RefreshCoordinator` events").
///
/// `refreshCoordinator` is `nil` today: there is no signed-in account yet (Onboarding/sign-in —
/// a separate, concurrently-developed work package — has not merged an `AccountDirectory` or any
/// credential store into this branch). That is the real, honest state of the app right now, not
/// a stub: once sign-in exists, whatever constructs the real per-account `RefreshCoordinator`
/// calls `attach(_:)` here, and `.backgroundTask`/`RefreshTallyIntent` (already wired through this
/// type, see `AppEnvironment`/`RefreshIntentBridge`) start doing real work with no further changes
/// to either call site.
@MainActor
@Observable
public final class AppModel {
    public private(set) var refreshCoordinator: RefreshCoordinator?
    public let refreshStatus = RefreshStatusModel()

    public init() {}

    /// Called once a `RefreshCoordinator` exists for the signed-in account (or, transiently, for
    /// sample mode — see `SampleDataModel`, which manages its own coordinator independently
    /// rather than routing through here: sample data must never reach the background task or the
    /// Siri "Refresh Tally" intent, ASC-14's "no network calls in sample mode" guarantee).
    public func attach(_ coordinator: RefreshCoordinator) async {
        refreshCoordinator = coordinator
        await refreshStatus.attach(to: coordinator)
    }

    public func detach() {
        refreshCoordinator = nil
        refreshStatus.detach()
    }
}
