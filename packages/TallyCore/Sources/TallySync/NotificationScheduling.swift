import TallyDomain

/// `NotificationReconciler`'s only way to reach the platform's real notification center
/// (WP-D02, architecture.md §3.4's post-commit pipeline step 2: "Compare desired with the ledger
/// and pendingNotificationRequests, then remove what is stale and add what is missing"). The
/// production conformance (`UNNotificationScheduler`, `TallyPlatform`) is out of this worktree's
/// scope; `FakeNotificationCenter` (`TallyTestSupport`) is the one used here and in tests.
public protocol NotificationScheduling: Sendable {
    /// Every identifier Tally currently has pending on the platform right now — the platform's own
    /// source of truth, which can drift from the ledger (e.g. a reminder that already fired).
    func pendingIdentifiers() async -> Set<String>
    /// Schedules one reminder, replacing any existing pending request with the same identifier
    /// (matching `UNUserNotificationCenter.add(_:)`'s own same-identifier replace behaviour).
    func schedule(_ reminder: PendingReminder) async
    /// Cancels every one of these identifiers. A no-op, per id, for one that is not pending.
    func cancel(ids: Set<String>) async
}
