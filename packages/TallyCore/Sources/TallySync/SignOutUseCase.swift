import Foundation
import TallyCanvasAPI
import TallyDomain
import TallyStore

/// WP-SEC-06: sign-out / account removal, in the order security.md §3.2 step 9 and this work
/// package specify:
/// 1. Revoke the token, best effort (network trouble or an already-signed-out account never
///    blocks the rest of this sequence), then bump the `RefreshCoordinator`'s epoch and cancel any
///    refresh in flight, so a late result can never land after this point. That also retires the
///    coordinator (`shutdown()`): its subscribers' streams finish, it never fetches again, and it
///    releases its decoded snapshot.
/// 2. Remove every Tally notification this account has pending or the ledger remembers.
/// 3. Crypto-shred the account's vault keys and delete its store files
///    (`AccountPurger.purge`, which itself calls `VaultPurger.purge` — one call covers both halves
///    of this step).
/// 4. Delete the Keychain credential.
///
/// The local purge (steps 2–4) always happens, even when step 1's revoke fails or the device is
/// offline — this is the one non-negotiable half of an otherwise best-effort sequence. Idempotent:
/// calling `signOut` again with nothing left to remove (no credential, an already-empty ledger and
/// platform, an already-purged store) does nothing and never throws.
public enum SignOutUseCase {
    public static func signOut(
        accountKey: AccountKey,
        credentialStore: any CredentialStore,
        transport: any HTTPTransport,
        tokenEndpoint: TokenEndpoint,
        refreshCoordinator: RefreshCoordinator,
        ledgerStore: SyncLedgerStore,
        notifications: any NotificationScheduling,
        storeRoot: URL,
        keyring: VaultKeyring,
        now: Date = Date(),
        logger: any TallyLogger = NoOpLogger()
    ) async {
        // 1. Revoke (best effort), then bump the epoch and cancel any refresh in flight. SEC1-02:
        // an access token that has already expired gets rejected by Canvas, which would otherwise
        // leave the refresh token valid (and listed under Approved Integrations) at Canvas until
        // it lapses on its own — so refresh once first when needed (security.md §3.2 step 9.1).
        // Basic variant: the refreshed credential is used for the revoke call only, never saved —
        // the credential is deleted a few lines below regardless — and nothing is told to the user.
        if let credential = await credentialStore.load() {
            let revocable: CanvasCredential
            if credential.isAccessTokenUsable(now: now) {
                revocable = credential
            } else {
                revocable = await Self.refreshedForRevoke(credential, transport: transport, tokenEndpoint: tokenEndpoint, now: now)
                    ?? credential
            }
            let response = try? await transport.send(tokenEndpoint.revokeRequest(for: revocable))
            logger.log(.signOutRevoked(ok: response.map { (200..<300).contains($0.status) } ?? false))
        }
        await refreshCoordinator.bumpEpochAndCancel()

        // 2. Remove every Tally notification for this account: whatever the ledger remembers,
        // unioned with whatever the platform actually still has pending (the same "trust both,
        // union them" rule `NotificationReconciler` uses for stale detection).
        let ledger: SyncLedger
        switch await ledgerStore.load() {
        case .loaded(let loaded): ledger = loaded
        case .absent, .unavailable: ledger = SyncLedger()
        }
        let pendingOnPlatform = await notifications.pendingIdentifiers()
        let idsToRemove = Set(ledger.notifications.keys).union(pendingOnPlatform)
        if !idsToRemove.isEmpty { await notifications.cancel(ids: idsToRemove) }

        // 3. Crypto-shred the vault keys and delete the account's store files (snapshot, glance,
        // user-state and the ledger all live in the one directory this removes).
        try? AccountPurger.purge(accountKey: accountKey, root: storeRoot, keyring: keyring)

        // 4. Delete the Keychain credential.
        await credentialStore.delete()
    }

    /// SEC1-02's one refresh attempt before revoking an expired access token. Best effort and
    /// silent on any failure — the caller falls back to revoking with the token it already has
    /// (still better than skipping the revoke call entirely).
    private static func refreshedForRevoke(_ credential: CanvasCredential, transport: any HTTPTransport,
                                           tokenEndpoint: TokenEndpoint, now: Date) async -> CanvasCredential? {
        guard let response = try? await transport.send(tokenEndpoint.request(for: .refresh(refreshToken: credential.refreshToken))),
              let refreshed = try? tokenEndpoint.credential(from: response, previous: credential, now: now)
        else { return nil }
        return refreshed
    }
}
