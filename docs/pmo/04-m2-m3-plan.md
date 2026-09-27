# M2–M3 work breakdown (next engineering batches)

This file sequences the next teams. Use the same brief (`03-implementation-brief.md`) and the same model: one worktree per team under `~/Documents/Tally-worktrees/`, with the PMO verifying and merging. iOS work is validated on GitHub macOS runners. Only the iOS teams may push, and only their own branch.

## Gate: start when `m2/app-shell` is merged
The shell provides `TallyAppleKit` (DesignSystem, Platform, Features, Intents), the `Tally` app, the `TallyWidgets` extension, test targets, CI on an iOS 26 simulator, design tokens and the static Welcome screen.

## Batch M2-B: three teams in parallel
| Team | Work packages | Notes |
|---|---|---|
| **Platform adapters** | E03: `URLSessionTransport` (ephemeral, no cache or cookies; SEC-08), `OSLogLogger` (typed events only), `KeychainCredentialStore` (`AfterFirstUnlockThisDeviceOnly`, atomic update-or-add; SEC-04), `KeychainVaultKeyStore` (ENC-03), `ProtectionState`, the `UNNotificationScheduler` adapter for `NotificationScheduling`, `WidgetReloader`, and the `LAContext` adapter for `AppLockPolicy` (SEC-07). ENC-05: App Group Keychain group; widget read path. | Hosted tests on the simulator. |
| **App core + sample-data mode** | E04: composition root; `AppModel` / `RefreshStatusModel` over `RefreshCoordinator` events; Dashboard over the glance. UX-WP-05 tab shell (Insights, not "More"). UX-WP-06 `FreshnessPresenter` + breadcrumb. UX-WP-13 Dashboard. **ASC-14 "Explore with Sample Data"**: the bundled `fixtures/canvas` personas behind a replay transport, a persistent SAMPLE banner and no network (asserted). | Depends on M1 sync (`RefreshCoordinator`). Sample mode is also the App Review path (GL-04). |
| **Onboarding + sign-in** | UX-WP-07 Welcome / brand moment. UX-WP-08 school search over `InstitutionDirectory` + the signed registry (all states: not enabled → "Ask My School"). UX-WP-09 sign-in hand-off. F02 / SEC-05 `ASWebAuthenticationSession` with the `.https(host: tally-app.dev, path: /oauth/callback)` callback and a `webcredentials` associated-domain entitlement; PKCE/state via TallyCanvasAPI; `TokenEndpoint` exchange → `TokenCoordinator`. UX-WP-10 first-sync skeleton. Lock screen and privacy cover (UX-WP-21 visuals). | The callback needs the AASA published on tally-app.dev and a Team ID (GL-02). Until then, test with the stubbed token endpoint. |

## Batch M3: features
- **Screens:** E05a–e and UX-WP-14…20 (Courses, Course Detail + what-if sheet, To-Do, Calendar with ICS subscribe + Add to Calendar per R6, Insights, and Settings as a `Form` with Sign Out & Erase).
- **Widgets and intents:** E06 + integrations R19 (Home, Lock and StandBy widgets; Control Center; App Shortcuts; Focus filter).
- **Notifications:** E07 wiring of `ReminderPlanner` → `NotificationReconciler` → the UN adapter; permission priming in context (UX-WP-12).
- **Family UI:** FAM-08…11, FAM-14 (sample family mode).
- **StoreKit 2:** the "Tally Annual" ($9.99/yr, 1-month trial) and "Tally Parent" ($4.99/yr per parent) groups, a StoreKit configuration file for tests, paywalls per PRD §11.3 / §11.9, and the Canvas-access gating.

## Later
- **M4 (needs a real Canvas key, GL-01):** the GL-05 / FAM-01 spikes, and the B07 fixture recorder run by the owner.
- **M5:** hardening: the release-gate workflow, accessibility audit, screenshots, privacy manifest and plist checks, and G01 legacy deletion (root `Package.swift` and the old `packages/Tally*` modules).
