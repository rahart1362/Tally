# ADR 0001 — Canvas sign-in: per-launch handshake, no Tally server, biometric app lock

- Status: **Accepted** (owner decision O2, 2026-09-26)
- Supersedes: kit `02_System_Architecture.md` §5 (identity) where they differ
- Related: `docs/pmo/reviews/security.md` §3.1–3.3, `architecture.md` §3.5, `encryption.md`; backlog BL-01, BL-13; go-live GL-01, GL-05

## Context
- Canvas supports OAuth 2.0 **Authorization Code + PKCE for public clients**, so no `client_secret` and no server are needed. This is verified in canvas-lms source, commits `07125fa` and `d0b9c22`.
- Tokens issued to a public client live in a **2-hour rolling window**, and the refresh token rotates on every use. On hosted Canvas this is UNVERIFIED; gate GL-05 must confirm it.
- The owner wants no services or hosting on their side. The owner also wants each launch to perform a handshake directly between the student's device and their school's Canvas, with an optional Face ID / Touch ID preference.

## Decision
**Default model: PKCE public client, device ↔ Canvas only.** No Tally server is on the credential or data path. A token broker is recorded as backlog BL-01, not built.

### Launch sequence (least-resistance path)
1. **Privacy cover.** The app shows a neutral cover until it has decided whether to lock. No cached grades are visible in the app switcher or before unlock.
2. **App lock**, if the student enabled "Unlock with Face ID / Touch ID".
   - Uses `LAContext` with `.deviceOwnerAuthentication`: biometrics first, with the device passcode as fallback, so a failed Face ID can never lock a student out and can never let anyone else in.
   - Locks on cold launch, and after being in the background longer than the grace period (default 1 min; options Immediately, 1, 5, 15 min).
   - Any `LAError` keeps the app locked. Turning the lock *off* requires authentication.
   - If biometric enrolment changes (`evaluatedPolicyDomainState`), the passcode is required once.
   - The preference lives in the Keychain, not `UserDefaults`.
3. **Instant render from the sealed cache**, targeting < 300 ms, with the "Updated <time>" footer.
4. **Silent handshake.** If the refresh token is still inside its window, refresh it without any UI (single-flight, and the rotated token is persisted *before* use), then run the live refresh under the 10-second budget.
5. **Automatic reconnect** if the refresh token has expired.
   - With cached data still on screen, Tally immediately presents the school's Canvas sign-in in `ASWebAuthenticationSession`.
   - The session is **non-ephemeral**, so it reuses the student's existing school single sign-on session in Safari. In the common case the student taps **Continue** on the iOS prompt and is back in about 2 seconds.
   - If the school page does ask for a password, iOS offers the saved password or passkey with **Face ID**, through iCloud Keychain AutoFill.
   - A Settings toggle, "Reconnect automatically when I open Tally", defaults to on. When it is off, the student sees the stale breadcrumb with a one-tap **Sign In**.
6. **Cancel is not an error.** Cached data stays visible with the breadcrumb "Sign in to refresh — showing saved data from <time>".

### Why this is the least resistance
- Zero hosting, zero Tally accounts, zero secrets in the binary.
- Face ID guards the app, and iCloud Keychain uses Face ID to fill the school password. Tally never sees or stores the school password.
- The only unavoidable friction is iOS's own "Tally wants to use <school> to sign in" prompt. It can only be suppressed with ephemeral sessions, which would discard single sign-on and force a full password (and MFA) entry every time. That is worse.

## Security controls (from the security review)
- Authorization request carries `state`, a single-use value with a 10-minute TTL, plus a PKCE S256 challenge. It also carries an exact-host check against the institution registry, and `force_login=1` when adding or switching accounts.
- Tokens are stored in the Keychain as `AfterFirstUnlockThisDeviceOnly`, per account, with atomic update-or-add. This allows background refresh while the device is locked, and the tokens never go to backups.
- Networking uses an ephemeral `URLSession` with no cache and no cookies. Cross-host redirects strip `Authorization`.
- Sign out and erase does all of the following: revokes the token at Canvas (`DELETE /login/oauth2/token`), deletes the Keychain items, crypto-shreds the sealed cache by deleting its key, and removes notifications. The UI discloses that Safari may remain signed in to the school.

## Consequences
- If hosted Canvas really enforces 2 hours, most launches after a gap will show the Continue prompt. Background refresh and widgets will often run on cached data. Reminders are unaffected because they are local and computed from the cache.
- Two ways to lengthen sessions, both recorded in the backlog: **BL-13**, Instructure's "mobile app" token treatment (90-day path in canvas-lms `developer_key.rb`), requested as part of GL-01; and **BL-01**, the broker, last resort only.
- `ClientRegistration.clientType` keeps the auth layer agnostic, so either change is a configuration switch, not a rewrite.

## Verification
- Linux: PKCE RFC 7636 vector, `state` store, 401 state machine (50 concurrent 401s produce exactly one refresh), lock-policy state machine.
- macOS CI: web-auth adapter against a stubbed token endpoint, lock/cover UI tests.
- Real Canvas: gate GL-05 (token lifetime, rotation, and whether Canvas re-shows its "Authorize" page on each reconnect — UNVERIFIED).
