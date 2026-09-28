import Foundation
import TallyCanvasAPI
import TallyDomain
import TallyStore
import TallySync

/// Sign-out's step 6 (perf-app-runtime.md §4.3): the purge, off the main actor. TallySync's
/// `SignOutUseCase` does its part in security.md §3.2's order (revoke at Canvas, best effort; retire
/// the coordinator; cancel the account's notifications; crypto-shred its vault keys and delete its
/// store; delete the Keychain credential). Then the account leaves `accounts.json` and the app-lock
/// setting is removed (sign-out and **erase**: security.md §3.3 makes sign-out the way out of a lock
/// with no device passcode, so the lock must not outlive it).
///
/// Idempotent, and never throws: every step is best effort except the local purge, which always
/// runs (`SignOutUseCase`'s contract).
public nonisolated enum AccountSignOut {
    @concurrent
    static func purge(account: AccountRecord, retired coordinator: RefreshCoordinator?, environment: AccountEnvironment) async {
        guard let root = try? environment.storeRoot() else {
            await environment.credentialStore.delete()
            await environment.lockPreferences.reset()
            return
        }
        let sealer = environment.sealer(for: account.accountKey)
        // `SignOutUseCase` bumps the coordinator's epoch again (idempotent) and needs one to exist.
        // When the Home never resolved one (for example, sign-out from the lock screen before any
        // projection), a coordinator over the store that never fetches stands in: it holds no
        // snapshot and is retired at once.
        let coordinator = coordinator ?? RefreshCoordinator(
            gateway: RetiredGateway(), store: SnapshotStore(root: root, accountKey: account.accountKey, sealer: sealer),
            clock: environment.clock, initialSnapshot: nil)
        await SignOutUseCase.signOut(
            accountKey: account.accountKey,
            credentialStore: environment.credentialStore,
            transport: environment.transport,
            tokenEndpoint: TokenEndpoint(host: account.host, clientID: account.clientID),
            refreshCoordinator: coordinator,
            ledgerStore: SyncLedgerStore(root: root, accountKey: account.accountKey, sealer: sealer),
            notifications: environment.notifications,
            storeRoot: root,
            keyring: environment.keyring)
        try? AccountDirectoryStore(root: root).remove(account.accountKey)
        await environment.lockPreferences.reset()
    }
}

/// A gateway for a coordinator that must never fetch (see `AccountSignOut.purge`).
nonisolated struct RetiredGateway: CanvasGateway {
    func fetchSnapshot(previous: CanvasSnapshot?, now: Date) async throws -> CanvasSnapshot {
        throw RefreshFailure.unknown
    }
}
