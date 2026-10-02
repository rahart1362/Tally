import Foundation
import Synchronization
import TallyDomain

/// PAY-06, M3-B1 O3: the gate a sign-in's coordinator asks. Until that sign-in's first sync has
/// finished (`close()`, at the root switch), a refresh is the free first sync, even over a snapshot an
/// earlier sign-in left behind (a re-sign-in whose purge failed). The app's gate alone counts that
/// snapshot as committed and refuses the run as a later refresh, and the first-sync page would wait
/// for an event that never comes. Every other decision, and every decision after `close()`, is the
/// app's gate's: the account's coordinator keeps this wrapper for the rest of the process, closed.
public nonisolated final class FirstSyncAllowance: EntitlementGating {
    private let base: any EntitlementGating
    private let isOpen = Mutex(true)

    public init(base: any EntitlementGating) {
        self.base = base
    }

    /// The sign-in's first sync finished (or the sign-in was abandoned): from now on a refresh with a
    /// committed snapshot needs the subscription.
    public func close() {
        isOpen.withLock { $0 = false }
    }

    public var isClosed: Bool {
        !isOpen.withLock { $0 }
    }

    public func allowsRefresh(_ trigger: RefreshTrigger, hasCommittedSnapshot: Bool) async -> Bool {
        let firstSync = isOpen.withLock { $0 }
        return await base.allowsRefresh(trigger, hasCommittedSnapshot: firstSync ? false : hasCommittedSnapshot)
    }

    public func allows(_ feature: SubscriptionFeature) async -> Bool {
        await base.allows(feature)
    }

    public func glanceEntitledUntil() async -> Date? {
        await base.glanceEntitledUntil()
    }
}
