import Foundation
import TallyCanvasAPI
import TallyDomain
import TallyStore
import TallySync

/// Builds an account's one `RefreshCoordinator` (perf-app-runtime.md §2.4 L5–L6, B2 and S3), off the
/// main actor. `AccountRuntime` owns what this returns, so the foreground Home, `.backgroundTask`
/// and the "Refresh Tally" intent all share it.
public nonisolated enum AccountSessionFactory {
    /// The active account's coordinator, or `nil` when no account is signed in (or the store cannot
    /// be read). `AppEnvironment` makes this `AccountRuntime`'s resolver, so it runs at most once per
    /// account, for the foreground launch and a background launch alike.
    @concurrent
    public static func activeCoordinator(_ environment: AccountEnvironment) async -> RefreshCoordinator? {
        guard let root = try? environment.storeRoot(),
              let account = AccountDirectoryStore(root: root).activeAccount() else { return nil }
        return await coordinator(for: account, root: root, environment: environment)
    }

    /// L5 then L6: the cached snapshot is read, unsealed and decoded **once**, here, and that value
    /// is the coordinator's `initialSnapshot`, which `AccountHomeSource` then hands to the
    /// projector as `committedSnapshot` (perf-app-runtime.md §2.2 rule 1: one decoded snapshot per
    /// generation). The refresh record starts from the snapshot's `fetchedAt`: no `refresh-state`
    /// file exists yet (perf-app-runtime.md §8), so the last *attempt* is unknown and the launch
    /// refresh always runs (after the cached paint).
    @concurrent
    static func coordinator(for account: AccountRecord, root: URL, environment: AccountEnvironment) async -> RefreshCoordinator {
        let store = environment.snapshotStore(for: account.accountKey, root: root)
        var initialSnapshot: CanvasSnapshot?
        var record = RefreshRecord()
        if case .loaded(let snapshot) = await store.loadSnapshot() {
            initialSnapshot = snapshot
            record.succeeded(dataFetchedAt: snapshot.fetchedAt)
        }
        let gateway = await gateway(for: account, environment: environment)
        // M3-A (Settings; M2-C2 OI5): the account's own settings, read here with the snapshot, off
        // the main actor: the widget grade opt-in every commit's glance is built with, and the
        // "What changed" thresholds every commit's digest uses.
        let settings = await AccountUserStateAccess.stored(account: account.accountKey, root: root, environment: environment)
        let coordinator = RefreshCoordinator(gateway: gateway, store: store, clock: environment.clock,
                                             initialSnapshot: initialSnapshot, initialRecord: record,
                                             includeGrades: settings.showGradesInGlance)
        await coordinator.updateDigestThresholds(settings.digestThresholds)
        // M3-C (E07): the account's reminders are planned from the cached snapshot now, and again
        // after every commit, whichever trigger started it (the Home, `.backgroundTask`, the intent).
        await ReminderPipeline.attach(to: coordinator, account: account.accountKey, environment: environment)
        return coordinator
    }

    /// Sign-in's S3, after the token exchange (S2): the credential goes to the Keychain, the
    /// account key is derived, `accounts.json` is written atomically, the account's store
    /// directory is prepared, and the account's coordinator is built for the first sync (S5).
    /// A re-sign-in to an account that still has a cached snapshot continues its generations.
    @concurrent
    static func provision(credential: CanvasCredential, target: SignInTarget,
                          environment: AccountEnvironment) async throws -> (AccountRecord, RefreshCoordinator) {
        let root = try environment.storeRoot()
        try await environment.credentialStore.save(credential)
        let record = AccountRecord.derived(credential: credential, target: target)
        try AccountDirectoryStore(root: root).activate(record)
        try await environment.snapshotStore(for: record.accountKey, root: root).prepare()
        return (record, await coordinator(for: record, root: root, environment: environment))
    }

    /// The live gateway: `CanvasClient` over the injected transport, with a `TokenCoordinator`
    /// that refreshes through the institution's token endpoint and saves every rotated credential
    /// to the Keychain before using it (ADR 0001 step 4).
    @concurrent
    static func gateway(for account: AccountRecord, environment: AccountEnvironment) async -> any CanvasGateway {
        if let override = environment.gatewayOverride { return await override(account) }
        let credential = await environment.credentialStore.load()
        let refresher = CanvasTokenRefresher(endpoint: TokenEndpoint(host: account.host, clientID: account.clientID),
                                             transport: environment.transport, clock: environment.clock)
        let tokens = TokenCoordinator(initial: credential, store: environment.credentialStore, refresher: refresher,
                                      clock: environment.clock)
        let client = CanvasClient(host: account.host, transport: environment.transport, tokens: tokens)
        return LiveCanvasGateway(host: account.host, accountKey: account.accountKey, client: client,
                                 logger: environment.logger)
    }
}

extension AccountRecord {
    /// The record sign-in's S3 writes for `credential` at `target`: its account key derives from
    /// the host and the Canvas user ID, so an abandoned sign-in can be purged by it whether or not
    /// its provisioning finished.
    nonisolated static func derived(credential: CanvasCredential, target: SignInTarget) -> AccountRecord {
        .derived(host: credential.host, canvasUserID: credential.userID, clientID: target.clientID,
                 displayLabel: target.schoolDisplayName)
    }
}
