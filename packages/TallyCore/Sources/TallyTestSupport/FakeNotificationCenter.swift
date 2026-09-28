import Synchronization
import TallyDomain
import TallySync

/// Linux/simulator stand-in for `UNUserNotificationCenter` (`TallySync.NotificationScheduling`,
/// architecture.md §3.1 lists this fake under `TallyTestSupport`): tracks pending reminders in
/// memory and counts calls, so `NotificationReconcilerTests` can assert "remove what's stale, add
/// what's missing" and idempotency without touching UserNotifications.
public final class FakeNotificationCenter: NotificationScheduling, Sendable {
    private struct State {
        var pending: [String: PendingReminder] = [:]
        var scheduleCallCount = 0
        var cancelCallCount = 0
    }
    private let state: Mutex<State>

    /// `seeding` models a platform that already has some requests pending (e.g. from a previous
    /// launch), independent of whatever ledger a test hands to the reconciler.
    public init(seeding initial: [PendingReminder] = []) {
        state = Mutex(State(pending: Dictionary(uniqueKeysWithValues: initial.map { ($0.id, $0) })))
    }

    public func pendingIdentifiers() async -> Set<String> { state.withLock { Set($0.pending.keys) } }

    public func schedule(_ reminder: PendingReminder) async {
        state.withLock { $0.pending[reminder.id] = reminder; $0.scheduleCallCount += 1 }
    }

    public func cancel(ids: Set<String>) async {
        state.withLock {
            for id in ids { $0.pending.removeValue(forKey: id) }
            $0.cancelCallCount += 1
        }
    }

    /// Everything currently pending, for test assertions.
    public var pending: [PendingReminder] { state.withLock { Array($0.pending.values) } }
    public var scheduleCallCount: Int { state.withLock { $0.scheduleCallCount } }
    public var cancelCallCount: Int { state.withLock { $0.cancelCallCount } }
}
