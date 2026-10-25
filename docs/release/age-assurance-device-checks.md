# Age-assurance device checks (AGE-1, EB-01/EB-04)

**The owner runs these on a physical device, with a sandbox Apple Account.** None of this can run
on CI: `DeclaredAgeRange`/`PermissionKit` have no effect in the Simulator (Apple's own sandbox
guide, `StoreKit/testing-age-assurance-in-sandbox`, is device-only), and a parental-consent
revocation needs a real family Apple Account and the real App Store's launch-block, which this
repo cannot simulate or observe (AGE-1's non-goal: no Tally server, no App Store Server
Notifications endpoint — Tally has no way to *detect* a revocation itself; it can only be verified
to *respect* Apple's own block).

Set up: a sandbox Apple Account in a Family Sharing group with at least one child/teen member
(App Store Connect → Users and Access → Sandbox → Testers), per Apple's sandbox age-assurance
guide. Sign in to iCloud with it on the test device before each check below.

## EB-01: the request itself

1. **Fresh install, adult account.** Delete any existing install, reinstall, sign into Sample
   Data or a test school. Expect the system age-range sheet once, on this first launch. Confirm:
   no birthdate field anywhere in it or in Tally's own UI (it is entirely Apple's system sheet).
2. **Fresh install, a sandbox minor account** (13–15, then 16–17, then under 13 — three separate
   installs or a reset age range between runs, per Apple's sandbox age-assurance doc). Confirm
   Tally's Dashboard renders normally for each (EB-01(d): the safety defaults — widget grades off,
   no grades in notification text, quiet hours 23:00–07:00 — already apply to everyone, so nothing
   visibly changes by category; confirm by checking Settings → "What Tally Stores" shows the same
   defaults regardless of which sandbox age was used).
3. **Decline sharing.** At the system sheet, decline. Confirm Tally continues normally (EB-01(g):
   never blocks) — Dashboard renders, no restricted screen. This is `AgeAssuranceOutcome.declined`
   (AGE-2): the person's own choice, and it counts as this device's request for the 12-month floor
   exactly as before.
4. **Simulator parity.** Launch the same build in the Simulator. Confirm the same "no blocking,
   app behaves as today" result — `DeclaredAgeRangeAdapter.requestAgeAssurance()` has no window to
   present from there and returns `.unavailable` (AGE-2), the same never-blocks path as a decline.
   Unlike a decline, `.unavailable` is never recorded as a request: relaunching the same Simulator
   build asks again every time (confirm this — do not expect the 12-month floor to apply here).
5. **The 12-month floor.** Not practically re-runnable on a device in real time; covered instead
   by `AgeAssuranceTests.swift`'s `twelveMonthsIsDue`/`justUnderTwelveMonthsIsNotDue` (pure, exact
   calendar-month arithmetic). Record here only that the pure test exists and passed (CI run ID in
   the PR), not a device observation.

## EB-02/EB-03: significant change (no concrete change ships in AGE-1 — exercise the mechanism only)

6. Force `TallyConfig.currentReleaseIsSignificantChange = true` in a local build (never commit
   this), install fresh as a sandbox minor who already completed check 2 above, relaunch. Confirm
   the significant-change consent flow presents (PermissionKit's system dialog to the parent/
   guardian, or — for the adult path — DeclaredAgeRange's own acknowledgment sheet if the sandbox
   account is instead a verified adult in a jurisdiction requiring adult notification). Have the
   parent/guardian sandbox account approve; confirm Tally becomes usable again without a fresh
   launch (the `AskCenter.responses(for:)` stream, `AgeAssuranceModel.listenForAnswers`).
7. Same as 6, but the parent/guardian **denies**. Confirm `AgeRestrictedView` shows instead of the
   Dashboard, with no way past it other than the parent/guardian approving.
8. **StoreKit age-rating change**, automatic path: change the sandbox app's age rating in App
   Store Connect, relaunch on a device that already has a cached `lastKnownAgeRatingCode`. Confirm
   the significant-change flow presents without setting the manual flag in check 6/7.

## EB-04: fail closed everywhere for a blocked or revoked minor

9. **The launch block itself.** With the sandbox minor account from check 2, have the
   parent/guardian withdraw consent for Tally (Screen Time / Family Sharing controls, or App
   Store Connect's sandbox revocation trigger per the sandbox guide). Relaunch Tally. Confirm
   Apple's own block prevents the app from launching at all (this is Apple's behavior, not
   Tally's code — the check is that Tally does nothing to interfere with it, e.g. no crash
   report, no retry loop).
10. **Widgets (glance).** Before revoking, add a Tally widget to the Home Screen or Lock Screen
    and confirm it shows real content. After the revocation in check 9, without removing the
    widget, confirm it shows nothing meaningful (no course names, no due items, no grades) — at
    minimum the last cached render before revocation, never a refreshed one. Record exactly what
    it shows; this is the one surface AGE-1 did not add new gating code to (engineering position:
    `TallyGlance` is deliberately isolated from `DeclaredAgeRange`/network/decode entirely,
    `check_widget_isolation.py`), relying on the same OS-level block as the main app. **If this
    check shows live content, that is an open item for a follow-up PR**, not something AGE-1's
    code change covers — record the result here either way.
11. **Control Center.** If Tally ships a Control Center widget/control, confirm the same: nothing
    meaningful after revocation.
12. **Siri/Shortcuts intents** (`DueIntents.swift`). After the revocation in check 9, ask Siri
    "What's due in Tally" (or run the Shortcut directly). Confirm it reports nothing meaningful
    (ideally: it reports the app is unavailable). Record the exact result.
13. **Alabama §13(5)** (installs before 2026-10-01 need blocking only after a revocation or a
    significant change — not relevant to a fresh sandbox install, but record for the compliance
    file): confirm checks 9–12 were run on a fresh install (not one that predates 2026-10-01), so
    this exception does not mask a real gap.

## Recording results

Append one line per check (1–13) to this file's bottom with the date, build, and PASS/FAIL/
observation — do not write a verification claim into code comments or a report that was not
actually observed on a device (pmo-common-rules-v2.md rule 14: "Never write a verification claim
... unless you observed it"). The PMO folds this into the compliance dossier.

### Results log

_(append here — date, build, check #, result)_
