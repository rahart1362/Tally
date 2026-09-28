import TallyDomain
import TallyStore

/// WP-D02: reconciles `ReminderPlanner`'s desired reminder set against the sync ledger and the
/// platform's actual pending set (architecture.md §3.4 post-commit pipeline, step 2). Idempotent:
/// calling `reconcile` again with the same `desired`, against the ledger and platform state it
/// just produced, schedules and cancels nothing, because every decision is keyed by
/// `PendingReminder.id` (`NotificationID.make`, deterministic) and a signature of each id's
/// schedulable fields.
public enum NotificationReconciler {
    /// Reconciles `desired` against `ledger.notifications` and `platform`'s own pending set, and
    /// returns the ledger to persist afterward (the caller — the post-commit pipeline, out of this
    /// worktree's scope — writes it back through `SyncLedgerStore`).
    ///
    /// - **Stale** identifiers — pending on the platform, remembered by the ledger, or both, but no
    ///   longer desired — are cancelled and dropped from the ledger.
    /// - **Missing** identifiers — desired, but not already pending with matching content — are
    ///   scheduled (this also covers a reminder whose *content* changed under the same deterministic
    ///   id, e.g. a due date moving shifts its fire date without changing its id).
    /// - `desired` is defensively re-capped to `cap`, soonest-first, even though `ReminderPlanner`
    ///   already enforces this — the same "each layer re-validates" pattern `SnapshotStore`'s own
    ///   `staleGeneration` backstop uses for `RefreshCoordinator`'s generation guard.
    public static func reconcile(
        desired: [PendingReminder], ledger: SyncLedger, platform: any NotificationScheduling,
        cap: Int = TallyConfig.pendingNotificationCap
    ) async -> SyncLedger {
        let capped = Array(desired.sorted(by: bySoonestThenID).prefix(cap))
        // CS-07: `desired` can repeat an ID. `ReminderPlanner.plan` emits reminders per candidate,
        // so a candidate list that repeats an assignment repeats its reminder IDs, and
        // `Dictionary(uniqueKeysWithValues:)` trapped on that. The first occurrence in the
        // soonest-first order above wins, and each ID is scheduled once.
        let desiredByID = Dictionary(capped.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let pendingOnPlatform = await platform.pendingIdentifiers()
        let managed = Set(ledger.notifications.keys).union(pendingOnPlatform)
        let staleIDs = managed.subtracting(desiredByID.keys)
        if !staleIDs.isEmpty { await platform.cancel(ids: staleIDs) }

        var newNotifications: [String: String] = [:]
        for (id, reminder) in desiredByID {
            let signature = contentSignature(reminder)
            let alreadyCorrect = pendingOnPlatform.contains(id) && ledger.notifications[id] == signature
            if !alreadyCorrect { await platform.schedule(reminder) }
            newNotifications[id] = signature
        }

        var updated = ledger
        updated.notifications = newNotifications
        return updated
    }

    /// A deterministic (never `Hasher`, which is randomly seeded per process and so would never
    /// match a ledger value read back from disk on a later launch) encoding of exactly the fields a
    /// schedule request carries, so an unchanged reminder is never re-registered with the platform,
    /// and a changed one always is.
    static func contentSignature(_ reminder: PendingReminder) -> String {
        "\(reminder.fireDate.timeIntervalSince1970)|\(reminder.interruptionLevel.rawValue)|\(reminder.kind.rawValue)|\(reminder.subjectID)"
    }

    private static func bySoonestThenID(_ a: PendingReminder, _ b: PendingReminder) -> Bool {
        a.fireDate != b.fireDate ? a.fireDate < b.fireDate : a.id < b.id
    }
}
