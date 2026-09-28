# Application Security Lead Review — Tally

Author: Application Security Lead. Date: 2026-09-26. Branch `pmo/assessment` (read-only on source).
Builds on `docs/pmo/00-baseline-audit.md`. Data-at-rest cryptography, file-protection classes and export compliance belong to the **Encryption specialist**; this report cites that lane and does not duplicate it.

**How I checked Canvas facts.** Instructure's public docs do not yet describe PKCE. The newer developer-docs portal does document `client_type=public`. To settle the PKCE question I read Instructure's open-source `canvas-lms` code and commit history directly (via the GitHub API, 2026-09-26). The public mirror was last pushed on **2026-04-30**. Instructure-hosted Canvas may have changed since then, so every behaviour I derived from source code is labelled **"source-verified (OSS), hosted UNVERIFIED"** until WP-SEC-17 tests it on a real hosted instance.

---

## 1. Executive summary

- **Blocker: no compliant way to launch at every school at once.** Canvas developer keys are "scoped to the institution they are issued from", and "for Canvas Cloud… issued by the admin of the institution". Global keys can only be created by Instructure employees, and each root account must still enable them. The Instructure Partner Program tier sheet does not list a global key as a benefit. So every compliant option needs a Canvas admin at each school (or Instructure) to act. Tally cannot ship as "download and sign in at any school". Owner decisions D1, D2 and D4.
- **PKCE without a secret is supported now, with a hidden cost.** Canvas added PKCE and public clients on 2024-09-26 and removed the feature flag on 2026-03-28. Public clients can exchange and refresh with no `client_secret`, which makes the owner's "no Tally server" principle achievable. The cost, from the source code: a third-party public client gets a **2-hour rolling refresh window** and its refresh token **rotates on every use**. A student who hasn't opened Tally for more than 2 hours has to sign in again, and background refresh and widgets can't keep the session alive. This must be tested on hosted Canvas (WP-SEC-17) before D1 is final.
- **Asking students to paste a token is explicitly banned.** Instructure's docs say: "asking any other user to manually generate a token and enter it into your application is a violation of Canvas' API Policy". Schools are also switching it off: UW–Madison stopped students generating tokens on 2025-11-14. Separately, the API Policy forbids "competitive purposes" and says apps "should not mirror or replicate Instructure… products". App Review 5.2.2 requires proof of permission "upon request". Tally therefore needs Instructure's written authorization before public launch (D4).
- **Today's code has no real sign-in, and the biometric lock can be bypassed three ways.** The app saves a fabricated token (`LoginView.swift:69-80`). `authenticate()` unlocks the app whenever biometrics can't be evaluated (`TallySecurity.swift:181-185`), which includes Face ID lockout: anyone holding the phone can fail Face ID five times and get in. `isLocked` starts as `false` and is only set on `.background`, so a cold launch opens unlocked (`TallySecurity.swift:109`, `AppRootView.swift:40-44`). The Keychain wrapper treats "device locked" the same as "no token" (`:51-54`), stores tokens in a class that background refresh can't read (`:29`), and writes non-atomically (delete, then add) (`:22-32`). That write pattern will lose a rotated refresh token.
- **Student data can leak outside the encrypted cache.** Authenticated calls use `URLSession.shared`, whose disk cache and cookie store sit outside the encrypted cache. Notifications show course and exam titles on the Lock Screen. `print()` writes an assignment title to the log. Sign-out neither revokes the token at Canvas nor purges the cache, and "Clear Cache" does nothing. Settings also shows "All cached data is encrypted at rest" with a green tick, which is false today (`SettingsView.swift:131`).
- **Supply chain is cheap to fix, and MS365/Google should not be in v1.** Keep the current zero third-party packages. Pin Actions to commit SHAs, drop `actions: write`, enable Dependabot (it supports Swift), protect `main`, and add a `.gitignore` before any signing material exists. For Outlook and Google calendars, EventKit can already write to accounts the user has added in iOS Settings, and the Mail compose sheet covers email. Together these deliver most of the MS365/Google value with no OAuth, publisher verification or Google restricted-scope review.

## 2. Findings

| ID | Severity | Evidence | Impact |
|---|---|---|---|
| SEC-01 | **Blocker** | Instructure OAuth docs: keys "scoped to the institution they are issued from"; Cloud keys "issued by the admin of the institution". Global keys are "created globally, by an Instructure employee" and "functional in any Canvas account where they are enabled"; root admins "may enable or disable global developer keys". The Partner tier sheet (2025) lists sandbox, support and listings, but **no global key**. OSS `developer_key.rb:379-391` resolves the account binding site-admin first, then down the account chain. | Every compliant path is gated per institution (or by Instructure). This is a go-to-market constraint, not a coding task, and it drives D1, D2 and D4. |
| SEC-02 | **Critical** | Source-verified (OSS), hosted UNVERIFIED: `developer_key.rb:449` `mobile_app?` returns `false`; `:457` gives public clients `public_client_token_ttl` = 120 min. `refresh_token.rb:29-37` extends the window by 2 h per refresh and forces refresh-token rotation (`overwrite: true`). Commit `a112b8fd` states: "Non-mobile public clients still have a 2hr expiration on refresh tokens… public clients (which are presently only used by Canvas Career)". | A PKCE public client makes students re-authorize after about 2 h of inactivity. BGAppRefresh can't guarantee a run inside 2 h, so widgets and background refresh go stale. Rotation also means two concurrent refreshes, or one lost refresh response, force a sign-in. |
| SEC-03 | **Blocker** | `LoginView.swift:69-80` saves `mock_canvas_token_<UUID>` to the Keychain. `CanvasOAuthManager.swift:66` never exchanges the code, and the OAuth manager is never called (baseline). | There is no real authentication, so no downstream security control can be tested. |
| SEC-04 | Major | `CanvasOAuthManager.swift:40-46` sends no `state`. There is no mix-up defence even though the app talks to many authorization servers (RFC 9700 §2.1 makes one **REQUIRED**). `:39` takes an unvalidated `baseURL` and force-unwraps it. `:53` uses the generic scheme `tally` (RFC 8252 §7.1 says apps MUST use a reverse-DNS scheme). `:19` ignores `SecRandomCopyBytes`'s status, so a failure yields an all-zero verifier. If `start()` returns false (`:70`), the continuation is never resumed. The Canvas `error=` callback is not handled. | CSRF/code injection and mix-up exposure, phishing-host input, scheme collisions, possible hang. |
| SEC-05 | **Critical** | `TallySecurity.swift:181-185`: any `canEvaluatePolicy` failure sets `isLocked = false` and returns `true`. That includes `biometryLockout`, which Apple says follows too many failed attempts. `:109` `isLocked = false` at launch, and lock is applied only on `.background` (`AppRootView.swift:40-44`), so a cold launch skips the lock. `:178` labels the cancel button "Use Passcode", but the policy is biometrics-only, so there is no passcode path. `:213-217` turns the lock off without authenticating. | The only local-auth control fails open. Anyone holding an unlocked phone can deliberately fail Face ID or force-quit and relaunch Tally, then read grades. Fails MASVS-AUTH-2. |
| SEC-06 | Major | `TallySecurity.swift:29` uses `WhenUnlockedThisDeviceOnly`, which Apple describes as "accessible only while the application is in the foreground". `:51-54` maps every `OSStatus` (including `errSecInteractionNotAllowed`) to `nil`, and `hasToken` feeds `isLoggedIn` (`AppRootView.swift:31`). `:22-32` deletes and then adds, which is not atomic. There is a single hard-coded account `"canvas"` (`LoginView.swift:80`, `SettingsView.swift:279`). | Background refresh can't read the token. A read while the device is locked looks like "logged out" and could trigger a wipe. A crash between delete and add loses a rotated refresh token for good. Multiple accounts are impossible. |
| SEC-07 | Major | `SettingsView.swift:277-284`: sign-out only deletes the Keychain item. There is no `DELETE /login/oauth2/token`, no cache purge, and pending notifications and calendar events stay. `:279` uses `try` on a non-throwing call, so the `catch` block is dead. `:271-273` "Clear Cache" only calls `print`. | The token stays valid at Canvas and remains listed in the student's Approved Integrations. Student data remains on the device after sign-out, and the PRD's cache-purge requirement (01 §9) is not met. Fails MASVS-PRIVACY-4. |
| SEC-08 | Major | `CanvasAPIClient.swift:8` defaults to `URLSession.shared`, which has a shared on-disk `URLCache` and cookie jar. `:27`, `:35` ignore the HTTP status, so a 401 surfaces as a JSON decode error and never triggers a refresh. Nothing guards against the bearer token following a cross-host redirect or pagination `Link`. Whether Canvas responses actually land in URLCache depends on their `Cache-Control` headers (UNVERIFIED); the design must not rely on it. | Raw grade JSON could persist outside the encrypted cache (MASVS-STORAGE-2). No 401 recovery. The token could leak to file-storage or CDN hosts. |
| SEC-09 | Major | `RefreshOrchestrator.swift:54-59` and `NotificationManager.swift:28-38` put "Calculus III Midterm" in the notification body. No `UNNotificationCategory` or `hiddenPreviewsBodyPlaceholder` is set. PRD 01 §7 plans threshold alerts ("course falls below 85%"). | Course, assignment and (soon) grade information appears on the Lock Screen and in Notification Center (MASVS-PLATFORM-3). |
| SEC-10 | Major | There are 11 `print()` sites. `CalendarSyncManager.swift:64` prints the **event title**. `ReminderEngine.swift:26`, `BackgroundSyncManager.swift:53` and `SettingsView.swift:283` interpolate raw `\(error)`. `TallyObservability.swift:1` is empty. The kit forbids logging titles (08:8). | This breaks the "logs never contain student content" rule. There is no privacy annotation, no levels and no event IDs. Whether `print` reaches the device's unified log in release builds is UNVERIFIED; I treat it as a leak either way. |
| SEC-11 | Major | The Settings row "All cached data is encrypted at rest" shows a green tick (`SettingsView.swift:127-139`). The cache is plain JSON (`CacheManager.swift:20-22`) and is never called (baseline). | A false security claim to users; it would also be a problem in App Review or an institution's security review. |
| SEC-12 | **Critical** | Canvas API Policy (effective 2025-08-12) prohibits "use of or access to our APIs for competitive purposes" and says "Your application should not mirror or replicate Instructure, our products…". App Review 5.2.2 requires the app be "specifically permitted… under the service's terms of use. Authorization must be provided upon request." | A student-facing Canvas client could be read as competing with Instructure's Canvas Student app. If so, Instructure could revoke keys or the app could be removed from the store. Tally needs written authorization (D4). |
| SEC-13 | Major | `ci.yml:12,38` pin actions to tags (`@v4`), not SHAs. `ci.yml:7` grants `actions: write`, which is unneeded (upload-artifact's README lists no token permission). `ci.yml:14` installs `xcodegen` unpinned. `ci.yml:2-4` runs only on push to `main`, with no PR gate. GitHub API readback: `main` **not protected**, Dependabot security updates **disabled**, `allowed_actions: all`, `sha_pinning_required: false`. There is no `.gitignore`. | Tag-hijack and supply-chain exposure. Nothing gates changes before `main`. Signing keys (`*.p8`/`*.p12`) could be committed by accident once the release lane exists. |
| SEC-14 | Minor | Secret scanning and push protection are **enabled** (API readback). A full-history grep for Canvas/GitHub/AWS/Google tokens and private keys found **no hits**. `Package.swift:20` has `dependencies: []`. | A positive baseline to preserve. |
| SEC-15 | Minor | `TallySecurity.swift:104,150`: the lock-enabled flag lives in `UserDefaults`, which is included in backups and editable. `Info.plist:8` bundle id and `TallySecurity.swift:11` service are hard-coded `com.tally.app`. There is no entitlements file (baseline). | The flag can be tampered with. Keychain and BG-task identifiers drift from the real bundle id. |
| SEC-16 | Minor | `CalendarSyncManager.swift:37` creates the "Tally Academic" calendar in the default source, which may be iCloud or a school Exchange account. | Course data syncs to a third-party or school cloud without an explicit choice of destination. That needs disclosure and consent. |
| SEC-17 | Minor | `SECURITY.md:1-3` has no vulnerability-disclosure process. `PRIVACY.md` is one line. | No way for researchers to report issues; weak story for institution security reviews. |
| SEC-18 | Minor | No URL schemes or universal links are registered today (`Info.plist`). The PRD wants "deep link back to Canvas" (01:46) and Handoff/universal links (01:74). Canvas assignment descriptions and announcements are HTML. | Future deep links, `html_url` opens and HTML rendering are injection and phishing surfaces (MASVS-PLATFORM-1/2, CODE-4). Controls must be designed in now. |

## 3. Target design

### 3.1 Canvas authentication — options and recommendation

Scoring key: **Sec** = security, **Pol** = Instructure/Apple policy, **Fit** = the owner's "no Tally account / no server retention of Canvas data", **Scale** = commercial scalability.

| Option | Sec | Pol | Fit | Scale | Verdict |
|---|---|---|---|---|---|
| **(a) PKCE public client, per-institution key** | Best. No secret, S256 PKCE, refresh token rotates each use, tokens never leave the device. | Compliant. | Full: no Tally server in the auth or data path. The only hosted pieces are a static signed registry and the AASA file. | Low: needs one admin action per school, and admins must create the key **via API** with `client_type=public` (documented; whether the admin UI exposes it is UNVERIFIED). Re-auth friction every 2 h (SEC-02). | **Primary** |
| (b) Embedded `client_secret` | Poor. RFC 8252 §8.5: secrets shipped in apps "should not be treated as confidential". Anyone can pull it from the IPA and run "Tally"-branded consent flows. Rotating it needs an app update. | Breaks the key custody schools expect, so revocation risk. | Fits (no server). | Same per-school bottleneck as (a); the only gain is long-lived refresh. | **Reject** |
| (c) Stateless zero-retention token-exchange broker | Secret stays server-side. But the broker sees every user's live access and refresh tokens (in transit), which makes it a high-value target. Confidential refresh tokens don't rotate, so a stolen refresh token keeps working through the broker. Needs App Attest, rate limits and verifiable no-logging. | Compliant with a normal confidential key. | Meets the **letter** (no Canvas content retained). But Tally then runs a service that handles credentials, and App Attest adds a pseudonymous server-side key registry. | Same per-school bottleneck. Better UX: confidential keys have no permanent expiry in the OSS code (`tokens_expire_in` returns `nil`). Adds ops cost, and a broker outage means no refresh after 1 h. | **Contingency** (only if WP-SEC-17 confirms SEC-02 and user testing rejects the friction) |
| (d) Manual token paste | Poor. Personal tokens are full-scope, long-lived secrets the student handles by hand. | **Explicit violation** of Canvas API Policy; students are blocked from creating them at some schools (UW–Madison). App Review 5.2.2 risk. | Fits. | Looks universal but the pool is shrinking, and one complaint could end it. A shipping competitor (DormWay) does this. | **Reject** |
| (e) Instructure global/partner key | Same as (a) or (c), depending on key type. | Best: sanctioned by Instructure. | Depends on key type. | Best available: one key, with each root admin toggling it (state "allow") or on by default ("on"). Whether Instructure grants this to a consumer student app is **UNVERIFIED**; the Partner tiers don't mention it. | **Pursue in parallel** (D4) |
| (f) Canvas calendar feed (ICS) "calendar-only mode" | The feed URL works as a bearer secret, so store it in the Keychain and never log it. Data is events and due dates only, no grades. | It's a documented, user-facing feature for third-party calendar apps and not an API token. Instructure's view on a commercial app using it is UNVERIFIED (fold into D4). | Full fit. | Universal with zero admin action, but it's only part of the product. | **Fallback** for schools without a key |

Instructure's own Canvas iOS app gets `client_id`/`client_secret` at runtime from the undocumented first-party endpoint `sso.canvaslms.com/api/v1/mobile_verify.json` (`canvas-ios` `MobileVerify.swift`, `APIOAuth.swift:20-26`). A third party using it would breach the API Policy's "Don't impersonate" rule. It's not an option for us.

**Recommendation: (a) + (f) + App Review demo mode now, (e) pursued in parallel, (c) designed but not built unless the D1 gate triggers it.**

This replaces the kit's implicit assumption (00:26, 01:57) that "OAuth + PKCE" alone makes Tally work anywhere.

### 3.2 Canvas OAuth flow (implementable spec)

1. **Institution registry (the host allow-list).** A signed JSON document: Ed25519 signature, public key compiled into the app, monotonically increasing `version` to block rollback. It ships bundled in the app and refreshes from a static CDN with an ETag. The request carries no identifiers or query strings.
   - Entry: `{id, displayName, canvasHost, clientId, redirectPath, scopes[], keyType:"public", minAppVersion?, status}`.
   - The student chooses from the list; **there is no free-text host for OAuth**, which is the anti-phishing control.
   - A school that isn't listed gets "Request my school" (no network call to the typed host) or ICS mode.
   - Pinning isn't needed for the registry: the signature protects its integrity even if TLS or the CDN is compromised.
2. **Host validator (pure function, used for registry entries and ICS feed URLs).**
   - Scheme is `https`; no userinfo; port absent or 443; no IP literals; lowercased; IDNA/punycode-normalised.
   - Reject mixed-script labels. Whenever a host is shown, show its punycode.
   - OAuth: host must **exactly** equal a registry host.
   - ICS: host must be in the registry or end in `.instructure.com`, and the path must match `^/feeds/calendars/user_[A-Za-z0-9]+\.ics$` (pattern from the Instructure Community guides; treat it as UNVERIFIED and tolerate variants).
3. **Authorization request** to `https://<host>/login/oauth2/auth`:
   - `response_type=code`, `client_id`, `redirect_uri=https://auth.<tally-domain>/oauth/canvas/<institutionId>`. A distinct redirect per institution is the RFC 9700 §4.4.2 mix-up defence; Canvas implements neither the `iss` parameter nor RFC 9207.
   - `state`: 32 CSPRNG bytes, base64url, single-use, held in memory with `{institutionId, verifier, createdAt}`, TTL 10 min. This matches Canvas's PKCE challenge TTL (`pkce.rb:23`).
   - `code_challenge` with `code_challenge_method=S256`, `scope=<registry scopes>`, `purpose=Tally for iOS` (shown in the student's Canvas Approved Integrations).
   - Add `force_login=1` when adding or switching accounts, so an existing Canvas session in Safari doesn't silently authorize the wrong user.
4. **ASWebAuthenticationSession.**
   - Use the `.https(host:path:)` callback (iOS 17.4+; the host must be an associated domain with `webcredentials`). **Register only this https redirect in every institution key.** A malicious app can't claim Tally's associated domain, so this stops public-client impersonation. The raw custom-scheme fallback does not.
   - Set `prefersEphemeralWebBrowserSession = false` by default: it reuses Safari's Canvas/SSO session, which makes 2-hourly re-auth tolerable, and iOS shows its own alert naming the domain.
   - Add a Settings toggle, "Private sign-in (shared device)", that sets it to `true` (D8).
   - Retain the session strongly, run it on the main actor, and treat `start()==false` as an error.
   - The callback page on the Tally domain must be static, set `Referrer-Policy: no-referrer`, load no third-party assets, and have **query-string logging disabled** at the CDN.
5. **Callback validation.** Exact host and path match. Compare `state` in constant time and consume it. Map `error=access_denied` to "cancelled". `code` must be present.
6. **Token exchange.** `POST https://<host>/login/oauth2/token` with `grant_type=authorization_code, client_id, redirect_uri, code, code_verifier` and **no secret**. Canvas `base_type.rb:38` accepts a blank secret only for public keys using PKCE.
   - **Do not send `replace_tokens`.** It destroys the user's other tokens for this key (`token.rb:86`), which would sign out their iPad when they sign in on their iPhone.
   - Check `token_type == Bearer`. On re-auth, require that `user.id` matches the stored account to prevent an account swap.
7. **Credential storage.** One Keychain generic-password item per account.
   - Contents: JSON-encoded `CanvasCredential {institutionId, host, userId, accessToken, refreshToken, accessExpiresAt, obtainedAt}`.
   - service `"<bundleId>.canvas.credential"`, account `"<host>#<userId>"`, accessibility **`AfterFirstUnlockThisDeviceOnly`** (D3). No access group, so extensions can't read it. Never synchronizable.
   - Writes use `SecItemUpdate`, falling back to `SecItemAdd` on `errSecItemNotFound`, never delete-then-add.
   - Reads return `.found / .notFound / .unavailable(errSecInteractionNotAllowed) / .error(OSStatus)`. **Only `.notFound` means signed out.**
8. **Token lifecycle: a `TokenCoordinator` actor with single-flight refresh.**
   - Canvas access tokens live 1 h ("Access tokens have a 1 hour lifespan"). Refresh proactively when less than 5 min remain.
   - Persist the new credential **before** releasing waiters.
   - Only the app process refreshes; widget and intent extensions never touch tokens.
   - The 10-second UI refresh budget must not cancel a token refresh already in flight.

   401 handling. Canvas adds `WWW-Authenticate` only for token errors, not scope errors (`application_controller.rb:2291-2307`):

   | Situation | Behaviour |
   |---|---|
   | 401 **with** `WWW-Authenticate` ("Invalid/Expired/Revoked access token") | Join or start a single refresh, retry the request **once**. |
   | 401 **without** `WWW-Authenticate` ("Insufficient scopes") | No refresh. Mark the feature unavailable for this school and log a scope event ID. |
   | 401 on a request while another request's refresh is in flight | Await that refresh result, then retry once. |
   | Refresh returns `invalid_grant`/400/401 (2-h window lapsed, revoked in Canvas settings, replaced by another device, admin or incident mass revocation — Instructure "revoked… access tokens" in May 2026) | Enter `.reauthRequired`: drop the tokens, **keep the cache and account record**, show the stale breadcrumb plus a "Sign in to refresh" banner. Background tasks stop. Local reminders keep firing from the cache. |
   | Refresh network failure or timeout | Keep the tokens and retry with exponential backoff. For public clients a lost response after the server has rotated the token becomes `invalid_grant` next time; this is unavoidable and handled by the row above. |
   | Retry after a successful refresh still returns 401 | Stop (no loop) and treat as `.reauthRequired`. |
   | App killed mid-refresh | Credential writes are atomic, so the old or new credential survives intact. The worst case is re-auth. |
9. **Sign-out** (a `SignOutUseCase`, ordered, best-effort network, guaranteed local purge):
   1. If the access token has expired, try one refresh.
   2. `DELETE https://<host>/login/oauth2/token` with the bearer token. Canvas's docs: it revokes the token and removes it "from the list of tokens on the user's profile page". `expire_sessions=1` only ends the session tied to the request's cookies, and Tally's ephemeral URLSession has none, so it **cannot** log out Safari. Say so in the UI.
   3. Whatever the network result: delete the Keychain credential, purge that account's cache (Encryption lane API), remove pending notifications with the account prefix, and remove the Tally calendar events if the user chooses.
   4. If revocation failed (offline), tell the student the token will expire on its own: about 2 h for public keys. Show them where Canvas lists Approved Integrations.
10. **Multi-account.** Key all storage, caches and notification IDs by `AccountID = host#userId` from day one. The v1 UI has one active account plus sign-out (D5). Adding an account always uses `force_login=1`.
11. **Scopes.** Ask institutions to enable "Enforce Scopes" (`require_scopes`) and request only `url:GET|…` scopes for self-data endpoints (courses, enrollments, assignments, submissions for self, calendar_events, planner, announcements, users/self). The Canvas-integration lane owns the final list. "Allow Include Parameters" must be on if `include[]` is used.
12. **Institution admin kit** (a 1-page doc for Canvas admins): create the key via `POST /api/v1/accounts/:id/developer_keys` with `developer_key[client_type]=public`, the https redirect, scopes, `require_scopes=true`; set the key state to **On**. Explain why there is no secret. Add a FERPA-oriented data-flow statement: no Tally server, on-device cache only.

**Contingency (c) broker, only if D1 = B:**
- Stateless function; per-institution confidential secrets in a managed secret store.
- Only endpoint is `POST /exchange` and `/refresh`, with egress allow-listed to registry hosts' `/login/oauth2/token`. **Never** proxies Canvas APIs.
- Request and response bodies are never logged; body size limits; TLS 1.3.
- App Attest assertion on every call (`DCAppAttestService`), which needs a per-install public-key store, i.e. server-side state that must be disclosed. Per-install rate limits.
- The app pins the broker's SPKI with a backup pin. PKCE stays on end to end (`AuthorizationCodeWithPKCE` works for confidential clients too).
- Publish a transparency page, and reflect the broker in the privacy label.

### 3.3 On-device threat model (STRIDE + OWASP MASVS v2.1.0)

**Assets:** Canvas credential; cached Canvas data (Encryption lane); ICS feed URL; notification content; widget and App Intent output; logs; registry integrity; future MS/Google tokens.

**Adversaries:**
- T1: casual physical access to an unlocked phone (roommate, friend).
- T2: stolen locked device.
- T3: malicious co-installed app.
- T4: network attacker.
- T5: phishing or lookalike host. Also a compromised real login page: Instructure reports that on 2026-05-07 the attacker made "changes… to student/teacher login pages".
- T6: CI or dependency compromise.
- T7: our own leaks through logs, caches or analytics.

**Out of scope:** a nation-state attacker extracting data from the device, and a student attacking their own data.

| STRIDE | Threat | Control (target) | WP |
|---|---|---|---|
| S | Lookalike or phishing Canvas host typed by the student (T5) | Registry pick-list, exact-host match, punycode display; the system browser shows the real URL and password managers only autofill on the true domain; never a WKWebView login. | 01, 12 |
| S | Malicious app runs Tally's public `client_id` (T3) | Only the https (AASA-bound) redirect is registered; the Canvas consent page names the app. | 05 |
| S | CSRF, code injection, mix-up across institutions | `state` plus PKCE plus a per-institution redirect path; callback host and path matched exactly. | 01 |
| T | Registry tampered in transit or on the CDN (T4/T6) | Ed25519 signature, version monotonicity, bundled fallback. | 12 |
| T | Lock flag edited or restored from backup | Flag stored in the Keychain (`ThisDeviceOnly`). | 07 |
| T | Modified app or jailbreak | Accepted (MAS-R not adopted, rationale below). App Attest only if the broker exists. | — |
| R | Disputed "the app did X" | Local event-ID log, no content, exported only by the user from Settings → Diagnostics. | 09 |
| I | Lock-screen notifications (T1) | Category `hiddenPreviewsBodyPlaceholder`, **no grade values ever**, thread ID per account (D7). | 10 |
| I | App-switcher snapshot | Privacy cover on `scenePhase == .inactive` whenever the app lock is enabled (the lock is currently applied only on `.background`). | 07 |
| I | Widgets, Siri and App Intents on the Lock Screen | `.privacySensitive()` on grade values; `authenticationPolicy = .requiresAuthentication` on intents that return grades; widgets read an app-written snapshot, never tokens. | 11 |
| I | URLCache and cookies persisting Canvas JSON (T7) | `URLSessionConfiguration.ephemeral`, `urlCache = nil`, `httpCookieStorage = nil`, `httpShouldSetCookies = false`. | 08 |
| I | Bearer token sent to another host (redirect, pagination, attachment CDN) | Redirect delegate strips `Authorization` when the host changes; pagination `Link` host must equal the account host; attachments are fetched without auth after Canvas redirects. | 08 |
| I | Logs (T7) | Privacy-safe facade (§3.4); `print`/`NSLog`/`dump` banned by lint. | 09 |
| I | Pasteboard | Read only via `PasteButton` (ICS URL); anything Tally copies uses `.localOnly` plus `expirationDate`; tokens are never copied. | 11 |
| I | Backups | Credentials are `ThisDeviceOnly`; the cache is excluded from backup (Encryption lane). | 04 |
| I | Canvas HTML (descriptions, announcements) | No JavaScript: sanitise to AttributedString, or WKWebView with `allowsContentJavaScript=false`, non-persistent data store, remote loads blocked except the account host, links routed through the URL validator (MASVS-PLATFORM-2). | 11 |
| I | Calendar export to a cloud source | Explicit destination choice plus disclosure (integration lane). | x-lane |
| D | Refresh-rotation race causes a forced logout | Single-flight coordinator; atomic Keychain write. | 03, 04 |
| D | Canvas rate limiting (the policy lets Instructure revoke tokens of apps that regularly exceed limits) | Honour `X-Rate-Limit-Remaining` (header name per Canvas docs, UNVERIFIED), backoff, no polling faster than the refresh policy. | x-lane |
| D | Lock with no recovery (Face ID locked out, passcode removed) | `.deviceOwnerAuthentication` with passcode fallback; if the passcode is removed, the only escape is "Sign out and erase", never an unlock. | 07 |
| E | Biometric bypass (SEC-05) | Fail closed (below). | 07 |
| E | Over-broad token | Scoped keys with `require_scopes`; never personal access tokens. | 11 (docs) |
| E | Deep link triggers an action | v1 registers no custom URL scheme for routing (ASWebAuthenticationSession needs none). Later universal links are read-only navigation with a strict parser. `html_url` opens only if `https` and host == account host, otherwise a confirmation sheet shows the host. | 11 |

**Biometric policy.**
- Use **`LAPolicy.deviceOwnerAuthentication`** (biometrics first, passcode fallback), not biometrics-only.
- Why: biometrics-only has no recovery on `biometryLockout` or when biometrics are unavailable. That leads either to failing open (today's bug) or to trapping the student. The passcode is already the device's root of trust, since anyone who knows it can re-enroll Face ID. So `evaluatedPolicyDomainState` checks add nothing against T1 and are not required.
- Rules:
  - Lock at cold launch **and** on `.background`; cover the screen on `.inactive`.
  - Evaluation failure, cancel or any `LAError` means **stay locked**.
  - `passcodeNotSet` means the toggle is unavailable. If the lock was enabled and the passcode was later removed, show "Set a device passcode, or Sign out" and do not unlock.
  - Turning the lock off requires a successful authentication (MASVS-AUTH-3).
  - Remove the misleading "Use Passcode" cancel title.
- MAS-L2 option **not** recommended: binding the cache key to a `.userPresence` Keychain item. Background refresh has to write the cache while the device is locked, so they are incompatible.

**Keychain accessibility vs BGAppRefresh (D3).** Credentials, the ICS URL and the lock flag all use `AfterFirstUnlockThisDeviceOnly`. Apple recommends that class for "items that need to be accessed by background applications"; it doesn't migrate to new devices. The cache key's class must match the cache writer's needs; the Encryption lane owns that.
- Trade-off: a forensic after-first-unlock extraction from a stolen device (T2) can read the token. For a student-grades threat model that's acceptable. The alternative is no background refresh or reminder updates while locked, which breaks PRD 01 §3 and §7.

**ATS and pinning.**
- ATS stays at its defaults. `Info.plist` has no `NSAppTransportSecurity` key today; add a CI check that none is ever introduced. Self-hosted Canvas instances without valid TLS are unsupported by design.
- **Do not pin to Canvas hosts.** MASTG says pinning must be "exclusively for the endpoints under their control", and MASVS-NETWORK-2 covers "remote endpoints under the developer's control". Institution hosts rotate certificates, CDNs and vanity domains, so a pin failure would take the app down for that school.
- Pin only the broker, if it is ever built. The registry is protected by its signature instead. This closes kit 09:17.

**Jailbreak posture.** No detection and no blocking. The data belongs to the device owner, detection can be bypassed, and blocking hurts legitimate users. MAS-R (MASVS-RESILIENCE-1..4) is deliberately not adopted. If the broker is built, server-side App Attest gives the integrity signal without client-side theatre.

**MASVS v2.1.0 mapping.** MASVS v2 no longer defines L1/L2 inside the standard. OWASP says they "have been reworked as 'MAS Profiles'" (MAS-L1, MAS-L2, MAS-R, MAS-P). The per-control profile assignment page did not render, so the L1/L2 column below is my target, not OWASP's table (UNVERIFIED).

| Control | Target | Today | Target control / WP |
|---|---|---|---|
| STORAGE-1 secure storage | L1+L2 | Partial (Keychain class wrong; cache is Encryption lane) | WP-04 + Encryption lane |
| STORAGE-2 no leakage | L1 | Fail (URLCache, print, notifications) | WP-08, 09, 10 |
| CRYPTO-1/2 | L1 | Encryption lane; the RNG status is unchecked (SEC-04) | WP-01 + Encryption lane |
| AUTH-1 secure protocols | L1 | Fail (mock token) | WP-01, 02, 03, 05, 06 |
| AUTH-2 local auth | L2 | Fail (SEC-05) | WP-07 |
| AUTH-3 step-up for sensitive ops | L2 | Fail (lock disabled without authentication) | WP-07 |
| NETWORK-1 secure traffic | L1 | Partial (ATS on; shared session) | WP-08, 11 |
| NETWORK-2 pinning | L2 | N/A for Canvas (not under our control) | Registry signature (WP-12); broker pin only if built |
| PLATFORM-1 IPC | L1 | N/A today; future deep links, intents, pasteboard | WP-11 |
| PLATFORM-2 WebViews | L1 | None today; Canvas HTML planned | WP-11 |
| PLATFORM-3 UI leakage | L1/L2 | Fail (notifications, snapshot) | WP-07, 10, 11 |
| CODE-1 current OS | L1 | Target 17.0 (platform lane decides) | x-lane |
| CODE-2 forced update | L2 | None | Registry `minAppVersion` (WP-12) |
| CODE-3 vulnerable deps | L1 | Pass (zero deps); no scanning | WP-13 |
| CODE-4 input validation | L1 | Fail (host, callback) | WP-01, 11, 16 |
| RESILIENCE-1..4 | MAS-R | Not adopted (rationale above) | — |
| PRIVACY-1..4 | MAS-P | Partial (no analytics; purge and revoke missing) | WP-06, 15 + privacy lane |

### 3.4 Privacy-safe logging facade (TallyObservability)

Design goals: developers **cannot** pass student content by accident; the facade is testable in the Linux container; it sinks to OSLog on Apple platforms.

```swift
public enum LogEvent: Sendable {          // closed set => reviewable
  case authStarted(InstitutionRef)          // AUTH-1001
  case authSucceeded(ms: Int)               // AUTH-1002
  case authFailed(AuthFailure)              // AUTH-1003 (enum, no strings)
  case tokenRefresh(RefreshOutcome)         // AUTH-1101
  case http(Endpoint, status: Int, ms: Int) // NET-5001 (Endpoint enum, never URLs: URLs carry course IDs)
  case syncTimedOut(afterMs: Int)           // SYNC-2004 …
  var id: String { … }; var level: LogLevel { … }
  var fields: [(String, SafeValue)] { … }
}
public enum SafeValue: Sendable { case int(Int), bool(Bool), token(String /* enum rawValue only */), hashed(String) }
public struct Redacted<T>: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
  public let value: T; public var description: String { "<redacted>" } /* same for debug/mirror */ }
```

- The facade exposes `log(_ event: LogEvent)` and nothing else: no `String` overload.
- IDs that could identify someone (course or user IDs) go through `.hashed`: HMAC-SHA256 with a per-install salt, truncated to 8 bytes. Because they are pre-hashed, the rendered line is safe to emit with `privacy: .public`. The OSLog sink uses `Logger(subsystem: bundleId, category: event.category)`, behind `#if canImport(os)`; the Linux test sink captures the lines.
- DTO fields holding names, titles, grades and HTML are wrapped in `Redacted<…>`, so `print(dto)`, `dump`, `String(describing:)` and error descriptions can't leak them.
- Errors are logged as a category enum (`URLError.Code`, `LAError.Code`, `OSStatus`), never as `\(error)`.
- Lint: a SwiftLint `custom_rules` regex bans `print(`, `debugPrint(`, `NSLog(`, `dump(` and `os_log(` outside `TallyObservability` and the test targets.

### 3.5 Supply chain and CI

- **`ci.yml`** (triggers: `pull_request` and `push` to `main`):
  - Top-level `permissions: contents: read`; nothing else unless a job needs it.
  - `concurrency` cancels superseded runs; `timeout-minutes` on every job.
  - `actions/checkout` with `persist-credentials: false`.
  - Every `uses:` pinned to a **full 40-character SHA** with a `# vX.Y.Z` comment. GitHub: "Pinning an action to a full-length commit SHA is currently the only way to use an action as an immutable release".
  - Jobs: SwiftLint, Linux `swift test` (container), macOS `xcodebuild test` on the simulator, `gitleaks` over full history (pinned SHA; adds generic patterns — the repo's non-provider patterns are disabled), CodeQL for Swift (supported; free on public repos), and a plist lint (no ATS exceptions, no custom schemes other than the OAuth one).
  - XcodeGen pinned by version and SHA-256.
  - Never use `pull_request_target` or self-hosted runners (public repo).
- **Repo settings (owner action, verify by `gh api` readback):**
  - Ruleset on `main`: require a PR and the status checks, block force-push.
  - Set "Require actions to be pinned to a full-length commit SHA" (the policy exists) and restrict allowed actions to GitHub-owned plus an explicit allow-list.
  - Enable Dependabot alerts and security updates. Add `dependabot.yml` for the `github-actions` and `swift` ecosystems (Swift v5/v6 is supported).
  - Keep secret scanning and push protection on (they already are).
- **`.gitignore`**:
  - Signing and secrets: `*.p8`, `AuthKey_*.p8`, `*.p12`, `*.cer`, `*.mobileprovision`, `*.provisionprofile`, `.env*`.
  - Build output: `apps/TallyiOS/build/`, `DerivedData/`, `*.xcodeproj/xcuserdata/`, `fastlane/report.xml`, `fastlane/README.md`.
  - Do **not** ignore the root `build/`, which holds tracked state files.
- **TestFlight lane (`release.yml`)**, triggered by `workflow_dispatch` or a `v*` tag:
  - `environment: testflight` with a **required reviewer (owner)** and deployment branches limited to `main` and tags. GitHub: "A workflow job cannot access environment secrets until approval is granted by a reviewer."
  - Secrets live only as **environment** secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_B64`, `DIST_P12_B64`, `DIST_P12_PASSWORD`, `PROFILE_B64`.
  - App Store Connect API key: a Team key with the **App Manager** role. Per Apple, App Manager can "Upload builds" and manage TestFlight; Developer cannot. Only Admin or Account Holder can generate keys.
  - Decode the key and certificates into `$RUNNER_TEMP`, import into a throwaway keychain with a random password, and delete it in an `if: always()` step. No `set -x`; `::add-mask::` any derived values.
  - Rotate the key yearly and whenever someone leaves. The owner keeps the offline copy in a password manager.
  - Don't publish signed IPAs as workflow artifacts; upload only to App Store Connect.
  - Add `actions/attest-build-provenance` (optional). Cloud-managed signing (`-allowProvisioningUpdates`) is an alternative that avoids storing a `.p12`; the key role it needs is UNVERIFIED.
- **Dependency budget:** stay at zero third-party packages for v1. Any addition (MSAL, GoogleSignIn) needs an ADR, a committed `Package.resolved`, and Dependabot coverage.

### 3.6 Optional Microsoft 365 and Google integrations

**Verdict: not in v1.** The same outcomes are available without OAuth:
- **Calendar:** EventKit writes to whichever calendar the student chooses. If they have added a Google or Exchange/Outlook account in iOS Settings, it appears as an EventKit source (`EKSourceType.calDAV` / `.exchange`) and iOS syncs it. Tally then holds no Google or Microsoft tokens. Note that write-only access can't list calendars; choosing a specific calendar needs full access, which the integration lane owns.
- **Mail:** `MFMailComposeViewController` or the share sheet. The student's Outlook or Gmail app sends the email, so no `Mail.Send` or `gmail.send` scope is needed. PRD 01 §7 already calls scheduled email "best-effort".
- **Opening in Office or Drive apps:** the share sheet and "Open in…". No Drive or Graph scopes.

**If and when they are built (v1.x), each provider gets its own OAuth.** They are separate authorization servers with separate client registrations, consent, Keychain items and revocation. They reuse the same credential-store and coordinator pattern.

| | Microsoft 365 | Google |
|---|---|---|
| Least-privilege scopes | `Calendars.ReadWrite` (least privileged delegated permission for "Create event", verified) + `offline_access`. No `Mail.Send`. | `calendar.app.created` ("Make secondary Google calendars, and see, create, change, and delete events on them"); fallback `calendar.events.owned`. Classification UNVERIFIED. No Gmail. If Drive export is ever needed: `drive.file` (**non-sensitive**, verified). |
| Verification burden | Publisher verification: free, needs a Microsoft AI Cloud Partner Program account and a verified domain. Without it, "users can't consent to most newly registered multitenant apps that aren't publisher verified" (under risk-based step-up). Many school tenants restrict user consent, so admin consent may be required. | Sensitive scopes need OAuth app verification. **Restricted** scopes (e.g. `gmail.readonly`, `drive`, `drive.readonly`) need restricted-scope verification, a CASA security assessment "if you store or transmit restricted scope data on servers", and reverification "at least every 12 months". `gmail.send` and `gmail.compose` are *sensitive* (verified). |
| SDK choice | **MSAL** (recommended). It supports the Microsoft Authenticator broker and Conditional Access, which school tenants often enforce; plain web auth may fail device-compliance policies. Costs: a dependency, the `msauth.<bundle>` scheme and a keychain group. | **Plain ASWebAuthenticationSession + PKCE** (iOS client type, no secret): zero dependencies and reuses the Canvas OAuth core. GoogleSignIn-iOS pulls in AppAuth, GTMAppAuth and GTMSessionFetcher. |

## 4. Decisions for the product owner

**D1 — Canvas authentication model.**
- Options:
  - A: PKCE public client, per-institution keys, no Tally server.
  - B: Confidential keys plus a stateless token-exchange broker.
  - C: A by default, B only for schools that refuse public keys.
  - (Manual token paste is not offered: it's non-compliant.)
- **Recommendation: A**, with B designed but gated on WP-SEC-17 evidence and a usability test of the re-auth cadence.
- Consequences:
  - A keeps the "no Tally server" promise and the best security, but students re-consent after about 2 h idle (SEC-02) and background refresh often finds the session expired.
  - B gives long sessions, but Tally runs a credential-handling service with an uptime SLO, App Attest and a privacy-label change; it is also a breach target.
  - C carries both costs.

**D2 — Launch scope, given per-school keys.**
- Options:
  - (i) Launch with one or more pilot institutions (key issued), plus ICS calendar-only mode for everyone else, plus a demo mode for App Review.
  - (ii) Wait for an Instructure global key.
  - (iii) Ship ICS-only v1.
- **Recommendation: (i).**
- Consequences:
  - (i) The owner must line up at least one Canvas admin before submission. Demo mode needs Apple's "prior approval" (Guideline 2.1).
  - (ii) Indefinite delay; availability UNVERIFIED.
  - (iii) No grades, so the core value proposition is missing.

**D3 — Token Keychain class.**
- Options: `AfterFirstUnlockThisDeviceOnly` vs `WhenUnlockedThisDeviceOnly`.
- **Recommendation: AfterFirstUnlock.**
- Consequences: AfterFirstUnlock enables background refresh and reminder rescheduling while locked, but a forensic after-first-unlock extraction could read the token. WhenUnlocked means no background refresh while locked, contradicting PRD 01 §3 and §7.

**D4 — Seek Instructure's written authorization and partnership before public launch.**
- Options: yes; or launch without it.
- **Recommendation: yes.** Join the Partner Program's lowest (Integrated) tier, whose benefits include a sandbox. Ask explicitly for:
  - written permission under the API Policy's "competitive purposes" and "mirror" clauses;
  - a global key;
  - "mobile app" refresh treatment for public keys (the 90-day path exists in code: `developer_key.rb:463`);
  - their position on ICS mode.
- Consequences: without it, App Review 5.2.2 or Instructure could remove the app or revoke keys at any time. Partner-program cost is UNVERIFIED.

**D5 — Multi-account in v1.**
- Options: one active account with multi-account-ready storage, or a full account switcher.
- **Recommendation: single active account.** Storage is keyed by account from day one, so the switcher can come later without migration.
- Consequences: a full switcher costs UI/QA effort and cross-account notification handling now.

**D6 — MS365/Google OAuth in v1.**
- Options: defer, or build.
- **Recommendation: defer.** EventKit plus compose and share sheets cover it (§3.6).
- Consequences: building now means publisher verification, sensitive-scope review, consent blocks in school tenants and one or two new SDKs.

**D7 — Lock-screen notification content.**
- Options:
  - (i) Titles in due-date reminders, iOS preview settings respected via placeholder, **never grade values**.
  - (ii) Always generic.
- **Recommendation: (i)**, plus a Settings toggle "Hide course names in notifications".
- Consequences: (ii) is the safest but makes reminders much less useful.

**D8 — OAuth callback and domain.**
- Options:
  - https callback on a Tally-owned domain (needs the domain, an AASA file and iOS ≥17.4).
  - Reverse-DNS custom scheme.
- **Recommendation: https.**
- Consequences: https needs a domain purchase plus a static host with query logging off, and resists client impersonation. A custom scheme is free and allowed by RFC 8252, but any app can register it.

## 5. Work packages

Verification legend: **Linux** = Swift-on-Linux container; **macOS CI** = GitHub Actions macOS runner and iOS Simulator; **device** = physical device or a real hosted Canvas.

| WP-ID | Title | Depends on | Acceptance criteria | How verified |
|---|---|---|---|---|
| WP-SEC-01 | OAuth pure core: PKCE (checked RNG), `state` store, authorize-URL builder, callback parser, host validator | — | RFC 7636 App. B vector passes. `state` is single-use with a 10-min TTL. Mismatched host, path or state is rejected. The validator table (IDN/mixed-script lookalikes, IP literal, `http`, userinfo, port) passes. No `!` force-unwraps. Crypto via `#if canImport(CryptoKit)`, with `swift-crypto` only on Linux (`.when(platforms:[.linux])`). | Linux |
| WP-SEC-02 | Token endpoint client + `CanvasCredential` model | 01 | Exchange and refresh requests have no secret and **no `replace_tokens`**. Decodes the fixtures for success, `invalid_grant`, 401 with and without `WWW-Authenticate`. Enforces `user.id` continuity on re-auth. | Linux (URLProtocol stubs) |
| WP-SEC-03 | `TokenCoordinator` actor + 401 state machine (§3.2 table) | 02 | 50 concurrent 401s trigger exactly one refresh. Persistence happens before waiters resume. There is no retry loop. The scope-401 path never refreshes. `.reauthRequired` keeps the cache. | Linux |
| WP-SEC-04 | Keychain `CredentialStore` | 02 | Atomic update-or-add. Typed read results (`notFound` vs `unavailable`). `AfterFirstUnlockThisDeviceOnly`, per-account key, no access group. The legacy `"canvas"` mock item is deleted on first run. | macOS CI (simulator unit tests). `errSecInteractionNotAllowed` path: device only |
| WP-SEC-05 | ASWebAuthenticationSession adapter + LoginView wiring + institution picker | 01–04, 12, D8 | `startMockOAuth` and the mock token are removed (grep gate). https callback. Ephemeral toggle. `force_login` on add-account. `start()==false` is handled. | macOS CI (XCUITest against a localhost mock authorization server using a test-only scheme config). Real https callback: device |
| WP-SEC-06 | `SignOutUseCase` (revoke, purge, notifications, calendar) + working "Clear Cache" | 03, 04, Encryption-lane purge API | Order per §3.2 step 9. Local purge happens even when offline. UI copy explains that Safari's session is unaffected. The dead `try` is removed. | Linux (fakes) + macOS CI |
| WP-SEC-07 | App-lock rewrite: pure `AppLockPolicy` state machine + `LAContext` adapter | — | Locks at cold launch. Cover on `.inactive`. Any `LAError` keeps it locked. `.deviceOwnerAuthentication`. Disabling requires authentication. Flag lives in the Keychain. `passcodeNotSet` path offers only sign-out. | Linux (state machine) + macOS CI (UI) + device (real Face ID lockout) |
| WP-SEC-08 | Networking hardening | 03 | Ephemeral config with no cache or cookies. Cross-host redirects strip `Authorization`. Pagination host check. Status mapping into `TokenCoordinator`. | Linux (URLProtocol) + macOS CI |
| WP-SEC-09 | Privacy-safe logging facade + replace all 11 `print()` sites + SwiftLint ban rule | — | `grep -rn 'print(' packages apps` finds none outside tests. Facade tests show no raw strings rendered. The lint rule fails the build on a planted `print(`. | Linux + macOS CI (lint) |
| WP-SEC-10 | Notification content builder + category placeholder | 09 | Pure builder never emits grade values. Category is registered with `hiddenPreviewsBodyPlaceholder`. Identifiers are prefixed by account. | Linux + macOS CI |
| WP-SEC-11 | Surface hardening: URL-open validator, Canvas HTML renderer policy, `.privacySensitive`, App Intent auth policy, `PasteButton`, plist/ATS lint script | 09 | Validator table passes. HTML renderer runs no JavaScript and blocks remote loads. The ATS/scheme lint fails on a planted exception. | Linux (validators) + macOS CI |
| WP-SEC-12 | Signed institution registry: format, offline signing script, verifier, bundled default, ETag fetch | 01 | Tampered, rolled-back or expired payloads are rejected. Falls back to the bundled copy. `minAppVersion` is honoured. The signing key never enters the repo or CI. | Linux |
| WP-SEC-13 | CI hardening (§3.5) + `.gitignore` + `dependabot.yml` + gitleaks/CodeQL jobs | — | Every `uses:` is a 40-char SHA. Top-level `permissions: contents: read`. Runs on PRs. XcodeGen pinned with a checksum. `gh api` readback shows branch protection, SHA-pinning required and Dependabot enabled (owner toggles). | macOS CI + `gh api` |
| WP-SEC-14 | TestFlight `release.yml` skeleton | 13, owner Apple account | Environment `testflight` with a required reviewer. Secrets only in the environment. Throwaway keychain cleaned in `always()`. No IPA artifact. | macOS CI (job skipped without secrets); first upload: owner/device |
| WP-SEC-15 | `SECURITY.md` disclosure policy + `PRIVACY.md` security sections + remove the false "encrypted at rest" row until Encryption WPs land | Encryption lane | Disclosure contact, supported versions and response SLA are present. The Settings claim either matches reality or is removed. | Doc review + macOS CI (UI snapshot) |
| WP-SEC-16 | ICS calendar-only mode: security parts (validator, Keychain storage, `PasteButton` input, fetch via hardened session) | 01, 04, 08, D2 | Feed URL never logged. Host and path validated. Stored `AfterFirstUnlockThisDeviceOnly`. | Linux + macOS CI |
| WP-SEC-17 | **Hosted-Canvas validation spike** (gates D1) | D4 sandbox or a pilot school | Written ADR with evidence covering: (1) whether `client_type=public` can be created via API and/or the admin UI; (2) PKCE exchange without a secret; (3) refresh rotation; (4) the actual permanent-expiry window; (5) `DELETE` revocation; (6) the re-consent experience after expiry with a non-ephemeral session. | Linux host (`curl` for the token calls) + device/browser |

## 6. Cross-lane notes

- **Encryption:** the cache key's Keychain class must follow D3. `URLCache` is a second at-rest store to eliminate (WP-SEC-08). Sign-out needs a per-account purge API. The widget snapshot's protection class must allow reading while locked, or the widget must redact. The Settings "encrypted at rest" claim (SEC-11) is theirs to make true.
- **Canvas integration/data:** final scope list; `Link` pagination constrained to the account host; per-account keyed repositories; remove the fake calendar and notification writes in `RefreshOrchestrator.swift:36-59`; rate-limit headers.
- **iOS platform/architecture:** minimum iOS ≥ 17.4 for https callbacks (D8). Entitlements file with `webcredentials:` associated domain. The real bundle id should drive the Keychain service and BGTask id. Widget and intent extensions never link the token store.
- **App Store compliance:** Guideline 5.2.2 authorization letter (D4). Demo mode needs prior approval (2.1). The 4.8 exemption applies ("client for a specific third-party service" / education account). The privacy label changes if a broker exists.
- **IP/legal:** API Policy "should not mirror or replicate Instructure"; users must understand Tally is "an independent resource" (copy and branding).
- **UX:** institution picker, "Request my school", re-auth banner, sign-out copy (Safari session caveat), privacy cover design, "Private sign-in" toggle, notification detail toggle.
- **DevOps:** merge WP-SEC-13/14 into the DevOps lane's pipeline plan rather than keeping two workflow designs.
- **Integrations:** the calendar destination choice and disclosure (SEC-16); whether write-only access is enough without calendar selection.

## 7. Sources

| URL | What it established | Status |
|---|---|---|
| https://canvas.instructure.com/doc/api/file.oauth.html | Manual-token violation of API Policy; keys scoped to the issuing institution; Cloud keys issued by the institution admin; "Access tokens are password equivalent" | VERIFIED |
| https://developerdocs.instructure.com/services/canvas/oauth2/file.oauth | Same policy sentence; 1-hour token lifespan; refresh-token use | VERIFIED |
| https://github.com/instructure/canvas-lms/blob/master/doc/api/oauth_endpoints.md | `state` guidance; `DELETE /login/oauth2/token`; no PKCE in the public endpoint docs | VERIFIED |
| https://developerdocs.instructure.com/services/canvas/resources/developer_keys | `developer_key[client_type]` create parameter: public clients "require PKCE… rotating refresh tokens… Immutable after creation" | VERIFIED (whether the admin UI exposes it: UNVERIFIED) |
| https://developerdocs.instructure.com/services/canvas/oauth2/file.developer_keys | Global keys created by Instructure employees; root admins enable or disable them | VERIFIED |
| https://canvas.instructure.com/doc/api/file.developer_keys.html | Scope format `url:<VERB>|<path>`; "Allow Include Parameters" | VERIFIED |
| canvas-lms `lib/canvas/oauth/pkce.rb` (S256 only, 10-min TTL); `grant_types/authorization_code_with_pkce.rb`; `grant_types/base_type.rb:38`; `grant_types/refresh_token.rb:29-37`; `app/models/developer_key.rb:449-463`; `lib/canvas/oauth/token.rb:81-119`; `app/controllers/oauth2_provider_controller.rb`; `app/controllers/application_controller.rb:2291-2307` | PKCE and public-client behaviour, the 2-h window, rotation, `replace_tokens`, 401/`WWW-Authenticate` semantics | Source-verified (OSS mirror, last push 2026-04-30); hosted UNVERIFIED |
| https://github.com/instructure/canvas-lms/commit/07125fa8456c935962cd0d1eb8b84ce8807f3524 | PKCE added 2024-09-26 (flag `pkce`) | VERIFIED |
| https://github.com/instructure/canvas-lms/commit/6383902d83cf23a2a346e3bfac5dcc6189b9eeba | `client_type` public/confidential added 2024-09-26 | VERIFIED |
| https://github.com/instructure/canvas-lms/commit/a112b8fd1670f1961ae89ad6774c55fb943f781c | "Non-mobile public clients still have a 2hr expiration on refresh tokens"; public clients used only by Canvas Career | VERIFIED |
| https://github.com/instructure/canvas-lms/commit/d0b9c225e63787991a51712b94e348ddd804f9bf | PKCE feature flag removed 2026-03-28 | VERIFIED |
| https://github.com/instructure/canvas-ios/blob/master/Core/Core/Features/Login/MobileVerify.swift and `APIOAuth.swift` | First-party app fetches `client_id`/`client_secret` at runtime from `sso.canvaslms.com/api/v1/mobile_verify.json` | VERIFIED |
| https://www.instructure.com/policies/canvas-api-policy | Effective 2025-08-12; "should not mirror or replicate"; "independent resource"; "competitive purposes" prohibited; token revocation for rate-limit abuse | VERIFIED |
| https://www.instructure.com/sites/default/files/pdf/integration-partnership-tiers-1-pager-2025.pdf | Partner tiers (Integrated/Certified/Professional) list sandbox, support and listings; no global key | VERIFIED (fees UNVERIFIED) |
| https://it.wisc.edu/academic-technology/learn-uw-news/change-to-student-access-tokens-in-canvas/ | Students can't generate tokens at UW–Madison from 2025-11-14 | VERIFIED |
| https://tdx.umsystem.edu/TDClient/66/MOOnline/KB/ArticleDet?ID=1852 | UM System reserves developer keys for "official, pre-approved, and critical integrations" | VERIFIED |
| https://dormway.app/blog/best-apps-that-sync-with-canvas-lms-2026 | A shipping student app uses personal access token paste ("No IT approval needed"); others use ICS or browser extensions | VERIFIED (vendor blog) |
| https://apps.apple.com/us/app/faster-canvas-tracker/id6760889725 | A third-party App Store app claims "secure OAuth" (key source unknown) | VERIFIED listing; mechanism UNVERIFIED |
| https://community.canvaslms.com/t5/Canvas-Basics-Guide/How-do-I-view-the-Calendar-iCal-feed-to-subscribe-to-an-external/ta-p/617607 | Calendar iCal feed is a user feature for external calendars | VERIFIED (via search summary) |
| https://www.instructure.com/incident_update ; https://en.wikipedia.org/wiki/2026_Canvas_data_breach | 2026 incident: login pages altered 2026-05-07; token revocation and key rotation | VERIFIED |
| https://www.rfc-editor.org/rfc/rfc9700 | OAuth Security BCP (Jan 2025): CSRF via PKCE/state; mix-up defence REQUIRED for multiple authorization servers; distinct redirect URIs allowed | VERIFIED |
| https://www.rfc-editor.org/rfc/rfc8252 | Reverse-DNS private schemes MUST; embedded secrets not confidential (§8.5) | VERIFIED |
| https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/callback/https(host:path:) | iOS 17.4+; host must be an associated domain | VERIFIED |
| https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/prefersephemeralwebbrowsersession | Ephemeral semantics; default `false` | VERIFIED |
| https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthentication and `…/deviceownerauthenticationwithbiometrics` | Passcode fallback; biometric lockout behaviour | VERIFIED |
| https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly and `…whenunlockedthisdeviceonly` | Background-access recommendation; no migration | VERIFIED |
| https://developer.apple.com/documentation/os/oslogprivacy | Privacy annotations and hash masks | VERIFIED |
| https://developer.apple.com/documentation/usernotifications/unnotificationcategory/hiddenpreviewsbodyplaceholder ; `swiftui/view/privacysensitive(_:)` ; `appintents/intentauthenticationpolicy` ; `uikit/uipasteboard/optionskey/localonly` ; `swiftui/pastebutton` ; `devicecheck/dcappattestservice` ; `eventkit/eksourcetype` ; `messageui/mfmailcomposeviewcontroller` | UI, IPC and integration controls cited in §3.3/§3.6 | VERIFIED |
| https://developer.apple.com/app-store/review/guidelines/ | 5.2.2 authorization; 4.8 exemptions; 2.1 demo mode with prior approval | VERIFIED |
| https://developer.apple.com/help/account/access/roles/ | App Manager can upload builds and manage TestFlight; only Admin/Account Holder generate API keys | VERIFIED |
| https://github.com/OWASP/masvs (release v2.1.0, 2024-01-18; `controls/*.md`; `Document/03-Using_the_MASVS.md`) | Control statements; L1/L2/R reworked as MAS Profiles | VERIFIED (per-control profile table UNVERIFIED) |
| https://github.com/OWASP/mastg/blob/master/Document/0x04f-Testing-Network-Communication.md | Pin only endpoints under your control | VERIFIED |
| https://docs.github.com/en/actions/reference/security/secure-use | SHA pinning; least-privilege `GITHUB_TOKEN`; environment reviewers; SHA-pinning policy | VERIFIED |
| https://docs.github.com/en/code-security/dependabot/ecosystems-supported-by-dependabot/supported-ecosystems-and-repositories | Dependabot supports `swift` (v5, v6) and `github-actions` | VERIFIED |
| https://docs.github.com/en/code-security/secret-scanning/introduction/about-push-protection | Push protection for users on by default for public repos | VERIFIED |
| `gh api repos/rahart1362/Tally` (+ `/actions/permissions`, `/branches/main/protection`) on 2026-09-26 | Secret scanning and push protection on; Dependabot off; SHA pinning not required; `main` unprotected; 0 secrets | VERIFIED |
| https://learn.microsoft.com/en-us/graph/api/user-post-events | `Calendars.ReadWrite` is least privileged for creating an event | VERIFIED |
| https://learn.microsoft.com/en-us/entra/identity-platform/publisher-verification-overview | Unverified multitenant consent restriction (post-2020-11-08); partner-program requirement; free | VERIFIED |
| https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/configure-user-consent | Admins can disable or limit user consent to verified publishers | VERIFIED |
| https://learn.microsoft.com/en-us/entra/msal/objc/ | MSAL iOS brokered auth and Conditional Access | VERIFIED |
| https://developers.google.com/workspace/gmail/api/auth/scopes ; https://developers.google.com/workspace/drive/api/guides/api-specific-auth ; https://developers.google.com/workspace/calendar/api/auth | Gmail/Drive scope classifications (`gmail.send` sensitive; `drive.file` non-sensitive); calendar scope descriptions | VERIFIED (calendar scope classification UNVERIFIED) |
| https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification | Security assessment when restricted data is stored or transmitted on servers; 12-month reverification | VERIFIED |
| — | Whether `print()` output reaches the unified log in release builds; whether Canvas responses are URLCache-eligible; `X-Rate-Limit-Remaining` header name; ICS feed path pattern; Instructure granting global keys to consumer apps; Partner Program fees | **UNVERIFIED** |
