import Foundation

/// SEC1-09 (App Group minimisation): a one-time move from the pre-split layout — `accounts.json`
/// and every account file, including the glance, in one root (the App Group container when the
/// entitlement was available, the app's own storage otherwise) — to the split layout, where
/// `accounts.json` and every account file *except* the glance live in `privateRoot` (the app's own
/// Application Support) and only `glance.v1.sealed` stays in `sharedRoot` (the App Group
/// container): the one file the widget actually reads.
///
/// Called once per foreground launch, before anything else opens `accounts.json` or an account
/// store (`LaunchBootstrapper`, step 0, ahead of the fresh-install reconcile: an upgrading install
/// must never be mistaken for one, which would shred every vault key). Idempotent and safe to call
/// every time:
/// - Nothing to do when `privateRoot` and `oldCombinedRoot` are the same directory (the App Group
///   was never configured, so there was never anything to split).
/// - Nothing to do once `privateRoot`'s `accounts.json` exists (already migrated, or a fresh
///   install that never had the old layout).
/// - Nothing to do when the old root has no `accounts.json` either (a fresh install, or a build
///   that only ever had the App Group as its single root with nothing signed in yet).
///
/// Every move is best-effort (`try?`): a failure here must never crash the launch or block it
/// indefinitely — the worst case is that a file is left behind at the old location, which is
/// harmless (dead weight, not a correctness or security problem: the old location is still the
/// app's own sandbox or the same App Group it already had full access to) and the migration is
/// retried, harmlessly, on the next launch.
///
/// SEC2-05: `accounts.json` moves LAST, not first. Every other step here is already safe to
/// re-run (each one re-lists its own directory and only moves what is still there), so the one
/// thing that must never become visible before the rest of the migration has actually finished is
/// `newAccountsJSON` itself — it is the single signal, above, that "this account is fully
/// migrated." Moving it first (the previous ordering) let a process death between it and the
/// per-account file moves leave `UserState`, the ledger and the refresh record stranded at the
/// old root forever: `fileExists(newAccountsJSON)` already read as "done," so no later launch ever
/// resumed the rest, and `ReminderPipeline` silently fell back to defaults (Hide Course Names
/// included) for files it could no longer find. With the move last, an interruption at any earlier
/// point leaves `newAccountsJSON` absent, so the very next launch re-runs this whole function
/// (harmlessly re-doing already-finished steps) and finishes the job.
public enum StoreMigration {
    public static func migrateIfNeeded(privateRoot: URL, oldCombinedRoot: URL) {
        guard privateRoot != oldCombinedRoot else { return }
        let fileManager = FileManager.default
        let newAccountsJSON = privateRoot.appendingPathComponent(AccountDirectoryStore.fileName)
        guard !fileManager.fileExists(atPath: newAccountsJSON.path) else { return }
        let oldAccountsJSON = oldCombinedRoot.appendingPathComponent(AccountDirectoryStore.fileName)
        guard fileManager.fileExists(atPath: oldAccountsJSON.path) else { return }

        try? fileManager.createDirectory(at: privateRoot, withIntermediateDirectories: true)

        // Carry the install sentinel forward: an upgrading install must read as already-reconciled
        // at the new (private) root, never as fresh (`LaunchBootstrapper.reconcileInstallIfNeeded`
        // would otherwise shred every vault key on the very launch that is supposed to migrate them).
        let oldSentinel = oldCombinedRoot.appendingPathComponent(".installed")
        let newSentinel = privateRoot.appendingPathComponent(".installed")
        if fileManager.fileExists(atPath: oldSentinel.path), !fileManager.fileExists(atPath: newSentinel.path) {
            try? fileManager.copyItem(at: oldSentinel, to: newSentinel)
        }

        let oldAccounts = oldCombinedRoot.appendingPathComponent("accounts", isDirectory: true)
        let newAccounts = privateRoot.appendingPathComponent("accounts", isDirectory: true)
        let glanceFileName = StoreLayout.fileName(.glance)
        let entries = (try? fileManager.contentsOfDirectory(atPath: oldAccounts.path)) ?? []
        for name in entries {
            let oldEntry = oldAccounts.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: oldEntry.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                // An account directory: every file moves except the glance, which stays right
                // where it is (already the shared root — the widget's entitlement never moves).
                let newEntry = newAccounts.appendingPathComponent(name, isDirectory: true)
                try? fileManager.createDirectory(at: newEntry, withIntermediateDirectories: true)
                let fileNames = (try? fileManager.contentsOfDirectory(atPath: oldEntry.path)) ?? []
                for fileName in fileNames where fileName != glanceFileName {
                    try? fileManager.moveItem(at: oldEntry.appendingPathComponent(fileName),
                                              to: newEntry.appendingPathComponent(fileName))
                }
            } else {
                // A sibling marker, e.g. a SEC1-08 purge-pending file (never inside an account
                // directory, so it was never a candidate to "stay with the glance" above).
                try? fileManager.createDirectory(at: newAccounts, withIntermediateDirectories: true)
                try? fileManager.moveItem(at: oldEntry, to: newAccounts.appendingPathComponent(name))
            }
        }

        // Last: once this lands, `fileExists(newAccountsJSON)` (above) reads as "fully migrated."
        try? fileManager.moveItem(at: oldAccountsJSON, to: newAccountsJSON)
    }
}
