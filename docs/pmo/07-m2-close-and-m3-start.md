# 07 — Closing M2 and starting M3

**Owner direction (2026-09-28):** "Monitor the M2 iOS shell for completion and validate accordingly once that is confirmed. In the interim, proceed to the next."

**Baseline:** `main` at `24d3cdf` (PR #1). `main` is protected; every change lands through a PR with the required checks green.

## 1. M2 audit against the program plan (PMO, on `main` @ `24d3cdf`)

M2's exit gate (`02-program-plan.md` §3): "App boots from cache in the simulator, <300 ms warm; 12-s slow replay shows the breadcrumb, which self-heals."

| Work package | Status | Evidence, or what is missing |
|---|---|---|
| ARC E01: TallyAppleKit and the `project.yml` rewrite | Done | app-shell merge; the identity step prints `dev.tally-app.tally` |
| ARC E02: macOS CI | Done | `ios-build` (tests, floor, smallest iPhone, binary gates) and `ios-asan` are required |
| ARC E03: platform adapters | Done except the `LAContext` adapter | platform merge. **Missing: the `LAContext` adapter (PL-03), see SEC-07** |
| ARC E04: composition root, Dashboard over the glance, `backgroundTask` | **Partial** | The 12 s slow-refresh breadcrumb criterion is met (`SlowRefreshUITests`). **Missing: "cache renders before network" and the warm boot under 300 ms** (plan 06 step 8, the launch bootstrap) |
| SEC-04: Keychain credential store | Done | platform merge |
| SEC-07: app lock | **Missing** | `AppLockPolicy` is pure and lives in TallyCore. **Missing:** the `LAContext` adapter (async API only), the lock view, and the privacy cover on `.inactive`, in ADR 0001's order: privacy cover, then lock, then cached render, then handshake |
| SEC-08: `URLSessionTransport` | Done | the 7b streaming cap. The timeouts (O5) remain |
| ENC-03: `KeychainVaultKeyStore` | Done | platform merge |
| UX-WP-02: type tokens | Done | The one `system(size` match on `main` is a doc comment in `TallyTypography.swift` |
| UX-WP-03: launch colour and no runtime PNGs | Done | `UILaunchScreen.UIColorName: LaunchBackground`; no `TallyLogo`/`TallyEmblem` files in the repo. A11Y-14 is re-checked at M2 validation |
| UX-WP-05: tab shell | Done | app-core |
| ASC-01: bundle identity and Info.plist base | Done | `TARGETED_DEVICE_FAMILY: "1"`, portrait only, IDs derived from the bundle ID |
| ASC-03: privacy manifest | **Partial** | `PrivacyInfo.xcprivacy` exists in the app and the widget. **Missing:** the script that cross-checks source symbols against the declared required-reason API categories |
| ASC-09: background refresh registration | Done | `.backgroundTask(.appRefresh)` in `TallyApp`, registered once |
| ASC-10: `release-gate.yml` | **Missing** | Jobs per the ASC review §3.3.1. For M2 the workflow must exist and run (manual dispatch); making it fully green is M5's exit |
| ASC-11: mock Canvas server | **PMO ruling** | The in-process `ReplayTransport` covers the scenario replays M2 needs, including delays over 10 s and errors (the slow-refresh tests use it). A localhost server is deferred to M5's release gate, if it proves necessary |
| ASC-14: sample data | Done | app-core |

## 2. Workstreams, run in parallel from `main`

Each has its own worktree under `~/Documents/Tally-worktrees/` and a fresh agent with a binding brief. The PMO opens and merges the PRs.

| Stream | Branch | Scope | Owns (other streams do not edit) |
|---|---|---|---|
| **M2-C1 lifecycle** | `m2/lifecycle` | Plan 06 step 8 (launch bootstrap, the M2 exit gate: cache before network, warm glance paint under 300 ms); step 9 (replay-backed sign-in first sync, then a root switch); step 10 (the sign-out order and leak proofs); **SEC-07** (the `LAContext` adapter, lock view, privacy cover) | `RootView`, `AppModel`, `TallyApp`, `Launch/*`, `Account/*`, `Onboarding/FirstSync*`, `Lock/*`, the `TallyPlatform` LAContext adapter |
| **M2-C2 widget and compliance** | `m2/widget-compliance` | Plan 06 step 11 (a glance-only widget, the memory gate, no `TallyFeatures` link); **ASC-03** (the privacy-manifest cross-check script plus a hygiene step); **ASC-10** (`release-gate.yml`, manual dispatch); O5 (transport timeouts); O12 (the TSan race, then make `ios-tsan` required); O8, O9, O11 | `apps/TallyiOS/TallyWidgets/*`, `scripts/ci/*` (new), `.github/workflows/release-gate.yml`, `URLSessionTransport` and its tests, `TallyUITestCase` |
| **M3-A screens** | `m3/screens` | E05a–e and UX-WP-14…20: Courses, Course Detail plus the what-if sheet (through `GradeWork`), To-Do, Calendar (ICS subscribe plus Add to Calendar, R6), Insights, Settings (a `Form`: Sign Out & Erase calling `AppModel.signOut()`; the "What changed" threshold, All or points, global and per course, into `UserState.digestThresholds` and then `RefreshCoordinator.updateDigestThresholds`). Every screen runs on real domain data in sample mode, with UI tests per screen | New files under `TallyFeatures/{Courses,CourseDetail,ToDo,Calendar,Insights,Settings}/`. Edits to `HomeShellView`, `HomeModel` and `HomeProjector` must be additive |

**Merge order:** M2-C1 and M2-C2 first. Then the **PMO's M2 exit validation** (§3). Then M3-A: it merges `main` and resolves conflicts before its PR.

**CI capacity:** GitHub allows 5 concurrent macOS jobs on this plan, and a full run uses 6. Engineers' iteration runs therefore use `gh workflow run CI --ref <branch> -f scope=quick`: the Linux jobs plus `ios-build`. Every hand-off run and every PR runs full.

## 3. M2 exit validation (the PMO, once M2-C1 and M2-C2 are merged)

1. Warm launch to the painted glance: `Launch.GlancePaint` median ≤ 300 ms on the CI simulator (`XCTOSSignpostMetric`), plus `XCTApplicationLaunchMetric` recorded. The cache must render before the network: a UI test with the network blocked paints cached rows.
2. A 12 s slow replay shows the breadcrumb, which then clears on its own. `SlowRefreshUITests` must be green in the validation run.
3. SEC-07:
   - the app locks at cold launch;
   - the cover shows on `.inactive`, checked by a UI test and a screenshot;
   - any `LAError` keeps it locked;
   - only the async `LAContext` API is used, enforced by the hygiene gate.
4. Sign-in to first sync, then a root switch; sign-out leaves no reachable `CanvasSnapshot`. Both are checked by weak references and the DEBUG instance counter.
5. Widget: reads the glance only, links no `TallyFeatures`, and stays inside its memory budget.
6. ASC-03: the script passes, and a mutation (an undeclared required-reason API) fails it. ASC-10: `release-gate.yml` runs.
7. Every required check is green on the validation commit. The PMO re-reads the logs, runs 2-4 mutation checks of its own, and records the result in the journal. Only then is **M2 marked complete** in `02-program-plan.md`.

### 3.1 Result (the PMO, 2026-09-28): M2 complete

The validation run is 36494900022, PR #3's full run on `809eee1` (M2-C1 + M2-C2 + the O9 fix). Every required job is green; the logs were read.

1. **Launch:**
   - `LaunchFromCacheUITests` passed. It shows 0 Canvas requests before the cached paint, then the stale breadcrumb at the live budget; that check was restored after the O9 fix.
   - `Launch.GlancePaint` median 2.06 s on the CI simulator. The previous medians were 1.97 s and 1.53 s.
   - `XCTApplicationLaunchMetric` median 3.80 s was recorded.
   - **Owner decision O10:** a required CI-simulator gate of 3.0 s median (`perf/budgets.json`, `ios-perf` required). 300 ms stays the on-device target (D-P3).
2. Both `SlowRefreshUITests` passed.
3. **SEC-07:** all four `AppLockUITests` passed: cold-launch lock, the cover on `.inactive`, a cancel keeping it locked, and the real `LAContext` on the simulator. The PL-03 async-`LAContext` gate is in hygiene.
4. `SignInSignOutUITests` passed: sign-in, first sync, root switch, then sign-out. `SignOutTests` also passed, covering the seven steps and the instance counter.
5. **Widget:** the link-map and binaries gates passed, and the memory median delta passed its budget in M2-C2's run 36491573304 and in 36494900022.
6. **ASC-03:** the check passed in hygiene. **ASC-10:** `release-gate.yml` ran (36465775989).
7. **PMO mutation checks,** each caught and restored byte-identical (journal):
   - O9 (the old task-group race);
   - PM1 (ASC-03, an undeclared `UserDefaults`);
   - PM2 (widget isolation, `import TallySync`);
   - PM3 (PL-03, callback `evaluatePolicy`);
   - the glance-selection parity test (OI3).

`ios-tsan` is required from 2026-09-28.

## 4. M3 streams to start after M2 closes (or when capacity allows)

- **M3-B StoreKit 2:** Tally Annual ($9.99/yr, 1-month trial); Tally Parent ($4.99/yr per parent); a StoreKit configuration file; paywalls (PRD §11.3, §11.9); purchase gated on a working Canvas connection.
- **M3-C notifications (E07):** `ReminderPlanner` → `NotificationReconciler` → the UN adapter in the post-commit pipeline; in-context permission priming (UX-WP-12).
- **M3-D widgets and intents (E06, R19):** Home, Lock and StandBy widgets; Control Center; App Shortcuts; Focus filter. Builds on M2-C2's widget.
- **M3-E family UI:** FAM-08…11, FAM-14 (sample family mode).
- **Core follow-up PERF-06:** the 5-6x Apple-silicon gap.
