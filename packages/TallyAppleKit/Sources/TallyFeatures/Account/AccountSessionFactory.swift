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
    /// account, for the foreground launch and a background launch alike. `launchRecords`: the
    /// refresh record the launch already read (O5), taken instead of reading the file again.
    @concurrent
    public static func activeCoordinator(_ environment: AccountEnvironment,
                                         launchRecords: LaunchRecordHandoff? = nil) async -> RefreshCoordinator? {
        guard let root = try? environment.storeRoot(),
              let account = AccountDirectoryStore(root: root).activeAccount() else {
            launchRecords?.close() // the first resolution closes the handoff, whatever it finds
            return nil
        }
        return await coordinator(for: account, root: root, environment: environment,
                                 launchRecord: launchRecords?.take(for: account.accountKey))
    }

    /// L5 then L6: the cached snapshot is read, unsealed and decoded **once**, here, and that value
    /// is the coordinator's `initialSnapshot`, which `AccountHomeSource` then hands to the
    /// projector as `committedSnapshot` (perf-app-runtime.md §2.2 rule 1: one decoded snapshot per
    /// generation). The refresh record (O5, PERF-L) is the one the launch read (`launchRecord`), or
    /// else read here alongside the snapshot, reconciled with the snapshot's `fetchedAt`
    /// (`RefreshStateStore.startingRecord`); the coordinator writes it back whenever a run ends, so
    /// the launch refresh obeys `FreshnessRules.shouldStart`. With no record on disk the last
    /// attempt is unknown and the launch refreshes (after the cached paint), as before.
    @concurrent
    static func coordinator(for account: AccountRecord, root: URL, environment: AccountEnvironment,
                            launchRecord: LaunchRecordHandoff.Handed? = nil) async -> RefreshCoordinator {
        let store = environment.snapshotStore(for: account.accountKey, root: root)
        let recordStore = RefreshStateStore(root: root, accountKey: account.accountKey,
                                            sealer: environment.sealer(for: account.accountKey))
        async let persisted = persistedRecord(launchRecord, from: recordStore)
        var initialSnapshot: CanvasSnapshot?
        if case .loaded(let snapshot) = await store.loadSnapshot() {
            initialSnapshot = snapshot
        }
        let record = RefreshStateStore.startingRecord(persisted: await persisted,
                                                      committedDataFetchedAt: initialSnapshot?.fetchedAt)
        let gateway = await gateway(for: account, environment: environment)
        // M3-A (Settings; M2-C2 OI5): the account's own settings, read here with the snapshot, off
        // the main actor: the widget grade opt-in every commit's glance is built with, and the
        // "What changed" thresholds every commit's digest uses.
        let settings = await AccountUserStateAccess.stored(account: account.accountKey, root: root, environment: environment)
        let coordinator = RefreshCoordinator(gateway: gateway, store: store, clock: environment.clock,
                                             initialSnapshot: initialSnapshot, initialRecord: record,
                                             includeGrades: settings.showGradesInGlance, recordStore: recordStore)
        await coordinator.updateDigestThresholds(settings.digestThresholds)
        // M3-C (E07): the account's reminders are planned from the cached snapshot now, and again
        // after every commit, whichever trigger started it (the Home, `.backgroundTask`, the intent).
        await ReminderPipeline.attach(to: coordinator, account: account.accountKey, environment: environment)
        return coordinator
    }

    /// The record the launch handed over, or else the one on disk (`nil` when there is none).
    @concurrent
    private static func persistedRecord(_ handed: LaunchRecordHandoff.Handed?, from store: RefreshStateStore) async -> RefreshRecord? {
        if let handed { return handed.record }
        return store.loadRecord()
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
