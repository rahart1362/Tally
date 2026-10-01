# Cryptography & Data Protection Review — Tally

Author: Cryptography & Data Protection Engineer. Date: 2026-09-26. Branch `pmo/assessment` (local only).
Builds on `docs/pmo/00-baseline-audit.md` and aligns with `reviews/architecture.md` (persistence contract `SnapshotSealer`, §3.2), `reviews/security.md` (token class D3, sign-out WP-SEC-06) and `reviews/app-store-compliance.md` (D10, R9, R11).
Lane: data at rest, i.e. protection classes, app-layer encryption, key management, purge and crypto-shred, the store/crypto interface and export compliance. OAuth, token lifecycle, network threats and logging belong to Security and appear here only as cross-lane notes.

**Spec package:** the implementable spec (sources + tests + vector script + test log) is at `docs/pmo/encryption-spec/`. The PMO directed this location because the scratchpad is temporary. Source code under `packages/` and `apps/` was not modified.

## 1. Executive summary

- **Critical: two current choices lock the data at exactly the moment the app needs it.** The first is `.completeFileProtection` (`CacheManager.swift:22`), whose class key is discarded 10 s after lock. The second is `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (`TallySecurity.swift:29`), combined with a Keychain read that returns `nil` for *every* failure, including "device locked" (`:49-55`). Background refresh and widget timelines run while the phone is locked, so they would fail, and a "no key → start over" rule would destroy data. **Fix:** every store file uses `CompleteUntilFirstUserAuthentication`. Every key and token uses `AfterFirstUnlockThisDeviceOnly`. "Locked" is a distinct error that never deletes or re-keys. With these classes, Architecture's "deferred commit" fallback is not needed.
- **Verdict on app-layer encryption: build it, keep it thin, and be honest about what it buys.** On the device it adds essentially nothing, because the key must be readable whenever the file is readable (after first unlock). That covers a stolen locked phone that has already been unlocked once since boot, an unlocked seized phone, an after-first-unlock forensic image, and malware on a jailbroken device. Off the device it adds real protection:
  - Apple says unencrypted Finder backups hold files "not encrypted regardless of their Data Protection class".
  - Apple says `isExcludedFromBackup` "is not a mechanism to guarantee" exclusion.
  - An AES-GCM envelope with a `ThisDeviceOnly` key makes every copy that leaves the device undecryptable.
  - It also gives crypto-shred on sign-out, cryptographic app/widget separation inside a shared App Group, and tamper/torn-write detection.
  - Cost: about 310 lines of Swift (plus a 90-line Keychain adapter), no dependency, and no export paperwork.
- **Export compliance: Apple OS crypto only means no documents.** That covers HTTPS, Data Protection, Keychain and CryptoKit `AES.GCM`. App Store Connect's own table reads "No documentation required". `ITSAppUsesNonExemptEncryption = NO` (`Info.plist:27-28`) stays correct, and no French declaration is needed. As I read 15 CFR 740.17(e)(3) (not legal advice), the annual self-classification report covers mass-market *components* and non-mass-market items, not an end-user app. **SQLCipher is rejected:** it is non-OS crypto, needs a French declaration, and needs its own classification filings. This agrees with Compliance D10(a).
- **The copies outside any envelope are the bigger leak.** They include `URLSession.shared`'s on-disk cache (`CanvasAPIClient.swift:8`; Security SEC-08 owns the fix), notification bodies, Spotlight/App Intents donations, EventKit events, app-switcher snapshots and `UserDefaults`. Today "Clear Cache" only prints (`SettingsView.swift:272`), and sign-out deletes one Keychain item (`:277-281`). The purge API in this spec shreds keys *first*. The caller must also clear every copy outside the vault.
- **Premise correction: the Secure Enclave is no longer P-256-only.** iOS 26 CryptoKit adds `SecureEnclave.MLKEM768/1024` and `MLDSA65/87`. Enclave keys are still asymmetric only, so it plays no role in v1. The one design that would protect an *unlocked* seized phone seals to an Enclave P-256 key behind user presence (HPKE). It is deferred (D-E5).
- **Deliverable status:**
  - `TallyVault` conforms to Architecture's `SnapshotSealer`. It contains the blob format v1, the per-account keyring, file dispositions, atomic protected writes, purge and the reinstall reconcile.
  - **20 XCTest tests pass** with Swift 6.4 on Linux (rootless podman, network off, 0 warnings).
  - The vectors were cross-checked against python-cryptography (OpenSSL) and GCM spec Test Case 16.
  - Tests were mutation-checked, i.e. deliberately broken code was confirmed to fail them.
  - The Keychain adapter and the protection-class behaviour still need macOS CI and device verification.

## 2. Findings

| ID | Severity | Evidence | Impact |
|---|---|---|---|
| ENC-01 | Critical | `CacheManager.swift:22` writes with `.completeFileProtection`. Apple: the Complete class key is discarded "10 seconds" after lock (Platform Security, p.92). Apple: "If your app supports background capabilities… assign a different protection level for files that you might access while in the background" (Encrypting Your App's Files). | Background refresh cannot read the previous snapshot while locked, so it cannot build the change digest or evaluate threshold alerts. It cannot write a new snapshot either, and the widget cannot read. A third-party field report (vibecoach PR #359) shows the typical follow-on bug: a locked background launch was treated as corruption and the store was deleted. |
| ENC-02 | Critical | `TallySecurity.swift:29` uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. `:49-55` returns `nil` for any `OSStatus`, so `errSecInteractionNotAllowed` (-25308) looks like "no item" (DTS, forum 78372). This overlaps Security SEC-06; the token class is theirs (D3). | Locked-time code decides the user is signed out. The same pattern applied to a *vault key* would mint a new key or discard data. This spec separates "locked" from "absent" (`VaultError.protectedDataUnavailable` → `.retryAfterUnlock`). |
| ENC-03 | Major | `CacheManager.swift:22` writes without `.atomic`. The cache is one file per arbitrary key (`:19-23`), and nothing checks integrity (`:25-30`). | A crash mid-write leaves a torn file. A multi-file refresh cannot be swapped atomically, and a partial file only shows up as a JSON decode error or a silently short dataset. This breaks the "atomically replaces the prior cache" non-negotiable. |
| ENC-04 | Major | The cache is in `Library/Caches` (`CacheManager.swift:14-15`). Apple: the system "periodically purges these directories… Don't use these directories to exclude nonpurgeable data from iCloud Backup". Same as ARC-10. | The offline and launch-from-cache promise fails after a storage-pressure purge. Moving the cache to Application Support (required) makes it backup-eligible, which leads to ENC-05. |
| ENC-05 | Major | There is no app-layer envelope and no backup exclusion, although the kit requires an "encrypted local cache" (kit 09 §Non-Negotiables; 14 §Constraints). Apple: for unencrypted Finder backups "the files aren't encrypted regardless of their Data Protection class" (p.94). Apple: `isExcludedFromBackup` is "not a mechanism to guarantee those items never appear in a backup". iCloud Backup stores app data with Apple-held keys unless Advanced Data Protection is on (p.136). | Once relocated, grades, assignment titles and instructor names could end up in plaintext on a family PC, or in an iCloud Backup that Apple can decrypt. Data Protection alone cannot stop this. |
| ENC-06 | Major | "Clear Cache" is `print` only (`SettingsView.swift:271-273`). Sign-out deletes one Keychain item (`:277-281`). Metadata lives in `UserDefaults.standard` (`CacheMetadataManager.swift:17-18`) and is never cleared. Same as ARC-17, SEC-07 and ASC-F13. | Canvas data outlives the session, so kit 09's "cache purge" and ASC R9 are unmet. There is no crypto-shred, so correctness depends on every file deletion succeeding. |
| ENC-07 | Major | `CanvasAPIClient.swift:8` defaults to `URLSession.shared`. Apple: responses are written to the disk cache when the status is 2xx, the cache policy allows it, the headers allow it and the body is under about 5% of the cache. Notification, Spotlight and calendar copies are similar. Security owns the network fix (SEC-08, WP-SEC-08). | Raw Canvas JSON can persist outside the sealed store. It isn't replaced atomically, isn't enveloped and isn't purged, which defeats this lane's guarantees. |
| ENC-08 | Major | Architecture says "No Keychain access group is needed, because the widget never holds tokens" (`architecture.md:113`). It also excludes and seals `user-state` (`:128-135`). | A sealed `glance` needs its key readable by the widget, so an App Group Keychain access group *is* required (for the glance key only, never tokens). Sealing `user-state` with a device-only key, or excluding it from backup, loses user-authored rules on every new phone. Apple: iCloud Backup restores the local keychain "only to the same device" (p.137). See D-E4. |
| ENC-09 | Minor | Cache has 7-day age eviction and a 50 MB oldest-first cap (`CacheManager.swift:7-11,38-78`). Keys are free strings joined onto the path (`:21,26,34`). | This contradicts "latest replaces prior". A key like `../x` escapes the directory. The fixed `StoreFile` enum removes both problems. |
| ENC-10 | Minor | Settings shows "All cached data is encrypted at rest" with a green tick (`SettingsView.swift:131`), yet nothing is cached (baseline). Same as SEC-11 and ASC-F21 context. | The claim must come back only when WP-ENC-01..05 land. Its wording must match the verdict: it protects copies off the device and survives sign-out, and does **not** mean "safe if your unlocked phone is taken". |
| ENC-11 | Minor | `CanvasOAuthManager.swift:3,28` imports CryptoKit (Apple-only). `:19` ignores the `SecRandomCopyBytes` status (SEC-04). | This module can't compile on Linux. Fix it with the same conditional import used here (swift-crypto, Linux only). Security owns the RNG check. |
| ENC-12 | Minor | `ITSAppUsesNonExemptEncryption=false` (`Info.plist:27-28`) is correct for this design, but nothing enforces it. | A future dependency with bundled crypto (e.g. SQLCipher, or an SDK that vendors BoringSSL) would make the plist value a false declaration without anyone noticing. WP-ENC-07 adds the gate. |
| ENC-13 | Minor (info) | The brief's premise says "Secure Enclave holds only P-256 keys". Apple docs list `SecureEnclave.P256`, `MLKEM768`, `MLKEM1024`, `MLDSA65`, `MLDSA87` (iOS 26.0). | No v1 impact. Enclave keys remain asymmetric only, so any use would still be key agreement or encapsulation. |

## 3. Target design

### 3.1 Verdict: what app-layer encryption actually buys

Data Protection already encrypts every file with a per-file AES-XTS key wrapped by a class key (Platform Security p.90). The question is whether a CryptoKit envelope adds anything. The key's accessibility class has to match the file's (`AfterFirstUnlock`), because background refresh and the widget must decrypt while the phone is locked.

| Threat | What Data Protection (CUFA file + AFU Keychain) already gives | What the AES-GCM envelope adds | Residual / real control |
|---|---|---|---|
| Lost/stolen phone, powered off or rebooted (BFU) | Everything is cryptographically locked: CUFA class keys don't exist until the passcode is entered. | Nothing. | Passcode strength. |
| Lost/stolen phone, locked but unlocked once since boot (AFU) | CUFA files and AFU Keychain items are available to the running OS. Reading them needs an OS exploit. iOS 18.1+ **Automatic Restart** moves a long-locked phone back to BFU (p.97; Apple does not state the duration). | **Nothing:** the key has the same class as the file. | Only Complete-class storage (D-E2 b/c) or an Enclave key behind user presence (D-E5) would help, and both break background refresh or the widget. |
| Unlocked seized phone / passcode known | Nothing: the data is readable through the UI and via extraction. | Nothing. | The app lock (Security WP-SEC-07) is a UI barrier. Only D-E5 is cryptographic. |
| iCloud Backup | CUFA files are backed up while locked and stored "encrypted using account-based keys" that Apple holds unless ADP is on (p.136). | **Real:** the blob is ciphertext, and the `ThisDeviceOnly` key restores only to the same device (p.137). | Also set `isExcludedFromBackup` (it's guidance only). |
| Finder backup, unencrypted | **None:** "files aren't encrypted regardless of their Data Protection class" (p.94). | **Real:** ciphertext on the PC, and the key stays wrapped by the device UID. | — |
| Finder backup, encrypted | Files are re-encrypted under the backup password (PBKDF2, 10M rounds, brute-forceable offline, p.94). | **Real:** `ThisDeviceOnly` items stay UID-wrapped, so even the password holder gets ciphertext. | — |
| Forensic image, BFU | Fully protected. | Nothing. | — |
| Forensic image, AFU full filesystem (exploit) | CUFA files are readable; Complete files are not (if locked for more than 10 s). | Nothing: AFU Keychain items are extracted too. | Same as the AFU row. |
| Forensic, logical/backup-protocol extraction | Same as the Finder backup rows. | **Real.** | — |
| Shared iPad | Each user has an APFS volume protected by their credential and a local keychain (p.242-243); other students can't read. | Marginal. Per p.243 user data syncs to iCloud; a blob that follows the user to another iPad fails with `keyMissing`, and the app re-fetches. The interaction between Shared iPad sync and `isExcludedFromBackup` is **UNVERIFIED**. | — |
| Malware on a jailbroken device | Complete-class files only while locked. | Nothing: the malware can call the Keychain as the app or read memory. | Out of scope. Jailbreak detection is not a reliable control (Security). |
| Developer error: a copy written elsewhere, with no class, or to a backed-up path | Depends on each call site. | **Real in practice:** one choke point (`ProtectedFile` + `VaultSealer`) plus a CI lint (WP-ENC-07). | Copies outside our process still need the purge list (§3.7). |
| Widget process reading app-only data in the shared App Group | None: same container, same class. | **Real:** the snapshot key lives in the app's *private* access group, so the widget can open `glance` only. | — |
| Corruption / torn write / bit rot | None. | **Real:** the GCM tag detects it, and the file is discarded and re-fetched. | — |
| Sign-out / purge | File deletion (per-file keys discarded with the metadata). | **Real:** deleting 32 bytes makes every copy (backups, stray temp files) undecryptable. Secure-deletion semantics of deleted Keychain rows are **UNVERIFIED**; accepted residual. | — |

**Recommendation (D-E1 b):** a Data Protection class for every file plus a thin CryptoKit AES-GCM envelope. It is *not* marketed as theft protection.

### 3.2 Protection class and location per artefact

Architecture's layout (`architecture.md:128-135`) is kept. The changes are marked ▲.

| Artefact | Location | File / Keychain class | Sealed with | Backup | Who can decrypt |
|---|---|---|---|---|---|
| Canvas credential (access + refresh token) — **Security owns** | Keychain, app-private group | `AfterFirstUnlockThisDeviceOnly`, not synchronizable (Security D3, agreed) | — | UID-bound, doesn't migrate | App only |
| Vault key, app audience, one per account | Keychain, **app-private** access group `<TEAMID>.<bundleID>` | `AfterFirstUnlockThisDeviceOnly`, not synchronizable | — | doesn't migrate | App only |
| Vault key, widget audience, one per account ▲ | Keychain, **App Group** access group `group.<prefix>.tally` | `AfterFirstUnlockThisDeviceOnly`, not synchronizable | — | doesn't migrate | App + widget |
| `snapshot.v1.sealed` | ▲ recommended: app container `Library/Application Support/<bundleID>/accounts/<acct>/` (least privilege). Staying in the App Group is acceptable because the key enforces separation. | `CompleteUntilFirstUserAuthentication` (CUFA) | app key | excluded (dir + file, re-applied each save) | App |
| `glance.v1.sealed` (widget projection) | App Group `Library/Application Support/Tally/accounts/<acct>/` | CUFA | **widget** key | excluded | App + widget |
| `sync-ledger.sealed` | with the snapshot | CUFA | app key | excluded (EventKit/notification IDs are device-specific) | App |
| `user-state` | with the snapshot | CUFA | **D-E4:** recommended *not sealed*, content restricted (§3.3) | **▲ backed up** (recommended) | App |
| `refresh-state.json`, `accounts.json` | App Group | CUFA | not sealed; **no student content** (`displayLabel` must not be a name) | excluded | App + widget |
| Install sentinel `.installed` | app container | CUFA | — | excluded | App |
| Entitlement record (PAY-04, M3-B1): an expiry per role and the time it was verified, never a receipt or a transaction ID | Keychain, app-private group (`<bundleID>.entitlement`) | `AfterFirstUnlockThisDeviceOnly`, not synchronizable | — | doesn't migrate | App (the glance mirrors the expiry for the widget, §3.3) |
| `UserDefaults` | system | system default | — | backed up | Only non-Canvas preferences (toggles, quiet hours). The app-lock flag moves to Keychain (SEC-15). |
| Logs | unified log (system) — **Security owns** | n/a | — | n/a | No file logs in the container. A user-exported diagnostic goes to `tmp/`, Complete class, and is deleted after sharing. |
| Transient files (PDF export, QuickLook attachments) | `tmp/<uuid>` | `complete` (foreground only) | — | tmp is not backed up | Delete after use; sweep `tmp/` at launch. |
| HTTP cache / cookies | none: `URLSessionConfiguration.ephemeral`, `urlCache = nil` (Security WP-SEC-08) | — | — | — | — |
| Notifications, Spotlight/App Intents, EventKit, app-switcher snapshot | system stores outside our container | not under our control | — | — | Minimise content (Security WP-SEC-10/11) and purge (§3.7). |

**Why CUFA and not `CompleteUnlessOpen`:**
- `CompleteUnlessOpen` lets a locked phone *create* a file, but an existing file cannot be reopened until unlock (Apple: "You can open existing files only when the device is unlocked").
- Background refresh must *read* the previous snapshot (to build the digest and threshold alerts), and the widget must *read* `glance`. Both happen while the phone is locked.
- The field report above shows CUO failing on exactly this path.
- CUO is only right for write-only background artefacts, and Tally has none in v1.

**Why not two tiers** (a full Complete/CUO snapshot plus a minimal CUFA "diff state"):
- The widget's "current grade snapshot" and "due today" must be readable while locked anyway. So the most sensitive fields sit in CUFA whatever we choose.
- The extra tier only protects assignment detail against after-first-unlock forensics, at the cost of the deferred-commit machinery and its failure modes. This is D-E2 (b); not recommended.

**Launch behaviour:** prewarming loads libraries only and runs no app code (About the App Launch Sequence). With CUFA everywhere, the only locked-read case is a pre-first-unlock launch. Apple does not document whether background tasks can run then (**UNVERIFIED**). If they can, those reads return `.retryAfterUnlock` and nothing is deleted.

### 3.3 Widget projection (`glance`) and Lock Screen

- **Content allowlist.** The glance is built only from the snapshot by Architecture WP-C03:
  - `generation`, `asOf`, `gradeSummary` (schema 2; `.notOptedIn`, `.band(GradeBand)`, `.noneYet` or `.notInCanvas`, which replaces the overall grade band), per-course short code plus current grade band, per-course `gradeStatus`, and at most N due items (opaque ID, course code, title truncated to 40 characters, due date, status flags).
  - **Grade values stay opt-in (D-E3):** the overall and per-course bands are present only when the student opted in. `gradeStatus` is a **state**, never a grade or score (whether a course's grades are in Canvas, plan 08 XG-02), so it is stored whether or not the student opted in: the launch paint and the widget must match the full screen. Updated 2026-10-01 with glance schema 2 (PR #15).
  - **`entitledUntil` (PAY-04; M3-B1, 2026-10-01; additive within schema 2).** The expiry of the account's last verified trial or subscription (`EntitlementPolicy`'s `.entitled(until:)`, the Keychain record's), so the widgets and the intents decide access without StoreKit: `GlanceProjection.coversSubscription(at:)` (`EntitlementAccess.covers`) fails closed `SubscriptionConfig.offlineGracePeriod` (3 days) after it, and takes the glance's `asOf` as a time the device has reached, so a clock set back cannot extend access. **An expiry date only: never a receipt, a signed transaction, a transaction ID, a product ID or a price.** Absent means no verified entitlement (never subscribed, lapsed, refunded) or a glance written before the field: locked once enforcement is on. It is not derived from the snapshot: the coordinator's entitlement gate supplies it at every glance write (commit and rewrites), `RefreshCoordinator.entitlementDidChange()` rewrites it when the entitlement changes, and the store's self-heal carries the old value forward. Rationale: the widget cannot reach the app's Keychain item (no shared access group until GL-02), and the date says only that this device's App Store account pays for Tally and until when: App Store metadata, no Canvas content and no grade, sealed with the widget key like the rest of the glance. No new file and no new key.
  - **Never included:** instructor names or emails, comments, announcements, submission content, the user's name, the institution host, tokens, or any purchase data beyond `entitledUntil` (receipts, transaction IDs, prices).
  - A unit test asserts the Codable key set (`GlanceProjectionTests.codableKeySetMatchesTheAllowlistExactly`, with and without `entitledUntil`).
- **Lock Screen.**
  - The user can switch off Lock Screen widget data under "Allow Access When Locked" (p.227).
  - Grade views use `.privacySensitive()`, so WidgetKit redacts them when the user hides sensitive content.
  - D-E3 decides whether grades appear in widgets at all.
- **Widget Data Protection entitlement.** The alternative is to give the widget extension the Data Protection capability (`NSFileProtectionComplete`/`…UnlessOpen`). WidgetKit then shows placeholders until unlock, and "these iOS widgets aren't available as iPhone widgets on Mac" (p.228). This is D-E3 (b).
- **User-state content rule (D-E4 a).** Only user-entered values (rules, targets, quiet hours, manual class times) and opaque Canvas IDs. Never Canvas-derived names, titles or scores. This is enforced by a schema test, because `user-state` is not sealed under D-E4 (a).

### 3.4 Key management

- **Algorithm.** `AES.GCM` with a 256-bit `SymmetricKey`, 96-bit random nonce and 128-bit tag.
  - `ChaChaPoly` is equivalent in CryptoKit and swift-crypto. AES is preferred because the SoC AES engine and CryptoKit are tuned for it; either would pass the same tests.
  - Random-nonce limit: NIST SP 800-38D §8.3 caps a key at 2^32 random-IV invocations. Tally does about 10–100 seals a day per key, so nonce reuse is not a practical risk. That is why there is **no time-based rotation**.
- **Hierarchy.**
  - One key per `(accountKey, audience)`. `audience ∈ {app, widget}` separates the widget from snapshot, ledger and user-state.
  - Per-account keys mean signing out of account A shreds only A (Security D5 / Architecture D3: single active account, storage keyed by account).
  - No KEK/DEK split: blobs are rewritten whole on every refresh, so re-wrapping has no benefit.
- **Keychain item.**
  - `kSecClassGenericPassword`, service `<bundleID>.vault.<audience>`, account `<accountKey>.<keyID>`.
  - `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable=false`.
  - An **explicit** `kSecAttrAccessGroup` on every query. Apple: without a group, "the search matches any of your app's groups".
  - `kSecUseDataProtectionKeychain=true`, which matters only if the iPhone app runs on a Mac.
- **Widget access.**
  - The widget's key store is configured with only the App Group access group. Apple: an App Group ID "can also be used as a Keychain Access Group".
  - It can therefore open `glance` and nothing else: a snapshot open returns `keyMissing` (tested).
  - The widget never creates keys (`mayCreateKeys: false`) and never deletes files (`isOwner: false`). This avoids a race where it deletes a freshly renamed glance.
- **keyID.** A random `UInt32` stored in the authenticated header. A blob from before a purge can therefore never match a newly minted key.
  - Invariant: exactly one key per scope. `VaultKeyring` serialises get-or-create with a lock (tested with 64 concurrent seals). If it finds more than one key, it deletes them all rather than guessing.
- **Rotation.** Happens only on sign-out/purge (shred), account removal and reinstall. The header's keyID and format byte give agility if a future format needs more.
- **Crypto-shred order.** `VaultPurger.purge(account:)` deletes the account's keys **before** deleting its directory. If deletion fails or the app dies in between, what remains is undecryptable (tested by resurrecting an old blob after purge → `keyMissing`).
- **Restore, migration and reinstall.**

| Event | Keys | Files | Result |
|---|---|---|---|
| Same-device restore (iCloud or Finder) | restored (UID-bound) | excluded files absent; any that slipped through are restored | Works, or re-fetch. |
| New device (iCloud Backup, Finder backup, device migration) | `ThisDeviceOnly` never arrive (p.101, p.137). Device-to-device Quick Start is **UNVERIFIED**, but the design is safe either way. | any restored blob → `keyMissing` → `.discardAndRebuild` | Sign in again (tokens are also device-only) → fresh fetch. `user-state` survives only under D-E4 (a). |
| App deleted and reinstalled | Keychain items **may survive**. Apple staff call it an implementation side effect, not guaranteed (forum 36442, **UNVERIFIED**, seen only as a search excerpt). | the container is gone | `VaultBootstrap.reconcileInstall`: no sentinel → shred every vault key, then write the sentinel. Security applies the same rule to tokens. |

- **Error taxonomy (the store MUST honour it; implemented as `VaultError.disposition(for:)`):**

| Error | snapshot / glance / ledger | user-state |
|---|---|---|
| `protectedDataUnavailable` (Keychain -25308, or file read denied) | `retryAfterUnlock`: keep file, key and memory; retry on `protectedDataDidBecomeAvailable` | same |
| `keyMissing`, `authenticationFailed`, `malformed`, `unsupportedFormat`, `fileMismatch` | `discardAndRebuild`: the owner deletes; re-fetch, or rebuild glance from snapshot, or reconcile the ledger | `resetUserStateAndTell`: start empty and tell the user once |
| `storage(code:)` (unclassified I/O), `readOnlyProcess` | `keepAndReport`: delete nothing, log the category | same |

- **Secure Enclave.**
  - Not used in v1: it holds no symmetric keys, and every background or widget read would need the private key.
  - The only defensible use is **vault mode (D-E5):** background refresh HPKE-seals to an Enclave `P256.KeyAgreement` public key (`SecureEnclave.P256.KeyAgreement.PrivateKey` conforms to `HPKEDiffieHellmanPrivateKey`, iOS 17). The private key requires `.userPresence`, so writing needs no unlock and reading needs Face ID or the passcode.
  - This partly answers Security's "MAS-L2 not recommended" (`security.md:179`): the *write* side works while locked. The digest inputs and `glance` would still have to stay CUFA, which is why deferral is recommended.
  - iOS 26 also offers Enclave ML-KEM (e.g. HPKE X-Wing), which is not needed for local data at rest.

### 3.5 Blob format v1 and test vectors

```
offset  size  field
0       4     magic  "TLYV" (54 4C 59 56)
4       1     format = 0x01
5       1     file   = StoreFile raw (snapshot 01, glance 02, userState 03, ledger 04)
6       2     flags  = 0x0000 (non-zero -> unsupportedFormat)
8       4     keyID  (UInt32 big-endian, random)
12      12    nonce  (random)
24      n     ciphertext
24+n    16    GCM tag
AAD = bytes 0..<12. Minimum size 40. Blob = header || AES.GCM.SealedBox.combined
```

Key `00 01 … 1f`; nonce `a0 a1 … ab`. The nonce is pinned for test vectors only; the `internal` seal API is reachable only through `@testable`.

| ID | file / keyID | plaintext | blob (hex) |
|---|---|---|---|
| TV1 | snapshot / 1 | `{"v":1}` | `544c59560101000000000001a0a1a2a3a4a5a6a7a8a9aaab9d3a0a0f7ffa7facb577066bd84fc946655a49e313646e` |
| TV2 | snapshot / 1 | empty | `544c59560101000000000001a0a1a2a3a4a5a6a7a8a9aaab77dd7c44b89e4d75d3af373e7244d192` |
| TV3 | glance / 7 | `Due: MATH 221 – Problem Set 4` (UTF-8) | `544c59560102000000000007a0a1a2a3a4a5a6a7a8a9aaaba26d1917658643eb2a45b5e1365a225ee38c0962fdd52e09f12e75e30b8b41a3e8788465b76b6f094732287b312360` |
| TV4 | ledger / 0xDEADBEEF | `[]` | `544c595601040000deadbeefa0a1a2a3a4a5a6a7a8a9aaabbd4553b61004cf09e59368bc4cf35293bda3` |
| TC16 | primitive check | McGrew–Viega GCM Test Case 16 | C = `522dc1f0…bcc9f662`, T = `76fc6ece0f4e1768cddf8853bb2d551b` |

Negative vectors (on TV1):

| Change | Expected error |
|---|---|
| Tag bit flip | `authenticationFailed` |
| File byte → 02 | `authenticationFailed` (AAD) |
| keyID → 2 | `authenticationFailed` (AAD) |
| Truncated to 39 bytes | `malformed` |
| Magic `X…` | `malformed` |
| Format 02 | `unsupportedFormat(2)` |
| Flags ≠ 0 | `unsupportedFormat(1)` |
| All-zero key | `authenticationFailed` |

The vectors were produced independently by `docs/pmo/encryption-spec/tools/vectors.py` (python-cryptography 50.0.1, OpenSSL 4.0.2) and reproduced by the Swift tests.

### 3.6 Interaction with the store (Architecture owns the engine)

- **Contract.** Architecture chose a sealed Codable snapshot plus a glance projection (`architecture.md:117-178`). `VaultSealer` conforms to its `SnapshotSealer` exactly. It is synchronous, one instance per account, and keyed per `StoreFile`. Conformance compiles in the spec package.
  - Architecture's `SnapshotStore` should call `SealedFileAccess.read/write`. That wrapper does the protected atomic write and returns `SealedRead.plaintext | .absent | .failed(error, disposition)`. It should not call the file system or the sealer directly.
  - Architecture's pass-through sealer stays fine for its own Linux tests.
- **Requirements for any engine** (in case D4 (b) trend history or a database is ever chosen):
  1. Every Canvas-derived byte at rest goes through `VaultSealer`, or is explicitly listed in §3.2 with a reason.
  2. Replace = temp file in the same directory → write → `fsync` → `rename`.
  3. CUFA class.
  4. Exclusion re-applied after every save.
  5. Engine files include side files. SQLite `-wal`, `-shm` and journals cannot be enveloped without SQLCipher and keep deleted rows in free pages. This is a further reason the chosen single-blob snapshot is the right fit.
- **Atomic replace.** Foundation's `Data.write(options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])` already does this:
  - The open-source implementation opens a protected temp file in the destination directory (`_NSOpenAtFileDescriptor_Protected` in the Apple build), writes, `fsync`s and `renameat`s (swift-foundation `Data+Writing.swift` @ `d1f19af768`).
  - `fsync` is not `F_FULLFSYNC`, so a power cut can lose the *latest* write. The GCM tag turns any resulting torn file into `discardAndRebuild`. Acceptable for a re-fetchable cache.
  - Whether the Apple build applies the class to the temp file is read from source only (**UNVERIFIED on device**). WP-ENC-06 reads back `FileAttributeKey.protectionKey`.
  - Orphaned temp files are swept on foreground launch (`ProtectedFile.sweep`).
- **Caches vs Application Support.** Application Support (or the App Group's `Library/Application Support`). Caches can be purged by the system, which breaks launch-from-cache.
- **SQLCipher: not justified.**
  - It adds non-OS crypto, which triggers the French declaration (ASC table) and the vendor's own guidance that "each party… is responsible for their own classification and reporting" (Zetetic).
  - It adds a C dependency.
  - It solves a problem the single-blob design doesn't have.
  - It still doesn't help against after-first-unlock threats, because its key would need the same Keychain class.

### 3.7 Purge contract (Encryption part of Security WP-SEC-06 / ASC R9)

`VaultPurger.purge(account:keyring:directories:)` does two steps:

1. Shred both audience keys for the account.
2. Delete the account directories in the app container and the App Group.

The caller (`AccountPurger`/`EraseService`), in order:

1. Revoke the token (Security).
2. Call `VaultPurger`.
3. Delete the credential (Security).
4. `removeAllPendingNotificationRequests` / `removeAllDeliveredNotifications` for the account prefix.
5. Delete Spotlight/App Intents donations.
6. Delete Tally calendar events, if the user chooses.
7. Clear `UserDefaults` of account-scoped keys.
8. `WidgetCenter.reloadAllTimelines()`.
9. On full erase, also `VaultBootstrap`'s sentinel reset.

Every step is idempotent. If shredding hits `protectedDataUnavailable`, sign-out tells the user to unlock. That can't happen in the foreground in practice.

### 3.8 Export compliance (as of 2026-09-26)

- **Apple.** "Set the value to NO if your app… only uses forms of encryption that are exempt". "Typically, the use of encryption that's built into the operating system… is exempt from export documentation upload requirements". ASC table: "Your app uses encryption limited to that within the Apple operating system → No documentation required in App Store Connect".
  - HTTPS via URLSession, Data Protection, Keychain and **CryptoKit AES-GCM** are all OS crypto.
  - Keep `ITSAppUsesNonExemptEncryption = NO`. Nothing is uploaded, and there is no French declaration.
- **If we ever bundle another crypto library** (SQLCipher, libsodium, OpenSSL/BoringSSL via an SDK, or swift-crypto *on iOS*):
  - The row "industry standard algorithm, not provided within the Apple operating system" applies, which means uploading a French encryption declaration if the app is distributed in France.
  - The plist must follow the questionnaire.
  - swift-crypto re-exports CryptoKit on Apple platforms ("compiles its entire API surface down to nothing"). Making it a **Linux-only conditional** dependency keeps it out of the iOS build graph and removes any doubt.
- **France.** ANSSI controls "Secure Storage, Secure Communications" apps (ASC overview), but Apple requires the upload only in the non-OS-crypto rows.
- **Annual self-classification report.** Apple's page still says "you might alternatively be required to submit a year-end self-classification report".
  - 15 CFR 740.17(e)(3) (eCFR, 2026-09-01) limits the report to "'mass market' encryption components and 'executable software'" plus non-mass-market 5A002/5B002/5D002 items. A consumer end-user app using OS crypto is neither. My reading: **no report** (the 2021 rule cut reporting for mass-market items).
  - **Not legal advice.** If D-E1 (c) or any bundled crypto were chosen, get counsel.
  - This agrees with Compliance R11 and D10(a).

### 3.9 Linux vs device, and whether swift-crypto forces an abstraction

- **Crypto primitives: no abstraction.**
  - Production code uses `#if canImport(CryptoKit) import CryptoKit #else import Crypto #endif`.
  - `Package.swift` uses `.product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))`.
  - The API is identical ("exactly the same"; swift-crypto 5.x needs Swift 6.2+). `SymmetricKey` is `Sendable`, and `SealedBox.combined` is `Data?`, both checked against Apple docs.
- **Seams that are forced:**
  - The Keychain (`VaultKeyStore`), because Security.framework is absent on Linux.
  - Protection class and backup exclusion. Both compile on Linux but are no-ops there: swift-foundation defines the options, and swift-corelibs-foundation silently ignores `isExcludedFromBackup`. They are verified in the macOS simulator (exclusion read-back) and on a device (class enforcement). Apple's Simulator does not enforce Data Protection (Nutrient, secondary source).
- **Assessment harness.** swift-crypto wasn't fetched: the network was off and the dependency was outside this read-only assessment. So `docs/pmo/encryption-spec` contains a **harness-only** `Crypto` shim with the same API subset, backed by the image's system `libcrypto.so.3`. **It must not ship.** WP-ENC-01 replaces it with the real conditional dependency and re-runs the same tests.
- **Test result.** Run in `swift:6.4.0-noble`, `--network=none`: 20 tests, 0 failures, 0 warnings (`tools/linux-test-run-2026-09-26.txt`).
  - Mutation checks: making the store delete on `retryAfterUnlock` failed the lock regression test, and altering one vector byte failed three vector tests.
  - Also re-run from a fresh copy of the durable directory.

### 3.10 API surface (full source in `docs/pmo/encryption-spec/Sources/TallyVault/`)

```swift
public enum StoreFile: UInt8 { case snapshot = 1, glance = 2, userState = 3, ledger = 4 }   // .audience, .isRederivable
public struct KeyScope: Hashable, Sendable { let account: String; let audience: KeyAudience } // .app | .widget
public enum VaultError: Error, Equatable { case protectedDataUnavailable, keyMissing, malformed, unsupportedFormat(UInt8),
                                           fileMismatch, authenticationFailed, readOnlyProcess, storage(code: Int) }
extension VaultError { func disposition(for: StoreFile) -> VaultDisposition } // retryAfterUnlock | discardAndRebuild | resetUserStateAndTell | keepAndReport

public protocol VaultKeyStore: Sendable {            // Darwin: KeychainVaultKeyStore; Linux tests: in-memory fake
  func keyIDs(for: KeyScope) throws -> [UInt32]; func key(id: UInt32, for: KeyScope) throws -> SymmetricKey?
  func add(_: SymmetricKey, id: UInt32, for: KeyScope) throws; func deleteAll(for: KeyScope) throws; func deleteEverything() throws }
public final class VaultKeyring: @unchecked Sendable {           // lock-serialised get-or-create; shred(account:); shredEverything()
  func currentKey(for: KeyScope, createIfMissing: Bool) throws -> (id: UInt32, key: SymmetricKey)? }
public struct VaultSealer: SnapshotSealer {                      // Architecture's contract
  init(account: String, keyring: VaultKeyring, mayCreateKeys: Bool)
  func seal(_ plaintext: Data, file: StoreFile) throws -> Data; func open(_ sealed: Data, file: StoreFile) throws -> Data }
public enum SealedBlob { static func seal(_:header:key:) throws -> Data; static func open(_:key:) throws -> (header, plaintext) }
public enum ProtectedFile { prepareDirectory(_:excludeFromBackup:), read(_:), atomicWrite(_:to:excludeFromBackup:), sweep(directory:keeping:) }
public struct SealedFileAccess { init(sealer:isOwner:); func read(_: StoreFile, at: URL) -> SealedRead; func write(_:_:to:excludeFromBackup:) throws }
public enum VaultPurger { static func purge(account:keyring:directories:) throws }            // shred first
public enum VaultBootstrap { static func reconcileInstall(keyring:sentinel:) throws }          // reinstall with surviving Keychain
```

**Integration notes:**
- The `accountKey`, bundle ID, Team ID and App Group ID come from Architecture D8.
- The `refresh-state.json` / `accounts.json` content rules are in §3.2.
- If `KeychainVaultKeyStore.add` loses a race, it can return `errSecDuplicateItem`. `VaultKeyring` prevents that within a process, and only the app process mints keys.

## 4. Decisions for the product owner

**D-E1 — App-layer encryption of the Canvas cache.**
- *Options:* (a) Data Protection (CUFA) plus backup exclusion only; (b) (a) plus a thin CryptoKit AES-GCM envelope with device-only keys; (c) SQLCipher.
- *Recommendation:* **(b).**
- *Consequences:*
  - (a) meets "encrypted" literally, since iOS encrypts every file. But unencrypted Finder backups and best-effort exclusion can still leak plaintext, and there is no crypto-shred.
  - (b) costs about 310 lines plus the Keychain adapter and roughly 1 ms-scale CPU per refresh (**UNVERIFIED** until WP-ENC-06 measures it). It closes the backup channel, gives shred and app/widget separation, and needs no export paperwork.
  - (c) adds a C dependency, a French declaration and classification duties, with no protection gain over (b).

**D-E2 — Protection class for Canvas data.**
- *Options:* (a) CUFA for every store file; (b) two-tier: full snapshot Complete/CUO plus a minimal CUFA digest state, using Architecture's deferred commit; (c) Complete everywhere.
- *Recommendation:* **(a).**
- *Consequences:*
  - (a) Background refresh, digest, threshold alerts and widgets work while locked; after-first-unlock forensics can read the data.
  - (b) Protects assignment detail from after-first-unlock forensics, but the glance and grades must stay CUFA anyway. Adds commit complexity and new failure modes.
  - (c) No background refresh or widget content while locked. This breaks PRD 01 §3/§4 (auto-refresh on periodic background intervals; WidgetKit home-screen widgets).

**D-E3 — Widget and Lock Screen exposure.**
- *Options:* (a) The widget shows due items; grade views are `.privacySensitive()`; grades in widgets are opt-in (default off); (b) the widget extension gets the Data Protection entitlement (Complete), so placeholders show until unlock and there are no iPhone widgets on Mac; (c) grades always shown.
- *Recommendation:* **(a).**
- *Consequences:*
  - (a) Useful widgets; grades appear on the Lock Screen only if the student opts in.
  - (b) Maximum privacy, but the Lock Screen widget is useless while locked.
  - (c) Anyone holding the phone sees grades.

**D-E4 — Backup of user-authored `user-state` (rules, goals, quiet hours).**
- *Options:* (a) Not sealed, CUFA, **backed up**, content limited to user-entered values and opaque IDs (schema test); (b) sealed with a device-only key and excluded (Architecture's current layout); (c) sealed with an iCloud-Keychain-synchronizable key.
- *Recommendation:* **(a).**
- *Consequences:*
  - (a) Rules survive a new phone; no Canvas content leaves the device.
  - (b) Every new phone or restore to a new device silently resets the student's rules, because iCloud Backup restores the local keychain to the same device only.
  - (c) Survives, but a key leaves the device and depends on iCloud Keychain being on. More complex, for little benefit.

**D-E5 — "Vault mode": cryptographically enforced app lock (Enclave, user presence).**
- *Options:* (a) defer; (b) build in v1 as an opt-in.
- *Recommendation:* **(a).**
- *Consequences:*
  - (a) The app lock stays a UI barrier (Security WP-SEC-07). Unlocked-phone extraction can read the cache.
  - (b) The snapshot is protected even from an unlocked-phone extraction. But the digest state and glance stay CUFA, background diffs need a redesign, and it adds HPKE plus Enclave device testing. That is a lot of cost for a partial gain.

## 5. Work packages

| WP-ID | Title | Depends on | Acceptance criteria | How verified |
|---|---|---|---|---|
| WP-ENC-01 | `TallyVault` core in `TallyCore/TallyStore`: `SealedBlob`, header, `StoreFile`/`KeyScope`/`VaultError` + dispositions, `VaultKeyring`, `VaultSealer: SnapshotSealer`; swift-crypto as a **Linux-only conditional** dependency; delete the harness shim | Arch WP-A01; owner OK to fetch swift-crypto ≥5.0 | TV1–TV4, TC16 and the negative vectors pass; 1,000 random nonces are distinct; one key per scope under 64-way concurrency; `import Crypto` never resolves on iOS (`swift package show-dependencies` check); ≤300 lines excluding tests | Linux swift container |
| WP-ENC-02 | `ProtectedFile` + `SealedFileAccess` + sweep, wired into `SnapshotStore` (with Arch WP-C01) | ENC-01, Arch C01 | All 16 `SealerAndStoreTests` pass against the real store; a locked read returns `retryAfterUnlock` and deletes nothing (regression test); the widget (non-owner) never deletes; no `Data.write(to:` elsewhere in `TallyCore` (grep gate) | Linux swift container |
| WP-ENC-03 | `KeychainVaultKeyStore` + hosted tests | ENC-01, Arch D8, WP-E01 | Add/get/list/delete per scope; an app-audience key is invisible to a store configured with only the App Group group; attributes read back as `AfterFirstUnlockThisDeviceOnly`, non-sync, explicit group; `errSecInteractionNotAllowed` maps to `.protectedDataUnavailable` (via injected status mapper) | macOS CI simulator |
| WP-ENC-04 | Purge + reinstall reconcile integration (`VaultPurger` inside Security WP-SEC-06 / ASC-07 `EraseService`; `VaultBootstrap` at the foreground launch path) | ENC-02, ENC-03, SEC-06 | Keys shredded before files (order test); account B survives A's purge; XCUITest "Sign out & erase" leaves no vault key and no account directory | Linux (order) + macOS CI simulator (XCUITest) |
| WP-ENC-05 | Widget wiring: App Group Keychain access group entitlement for app + widget; widget uses `VaultSealer(mayCreateKeys:false)` + `SealedFileAccess(isOwner:false)`; glance content allowlist test | ENC-03, Arch WP-E06, WP-C03, D-E3 | Widget renders glance on the simulator; opening the snapshot from the widget → `keyMissing`; glance Codable key set equals the allowlist | macOS CI simulator; lock-screen behaviour device-only |
| WP-ENC-06 | Device verification protocol + runbook | ENC-02..05 | On a passcode-locked device: forced BG task (`_simulateLaunchForTaskWithIdentifier`) reads the snapshot and writes a new one; widget timeline reload renders while locked; `protectionKey` reads back CUFA on the final file after an atomic write; unencrypted Finder backup contains no plaintext (`grep` for a known course code) and no vault key usable elsewhere; restore to a second device → `keyMissing` → refetch; seal+open of 5 MB on the oldest supported device < 20 ms (budget named in config) | **device-only** |
| WP-ENC-07 | CI guards | ENC-01 | (1) Dependency allowlist: iOS build graph has no non-Apple crypto (fails on SQLCipher/OpenSSL/BoringSSL/swift-crypto without the Linux condition); (2) `Info.plist` `ITSAppUsesNonExemptEncryption == NO`, tied to (1); (3) SwiftLint custom rule bans `.completeFileProtection` and raw `Data.write` outside `ProtectedFile` | Linux (lint/grep) + macOS CI |
| WP-ENC-08 | Accurate privacy copy: Settings "Data protection" row and PRIVACY.md, restored only after ENC-01..05 (with SEC-15 and UX) | ENC-05 | Copy says "Cached data is encrypted, kept only on this iPhone, excluded from backups and destroyed on sign-out"; no theft-protection claim | macOS CI screenshot |

## 6. Cross-lane notes

- **Architecture:**
  - The glance needs an App Group **Keychain access group** for its key (ENC-08). Tokens still never enter it.
  - Consider the app-private container for snapshot, ledger and user-state. The envelope enforces separation either way.
  - CUFA everywhere makes `incoming/` deferred commit unnecessary.
  - `SnapshotStore` must honour `VaultDisposition`, and must adopt the locked-read regression test.
  - `user-state` backup changes the "every file excluded" rule (D-E4).
  - D4 (b) trend history would be a new `StoreFile`.
  - `BGTaskScheduler.register` runs in a SwiftUI `View.init` (`AppRootView.swift:10-13`). It must run exactly once, before launch finishes.
- **Security:**
  - Token class `AfterFirstUnlockThisDeviceOnly` agreed (D3). Use the same typed "locked vs absent" results (WP-SEC-04).
  - The purge API for WP-SEC-06 is `VaultPurger.purge(account:)`, which shreds first.
  - Apply the reinstall-sentinel rule to credentials.
  - Asymmetric sealing solves only the *write* side of MAS-L2. Deferral is agreed (D-E5).
  - URLCache/cookies (SEC-08) are a prerequisite for ENC-05's promise.
- **App Store compliance:**
  - D10 (a) confirmed. R11 stands. WP-ENC-07 enforces it.
  - Apple's page mentions a possible self-classification report; §3.8 gives the CFR reading.
  - iPhone apps on Apple silicon Macs get Class C with a *volume* key (p.90). Consider opting out of Mac availability for v1 unless tested there.
- **UX:**
  - States needed for `resetUserStateAndTell` ("Your reminder settings couldn't be restored on this device") and first launch after a new-device restore (sign in again; data re-fetches).
  - Widget grade opt-in (D-E3).
  - Cover the screen on `.inactive`, so app-switcher snapshots hold no grades (Security §3.3 rule).
- **Notifications:** keep bodies generic (Security WP-SEC-10). Pending and delivered requests are in the purge list.
- **QA:** WP-ENC-06 is the only place where protection classes are truly verified. The Simulator does not enforce Data Protection.

## 7. Sources

| URL | What it established | Status |
|---|---|---|
| https://help.apple.com/pdf/security/en_US/apple-platform-security-guide.pdf (August 2026; text extracted 2026-09-26) | p.90 per-file AES-XTS keys; Mac Class C volume key. p.92-93 class semantics (Complete discarded 10 s after lock; CUO via Curve25519 ECDH; CUFA default for third-party data). p.94 backup keybag; unencrypted backups hold files "not encrypted regardless of their Data Protection class"; PBKDF2 10M. p.97 Automatic Restart (AFU→BFU, iOS 18.1). p.100-101 Keychain classes table; `AfterFirstUnlock` for background refresh; "This device only… useless if it's restored to a different device". p.87 CryptoKit ML-KEM/ML-DSA (iOS 26). p.136-137 iCloud Backup: CUFA files uploaded with account-based keys; local keychain restorable "only to the same device". p.214 Apple SSO tokens use `AfterFirstUnlockThisDeviceOnly`. p.227-228 WidgetKit: "Allow Access When Locked", redaction, Data Protection capability → placeholders, not on Mac. p.242-243 Shared iPad per-user APFS volume and keychain; data synced to iCloud | VERIFIED |
| https://support.apple.com/guide/security/data-protection-classes-secb010e978a/web ; https://support.apple.com/guide/security/keychain-data-protection-secb0694df1a/web | Web versions of the same class definitions | VERIFIED |
| https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files | The four levels; CUO "open existing files only when the device is unlocked"; use a different level for background access | VERIFIED |
| https://developer.apple.com/documentation/uikit/uiapplication/isprotecteddataavailable | Complete/CUO files unreadable while locked | VERIFIED |
| https://developer.apple.com/documentation/uikit/about-the-app-launch-sequence | Prewarming runs no app code | VERIFIED |
| https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup ; …/urlresourcevalues/isexcludedfrombackup | Caches/tmp purged and not backed up; exclusion is "not a mechanism to guarantee"; re-set on every save; directory-level exclusion | VERIFIED |
| https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly | Recommended for background access; does not migrate | VERIFIED |
| https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps ; https://developer.apple.com/documentation/xcode/configuring-app-groups | App Group ID usable as a Keychain access group; an unscoped query matches any group | VERIFIED |
| https://developer.apple.com/documentation/foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:) | App Group container and its `Library/Application Support` | VERIFIED |
| https://developer.apple.com/documentation/cryptokit/secureenclave ; …/secureenclave/mlkem768 | Enclave: P256, MLKEM768/1024 (iOS 26.0), MLDSA65/87 | VERIFIED |
| https://developer.apple.com/documentation/cryptokit/hpkediffiehellmanprivatekey ; …/hpke/ciphersuite | `SecureEnclave.P256.KeyAgreement.PrivateKey` conforms (iOS 17); P256/X-Wing suites | VERIFIED |
| https://developer.apple.com/documentation/cryptokit/symmetrickey ; …/aes/gcm/sealedbox/combined | `SymmetricKey: Sendable, ContiguousBytes`; `combined: Data?` | VERIFIED |
| https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/urlsession(_:datatask:willcacheresponse:completionhandler:) ; …/urlsessionconfiguration/ephemeral | When URLCache stores responses; ephemeral writes no cache to disk | VERIFIED |
| https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations | `ITSAppUsesNonExemptEncryption` semantics; OS crypto "typically… exempt"; possible year-end self-classification report | VERIFIED |
| https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption | OS-only → no documentation; non-OS standard → French declaration (France only); proprietary → CCATS + French | VERIFIED |
| https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance | France controls Secure Storage/Communications (ANSSI) | VERIFIED |
| https://www.ecfr.gov/current/title-15/subtitle-B/chapter-VII/subchapter-C/part-740/section-740.17 (versioner API, 2026-09-01) | (b)(1) and (e)(3): report scope limited to mass-market components/executable software and non-mass-market items; due 1 Feb | VERIFIED (text); interpretation is not legal advice |
| https://www.venable.com/insights/publications/2021/03/export-administration-rules-are-revised-to-elim | 2021-03-29 rule eliminated reporting for certain mass-market items | VERIFIED (secondary) |
| https://www.zetetic.net/sqlcipher/export-compliance/ | SQLCipher adopters file their own classification/reports and French declaration | VERIFIED |
| https://github.com/apple/swift-crypto | Re-exports CryptoKit on Apple platforms; BoringSSL on Linux; identical API; 5.0.0 needs Swift 6.2 | VERIFIED |
| https://github.com/swiftlang/swift-foundation/blob/main/Sources/FoundationEssentials/Data/Data%2BWriting.swift (@ d1f19af768, 2026-09-15) | `.atomic` = protected temp in the destination directory, write, `fsync`, `renameat`; protection options defined but ignored off Apple | VERIFIED (source) |
| https://github.com/swiftlang/swift-corelibs-foundation/blob/main/Sources/Foundation/NSURL.swift (@ cb95d20027) | `isExcludedFromBackup` "Not supported outside of Apple OSes"; setting it is silently ignored | VERIFIED (source) |
| https://developer.apple.com/forums/thread/78372 | `WhenUnlocked` items fail with -25308 while locked; `AfterFirstUnlock` works (DTS, 2017) | VERIFIED |
| https://developer.apple.com/forums/thread/718416 | Data Protection drops the file key; reads fail while the descriptor stays valid (DTS, 2022) | VERIFIED |
| https://developer.apple.com/forums/thread/36442 | Keychain survival across uninstall is an implementation side effect, not guaranteed | UNVERIFIED (search excerpt only) |
| https://github.com/markclausing/vibecoach/pull/359 | Field report: locked background launch + CUO store → treated as corruption → store deleted; fixed with CUFA and no-delete | VERIFIED (third-party report) |
| https://www.nutrient.io/blog/how-to-use-ios-data-protection/ (2024-09-24) | Simulator does not enforce Data Protection | VERIFIED (secondary) |
| https://csrc.nist.rip/groups/ST/toolkit/BCM/documents/proposedmodes/gcm/gcm-spec.pdf ; https://github.com/bcgit/bc-java/blob/main/core/src/test/java/org/bouncycastle/crypto/test/GCMTest.java | GCM Test Case 16 values (reproduced exactly by OpenSSL and the Swift harness) | VERIFIED |
| https://nvlpubs.nist.gov/nistpubs/legacy/sp/nistspecialpublication800-38d.pdf | §8.3: at most 2^32 random-IV invocations per key | VERIFIED (via search excerpt of the primary) |
| — | Background tasks before first unlock; exact CocoaError for a denied read on device; `fileExists` while locked; Quick Start keychain transfer; Shared iPad sync vs exclusion; CryptoKit throughput on the oldest device; the Apple Foundation build applying the class to the atomic temp file | **UNVERIFIED** → WP-ENC-06 |
