#if DEBUG
import Foundation

/// DEBUG only: how many `CanvasSnapshot` values are alive, per account (plan 06 step 10, plan 07
/// M2-C1 L-3: "no `CanvasSnapshot` is reachable after sign-out, checked by a DEBUG live-instance
/// counter").
///
/// A struct has no deinit, so each snapshot carries one `CanvasSnapshotInstanceToken`. Every way
/// of making a snapshot (the memberwise initialiser and decoding) creates a new token; copying a
/// snapshot copies the reference, never the token, so copies that share storage count once. When
/// the last copy is released the token's deinit decrements the count. A count of zero for an
/// account therefore means no decoded or fetched snapshot of that account is reachable from
/// anywhere in the process.
///
/// Keyed by account because tests run in parallel: a sign-out test uses its own account key and
/// reads only that account's count. Release builds compile none of this.
public enum CanvasSnapshotInstances {
    private static let registry = LiveCounts()

    /// Live snapshot values whose `accountKey` is `account`.
    public static func liveCount(for account: AccountKey) -> Int {
        registry.count(account.rawValue)
    }

    static func created(_ account: String) {
        registry.change(account, by: 1)
    }

    static func released(_ account: String) {
        registry.change(account, by: -1)
    }
}

/// The counts behind `CanvasSnapshotInstances`, behind an `NSLock` (a pthread mutex).
///
/// Not `Synchronization.Mutex`: the toolchain's Synchronization module is not built with
/// ThreadSanitizer instrumentation, so TSan never sees that lock being taken and reported every
/// concurrent count as a data race (`make core-tsan`; CI run 36441894351, 63 reports, all inside
/// the lock's closure). TSan does intercept pthread mutexes.
private final class LiveCounts: @unchecked Sendable {
    // @unchecked: `counts` is read and written only with `lock` held.
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    func count(_ account: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[account, default: 0]
    }

    func change(_ account: String, by delta: Int) {
        lock.lock()
        defer { lock.unlock() }
        let updated = counts[account, default: 0] + delta
        counts[account] = updated > 0 ? updated : nil
    }
}

/// The per-value token behind `CanvasSnapshotInstances`. Immutable, so `Sendable`. It never takes
/// part in equality: two snapshots with equal fields are equal whatever their tokens.
final class CanvasSnapshotInstanceToken: Sendable, Equatable {
    let account: String

    init(account: String) {
        self.account = account
        CanvasSnapshotInstances.created(account)
    }

    deinit {
        CanvasSnapshotInstances.released(account)
    }

    static func == (lhs: CanvasSnapshotInstanceToken, rhs: CanvasSnapshotInstanceToken) -> Bool { true }
}
#endif
