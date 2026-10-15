# MVP-4 — App Review Readiness

Author: App Review Readiness Engineer (Claude Sonnet 5). Branch `mvp/review-readiness`, from
`origin/main` @ `5f6a730`. Commit under review: `3a8dd49`. This host has no Xcode; every
iOS-hosted claim below is sourced from a cited CI run or a downloaded Audit tour artifact, never
assumed.

## 1. The review-path proof (O6)

`apps/TallyiOS/TallyUITests/ReviewPathUITests.swift` (new). From a fresh install
(`resetAppState()`), Welcome → "Explore with Sample Data" (a root switch, asserted to remove
Welcome from the hierarchy — the only way to reach sign-in) → Dashboard → Courses → Course detail
with What-If → To-Do with Mark Done → Calendar → Insights → Settings (About, Subscription/paywall
display, parent mode) → the Sample Data family. Two leaf classes share one walk
(`ReviewPathUITestsBase.runReviewPathWalk`): `ReviewPathUITests` (English, the full walk including
the paywall's display) and `ReviewPathSpanishUITests` (es; skips only the paywall step, since the
Subscription interstitial is a plain SwiftUI `.alert` with no accessibility identifier in either
language — the one unavoidable English-label dependency, shared with `PaywallUITests`' own
helpers; every other lookup in both legs is an identifier).

- **No sign-in**: asserted directly (Welcome's CTA vanishes after the tap) and architecturally
  (Sample Data's own gateway, `SampleDataCanvasGateway`, has no `HTTPTransport` dependency in its
  init at all — it replays bundled fixtures from `TallySampleFixtures`).
- **No network request leaves the app**: a new test hook, `LaunchTestHooks.Key.trapAllNetwork`
  (`packages/TallyAppleKit/Sources/TallyFeatures/Launch/LaunchTestHooks.swift`), traps every seam
  the composition root wires an `HTTPTransport` into (`AccountEnvironment.transport`,
  `SignInServices.institutionSearch`/`makeTokenExchange` — the same two places
  `scripts/ci/check_policy_matches_app.py` reads for EB-07) and records each attempt into the
  existing `LaunchProbe` counter instead of answering. The existing `blockNetwork` hook only
  replaces one *signed-in account's* gateway, which Sample Data never builds, so it would prove
  nothing for this path. The count is read from `testHook.networkProbe`
  (`LaunchTestHookViews.swift`), the identifier `LaunchRefreshThrottleUITests` already uses for the
  same counter. The walk asserts it reads "· 0 requests" at the end, cumulative over the whole
  session.
- **Every screen shows content**: each step asserts a content identifier specific to that screen
  (`dashboard.hero.averageOfCourses`, `course.card`, `courseDetail.hero`, `whatif.projected`,
  `todo.row.notDone`/`todo.row.done` (before/after Mark Done), `calendar.day`, `chart.trend`,
  `settings.version`, `paywall.root`, `family.switcher`).

**CI result** (`scope=quick`, run
[38672412363](https://github.com/rahart1362/Tally/actions/runs/38672412363), 1h20m50s, all green):
`ios-build + test` xcresult `totalTestCount=710, passedTests=631, failedTests=0, skippedTests=77,
expectedFailures=2`. Both new tests passed on the first attempt, no retry, no failed-attempt
annotation: `ReviewPathUITests.testReviewPathShowsEveryScreenWithNoSignInAndNoNetwork` (134.337 s),
`ReviewPathSpanishUITests.testReviewPathInSpanishShowsEveryScreenWithNoSignInAndNoNetwork`
(121.532 s).

## 2. EB-06 — Privacy Policy link (Settings → About, Welcome footer)

Reuses `subscription.privacyPolicy` (`L10n.Subscription.privacyPolicy()`, "Privacy Policy") and
`SubscriptionLinks.privacyPolicy` (the paywall's own URL source) — **no new string**.

- **Settings → About** (`SettingsView.aboutSection`): a `Link` row below Version, styled like the
  existing Language row (`LabeledContent` + `arrow.up.forward`, the L10N-04 gate-2 "external link"
  convention), 44 pt minimum (the paywall's own D10 pattern). Identifier `settings.privacyPolicy`.
- **Welcome footer** (`WelcomeView.footer`): a small caption-sized `Link` under the disclaimer, in
  the scrolling footer, well clear of the two pinned CTAs. `WelcomeFlowView` already tints the
  whole onboarding stack `TallyColor.accent` (the FP-4/FP-5 fix), so no new tint code was needed;
  44 pt minimum. Identifier `account.privacyPolicy`.

### Before/after (Gate 1)

**Baseline corrected per PMO instruction mid-task**: the stale 2026-10-07 design-audit captures
(`pmo-audit/.build-audit/audit-*-*-*/named/`) predate the whole FP-1…FP-6 fix wave and would have
credited this work package with changes it did not make. Before = Audit tour
[38339844918](https://github.com/rahart1362/Tally/actions/runs/38339844918) on `ad7688f`
(`main @ 5f6a730` + test-only changes — UI-identical to this branch's base),
`pmo-audit/.build-audit/mvp2b/tour-before-38339844918/`. After = this work package's own Audit tour
dispatch, run [38686462804](https://github.com/rahart1362/Tally/actions/runs/38686462804) (all
methods, all 8 legs, `widgets=false`), on commit `3a8dd49`,
`pmo-audit/.build-audit/mvp4/after-38686462804/`.

| Change | file:line | Evidence (200% crop) | Layout-check delta |
| :--- | :--- | :--- | :--- |
| Welcome footer link | `WelcomeView.swift:167-175` | `evidence/eb06-welcome-footer-light-std.jpg`, `evidence/eb06-welcome-footer-dark-std.jpg` | **0 change on any of the 8 legs** — `overlap`/`offscreenOrClipped`/`hitTargetsUnder44pt` counts on `111-welcome-default.layout.json` are byte-identical before vs. after at every device × appearance × size (the pre-existing `overlap` findings, 2–7 depending on leg, are the ScrollView off-screen-elements-still-in-the-accessibility-tree pattern, unrelated to this change and unchanged by it). |
| Settings → About row | `SettingsView.swift:470-491` | `evidence/eb06-settings-about-proMax-light-std.jpg`, `evidence/eb06-settings-about-smallest-dark-std.jpg` | The new row added one row's worth of content, which pushed the page's later scroll-step captures down by one step on most legs (so a same-file-name before/after comparison compares different scroll windows, not the same content — not a meaningful signal either way). Direct, identifier-specific check instead: grepped every `*settings*.layout.json` in the after-tour (every leg, every scroll step) for `settings.privacyPolicy` — **zero matches**, i.e. the new row has no `overlap`, `offscreenOrClipped` or `hitTargetsUnder44pt` finding anywhere. |

`evidence/owner-sheet-mvp4.jpg` (1200×2783, 448 KB, under the 1.5 MB / 4000 px caps): both changes,
light and dark, two device sizes.

**AX5 on the smallest iPhone (brief's specific check for the Welcome link): partially verified, not
fully.** `AuditTourUITests`'s Welcome method captures only the unscrolled "default" state (no
scroll-step captures exist for Welcome in any leg, before or after); at AX5 the footer — like the
pre-existing disclaimer above it — sits below the fold in that single capture, so neither one is
visible at rest in the screenshot. What **is** verified: the automated layout check scans the
*full* accessibility snapshot regardless of scroll position (confirmed: the known pre-existing
`overlap` findings at AX5 include elements below the fold, e.g. "See where you stand" vs. the
pinned CTAs), and it reports **zero** `hitTargetsUnder44pt` or `offscreenOrClipped` finding
involving `account.privacyPolicy` on the smallest/AX5 leg specifically (or any leg). A direct,
scrolled-into-view screenshot of the footer at AX5 on the smallest iPhone does not exist in this
tour's output — **open item** below.

## 3. EB-17 — Settings footer under Sign Out & Erase

New key `settings.signOut.footer`, wired as `accountSection`'s `footer:`, shown only
`if isSignedIn` (`SettingsView.swift:264-270`; sample mode has nothing to sign out of and nothing
says "your school" for it).

**Strings PENDING owner approval:**

| Key | English | Spanish (`needs_review`) |
| :--- | :--- | :--- |
| `settings.signOut.footer` | Before you delete Tally, use Sign Out & Erase to end its access at your school. | Antes de eliminar Tally, usa Cerrar sesión y borrar para terminar su acceso en tu escuela. |

The English is the brief's own wording, verbatim (not mine to vary). The Spanish reuses the
catalog's existing translation of "Sign Out & Erase" (`account.signOutAndErase` → "Cerrar sesión y
borrar") and "your school" → "tu escuela", matching a dozen other strings per
`docs/l10n/es-glossary.md`.

**Open item**: this footer is signed-in-only, and the Audit tour's Settings captures are all
sample-mode (no signed-in Settings leg exists in this tour's output) — there is **no device/
simulator screenshot of this specific footer**, before or after. The code path is verified by
local review, `make lint` (0 violations) and the green `ios-build` run (the app compiles and runs
with the new conditional footer in place), but its *visual* appearance (wrapping, spacing) is
UNVERIFIED. Recommend a `-f tests=testN_settingsSignedIn` (or similar signed-in leg, if one exists
or is added) Audit tour dispatch before the owner approves the string, if a visual check is wanted
ahead of sign-off — out of this PR's remaining CI budget.

## 4. EB-07 — policy-matches-app CI check

`scripts/ci/check_policy_matches_app.py` (new, 332 lines, `--self-test` with 16 cases). Compares a
new, machine-readable `POLICY-FLOWS` comment in `site/privacy/index.html` (states what the prose
above it currently claims as active; the prose itself is untouched — counsel's and the owner's to
rewrite per dossier.md §12) against what `AppEnvironment.live()` and `SignInServices`'s own
defaults actually wire, across four flows: `canvas-api`, `school-search`, `school-list-download`,
`summary-sharing`.

```
POLICY | PASS | every flow the app wires is named active; every active claim is wired, or allow-listed
```

**Dated allowlist** (excuses only the overclaim direction, only for these three, named in the
script):

| Flow | Why it's allow-listed | Citation |
| :--- | :--- | :--- |
| `school-search` | Policy claims active; the app does not wire it (`SignInServices.institutionSearch` stays `UnavailableInstitutionSearch()` in `AppEnvironment.live()`) | dossier.md §12 P1, 2026-10-12 |
| `school-list-download` | Policy claims active; `ClientRegistry([])` is a literal empty list in `live()` | dossier.md §12 P1, 2026-10-12 |
| `summary-sharing` | Policy claims active; no code implements the feature at all (`BL-14`) | dossier.md §12 P2, 2026-10-12 |

A fourth allowlist-free case — `canvas-api` — is correctly claimed active and correctly wired; the
self-test also proves (by clearing the allowlist) that these three mismatches reappear without it,
and that a *new*, unlisted mismatch (in either direction) still fails. Wired into `ci.yml`'s
`hygiene` job, after the StoreKit check; the `workflow_dispatch.inputs.scope` block (PR #56/MVP-2c's
territory) is untouched.

## 5. EB-13 — App Store review notes

`docs/release/app-store/en-US/review_notes.txt` (new, 2,629 of 4,000 characters, marked "DRAFT:
owner and counsel review"). Covers the Guideline 4.8 education exemption, Sample Data as the demo
mode with an explicit request for Apple's prior approval under 2.1(a), the parent-mode basis
(5.1.1(viii)), "no Tally account", and the two permissions actually requested (Notifications for
local reminders; Face ID/Touch ID/passcode for optional App Lock — read from
`apps/TallyiOS/project.yml:99` and `UNNotificationScheduler.swift:190`; no Calendar/Contacts/
Photos/Camera/Location permission exists in the app). Every sentence checked against a `path:line`
on `main`.

**Open item**: `scripts/ci/check_release.py:111` defines `METADATA_DIR = "docs/release/metadata"`
(flat, no locale folder) and expects `review_notes.txt` plus four other files there (`name.txt`,
`subtitle.txt`, `keywords.txt`, `promotional_text.txt`, `description.txt` — none exist yet), not at
the brief's `docs/release/app-store/en-US/` path. That check (`REL.metadata.store-listing`) is
`due="M5"` and runs only from `release-gate.yml`'s manual dispatch (never this PR's own CI, which
runs `check_release.py --self-test` only), so this path has no effect on this PR's gate. Filed for
the PMO/M5 store-listing work package to reconcile when the other four files are written — not
fixed here (restructuring that script is outside this item's scope).

## 6. CI run IDs and results

| Run | Scope | Result | Notes |
| :--- | :--- | :--- | :--- |
| [38672412363](https://github.com/rahart1362/Tally/actions/runs/38672412363) | `scope=quick` | **PASS** | Hygiene, TallyCore (Linux + sanitizers + perf), SwiftLint, iOS build+test all green. 1 of 2 budgeted quick runs used. |
| [38679546635](https://github.com/rahart1362/Tally/actions/runs/38679546635) | `scope=a11y` | **FAILED** — pre-existing, see §7 | 1 of 1 budgeted a11y run used; not re-dispatched (deterministic, not a flake). |
| [38686462804](https://github.com/rahart1362/Tally/actions/runs/38686462804) | Audit tour, all methods, 8 legs | **PASS** (all 8 leg jobs green) | 1 of 1 budgeted Audit tour dispatch used. |

## 7. Open items

1. **`scope=a11y` run 38679546635 failed, but every failing (element, audit type) pair pre-dates
   this PR.** All three sub-passes failed broadly (Light 3/16, Dark 3/16, Increase Contrast 4/16)
   across nearly every screen in the app — not specific to Welcome or Settings, and not specific to
   any file this work package touched. Cross-checked against `docs/pmo/a11y-waivers.md` ("Real
   issues found, not yet fixed"), written from an earlier `scope=a11y` run (38313859274): it
   already names, as open, `Welcome/account.exploreWithSampleData` (contrast, dynamicType),
   `Settings/settings.exitSample` (dynamicType) and `Paywall/paywall.restore` (contrast) — three of
   this run's exact failures — plus a documented, unresolved "widespread, unidentified contrast and
   dynamicType issues" category (a design-token gap: `text.primary`/`bg.canvas`/`bg.card` lack a
   High Contrast appearance) that matches this run's shape and scale. Grepped the complete job log
   for every string this PR introduces (`privacyPolicy`, `signOut.footer`/`signOutFooter`, and the
   new footer's own English text): **zero matches**. This PR introduces no new accessibility
   finding; fixing the inherited, pre-existing, app-wide gap is MVP-2/EB-09's remediation work (a
   device-verified colour-token pass this host cannot perform), not this work package's.
2. **EB-17's Settings footer has no device/simulator capture** (signed-in-only; the Audit tour's
   Settings legs are all sample-mode). Code-verified, not visually verified. See §3.
3. **Welcome link's AX5/smallest-iPhone state has no scrolled-into-view capture** (the tour's
   Welcome method only captures the unscrolled top). Layout-check-verified (zero findings
   involving `account.privacyPolicy` on any leg including smallest/AX5), not screenshot-verified
   at rest scrolled down. See §2.
4. **`docs/release/app-store/en-US/review_notes.txt` vs. `check_release.py`'s
   `docs/release/metadata/` path mismatch.** See §5. Does not block this PR's own CI.

## 8. Evidence paths

- `pmo-audit/.build-audit/mvp4/after-38686462804/` — the full Audit tour download (8 legs).
- `pmo-audit/.build-audit/mvp4/evidence/` — the 4 before/after crops + the owner sheet (not
  committed to the repo; images never go in a public repo).
- `pmo-audit/.build-audit/mvp4/make_crops.py`, `make_owner_sheet.py` — the generation scripts.
- Journal: `build/logs/journal/2026-10-14-mvp4.md`.

## PMO fixes after gate 2 (2026-10-15)
Gate 2 (Opus, `pmo-audit/.build-audit/mvp4/review/verdict.md`) failed the review notes on two S2s. The PMO fixed those and the recommended items:
- **N1/N2/N3, review notes:**
  - Sample Data is now described as "Tally itself sends nothing over the network", with StoreKit and Safari named as the only network activity.
  - The header no longer claims every sentence is true of this build. Sentences that depend on decisions not yet made (a school enabled for sign-in, real-account parent linking) are marked `[AT SUBMISSION]`.
  - The subscription path is spelled out (Settings → Subscription → See Plans → Continue), and so is the calendar label ("Subscribe to Canvas Calendar").
- **V1:** the Settings Privacy Policy row drops its redundant `.frame(minHeight: 44)`, which made it 74 pt tall against its 51–52 pt neighbours. A Form row is already at least 44 pt.
- **T1:** `testG` ran at 97% of its 300 s cap on `main` and timed out on the smallest iPhone in dark at AX5 (tour 38695020712).
  - The Makefile's cap is now `IOS_MAX_TEST_ALLOWANCE` (default 300, so CI is unchanged).
  - The Audit tour passes 600, and the tour methods use `AuditTourUITests.tourAllowance` (560).
- **P1:** `check_policy_matches_app.py` also detects `….institutionSearch = …` and `….registry = …` assigned anywhere in `live()`, with a self-test case for it (9 of 9 pass).
- **S4-1, a correction:** §3 above says no capture of the signed-in footer exists. It does: the PMO's tour 38695020712 shows it on 7 of 8 legs (`pmo-audit/.build-audit/mvp4/footer-for-approval.jpg`), and the owner approved the string on 2026-10-15 (the catalog comment is updated).
- **Not done:** S4-6 (mapping ReviewPath to a `REL.flow`) is left for MVP-3, which owns `check_release.py`. Counsel items C1–C6 go to the owner's attorney.
