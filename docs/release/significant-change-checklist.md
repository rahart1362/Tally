# Release checklist: is this a "significant change"? (EB-02(a))

**Run this step for every release, before tagging it.** It decides whether the release must run
the significant-change flow (EB-02(b)/(c): PermissionKit's `SignificantAppUpdateTopic` for an
affected minor, or DeclaredAgeRange's `showSignificantUpdateAcknowledgment` for a verified adult)
before continuing use, and whether it re-requests age/consent at the next launch.

## The test: the union, not any one state's definition

Texas SB 2420 §121.053(b) has the **broadest** definition of the four enacted App Store
Accountability Act states (matrix.md §2), so building to it covers Utah 13-76-101(20) and
Alabama HB161 §1(19) too — "jurisdiction-agnostic... a new state needs no new code if Apple flags
it" (engineering-backlog-us.md §2, AGE-1 goal). A release is a significant change if **any** of
these is true:

1. **Data categories collected, stored or shared changed.** In Tally's terms: a new field was
   added to anything `UserState`, the sealed snapshot, or the glance stores; a new network
   destination was wired (`scripts/ci/check_policy_matches_app.py`'s `FLOWS`); or the privacy
   policy's `POLICY-FLOWS` block (`site/privacy/index.html`) changed which flows it calls active.
   **This one is the mechanical trigger**, checked by `scripts/ci/check_significant_change_notice.py`
   (EB-02(d)) — see below.
2. **The age rating changed.** Alabama §1(19)(c) names this explicitly; it is also
   **automatic** in this app: `AgeRatingChangeDetector` (TallyDomain) compares StoreKit's
   `AppStore.ageRatingCode` at every launch against the last value this device observed
   (`SignificantChangeVersionState.lastKnownAgeRatingCode`), and a change feeds
   `AgeRequestPolicyInput.isFirstLaunchOfSignificantChangeVersion` with **no checklist step
   needed** — `AgeAssuranceModel.evaluateIfDue` runs it every time, regardless of this flag.
3. **First-time monetization**, i.e. a new purchasable product or ad surface. Today: "Tally
   Annual" and "Tally Parent" (`SubscriptionConfig.swift`); COMP-1's trial-length change is not a
   new product and is not itself in scope. A future Tally Parent-style second product, or any ad
   surface, is.
4. **"Materially changes the functionality or user experience"** (Tex. §121.053(b)'s catch-all;
   not independently mechanically checkable). Examples already flagged in engineering-backlog-us.md
   §2: real-account family linking (M4), wiring school search or the school-list download. Judgment
   call — when in doubt, mark it significant; the cost of a false positive is one extra consent
   screen, the cost of a false negative is a statutory violation.

## The step

1. Before tagging a release, read the diff since the last tag against tests 1–4 above.
2. Set `TallyConfig.currentReleaseIsSignificantChange` (`packages/TallyCore/Sources/TallyDomain/
   Config/TallyConfig.swift`) to `true` for **this release only** if 3 or 4 applies (1 and 2 are
   automatic — see above — and need no flag). Revert it to `false` in the very next release's
   commit; it is not a toggle to leave on.
3. Add one line to `docs/release/significant-change-log.md` (create it from the template there if
   this is the first entry): the commit, the date, `yes`/`no`, and a one-sentence reason citing
   which of 1–4 applies. **Required even when the answer is "no"** — EB-02(d)'s CI check fails a
   release whose data-category surface changed (test 1) until this file has a dated entry for it.
4. If `yes`: write the one English sentence a parent/guardian (or a verified adult) will read —
   concise, specific, never "we've made improvements" (DeclaredAgeRange's own guidance: "Use
   concise, understandable language... Vague: 'We've made improvements to the app.'"). Pass it as
   `AgeAssuranceModel`'s `changeDescription` (currently empty — the composition root wires this at
   the release that first needs it; AGE-1 ships the mechanism, not a description, since nothing
   ships a significant change yet). **New copy, owner approval needed** (brief's Copy rule): this
   sentence is handed directly to Apple's system UI, which takes one plain `String` with no
   per-locale slot (neither `SignificantAppUpdateTopic.init(description:)` nor
   `showSignificantUpdateAcknowledgment(updateDescription:)` takes a `LocalizedStringResource`) —
   an open item for a Spanish-speaking parent/guardian, flagged in the AGE-1 PR, not solved by it.

## What this is not

This step does **not** replace EB-01's three request points (first launch after install, before a
paywall purchase, the 12-month floor) — those run regardless of whether any release was ever
marked significant. It also does not require Tally to track *which* past changes a given device
already acknowledged version-by-version (DeclaredAgeRange's own sample app does, with iCloud
key-value storage, for an app that ships many small changes over time); `AgeAssuranceModel`
tracks only "has this device acknowledged the significant-change flow for the current app
version," which is enough while Tally ships at most one significant change between consent checks.
Revisit if that stops being true.
