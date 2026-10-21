# COMP-1 report: subscription disclosures and the 2-week trial (EB-18, EB-19, EB-21, EB-22, EB-24(a))

Work package COMP-1, `compliance/comp-1` (branch), PR TBD. Implements EB-18, EB-19, EB-21, EB-22
and EB-24(a) from the LOCAL (never committed) `Tally-compliance/us-wide/engineering-backlog-us.md`
§3, against `matrix.md`'s FED-4 row and the dossier facts it cites.

## Items, one line each

- **EB-19** (owner decision, 2-week trial): done — `Products.storekit`'s introductory offer is
  `P2W`; `check_storekit_products.py` enforces it; every test and doc comment that pinned the old
  one-month value is updated. No code string hard-codes the length (it derives from StoreKit), so
  no new key was needed for this item itself. **Owner action**: set the introductory offer to 2
  weeks in App Store Connect at submission — this PR only changes the code path and the local
  StoreKit Testing configuration.
- **EB-18** (clear and conspicuous renewal terms): done — `PaywallView`'s price block now shows,
  at body size and the primary text colour, directly above the purchase button: the price and
  period (already the most prominent text above it), the trial's end date and the charge that
  follows (computed from the offer, never hard-coded), that it renews automatically until
  cancelled, and how to cancel. The date math is a pure, unit-tested function
  (`SubscriptionOfferText.trialEndDate`), never `Date()`/`Calendar.current` in a view body.
- **EB-21** (retainable purchase confirmation): done — a new sheet (`PurchaseConfirmationView`)
  shown once right after a direct purchase or trial start (never a restore or a redeemed code),
  stating the plan, the amount, the renewal date and how to cancel; re-findable afterwards from
  Settings → Subscription's "View Purchase Confirmation" row. Nothing is persisted — every fact
  is read fresh, so nothing can go stale.
- **EB-22** (Terms of Use row): done — Settings → About now has a Terms of Use row under Privacy
  Policy, reusing the paywall's own key and URL (`subscription.termsOfUse`,
  `SubscriptionLinks.termsOfUse`) exactly as EB-06 did for the policy row. No new string.
- **EB-24(a)** (qualify "stays on this iPhone"): done, DRAFT wording pending owner/counsel
  sign-off — the paywall's privacy bullet now reads "Your Canvas data stays on this iPhone —
  except what you choose to sync to Calendar or ask Siri," covering the Calendar-subscribe
  (dossier F14) and Siri/Shortcuts (F32) gaps. The static-host-log gap (F6, F19) is left to the
  Privacy Policy (EB-28, site text) rather than restated in this one-line bullet — flagged below
  as an explicit scoping choice, not a silent gap.

## Tests

- Unit: `SubscriptionOfferText.trialEndDate` over every StoreKit period unit (day/week/month/year)
  and no trial; the two new renewal sentences' exact text; `SubscriptionModel.justPurchased` set
  only by a `.purchased` outcome (folded into the existing `paywallPurchase()`/`restore()` tests,
  one guard per outcome); `PurchaseConfirmationModel`'s four facts, read fresh after `.load()`.
- UI smoke (by identifier, never translated text): `PaywallUITests
  .testSampleModeSettingsInterstitialPaywallAndPurchase` now also asserts the confirmation appears
  once after the purchase (`confirmation.root`, `.plan`, `.amount`, `.renewalDetail`), dismisses
  (`confirmation.done`), and is re-findable from Settings → Subscription
  (`subscription.viewConfirmation`) afterwards. `assertPaywall` now also checks
  `paywall.trialEnds`'s presence alongside `paywall.trial`. `ReviewPathUITests`'s Settings → About
  walk now also asserts `settings.termsOfUse`.
- a11y suite: unchanged (never widened a hold); the paywall's existing `testPaywall`/
  `testPaywallAX5` (Light), `AccessibilityAuditDarkUITests.testPaywall` (Dark) and
  `AccessibilityAuditContrastUITests.testPaywall` (Increase Contrast) already cover this screen at
  AX5/Light/Dark/Contrast and now exercise the EB-18 lines too, reusing the same already-audited
  colour/typography tokens (`TallyColor.textPrimary`, `TallyTypography.body`) as every sibling
  line on the screen.
- Store screenshots: the paywall and Settings → Subscription screens changed visually (EB-18's
  extra lines, EB-21's new row); confirmed via `docs/release/app-store/` that the paywall is not
  one of the captured store screenshot scenes, so `store-screenshots.yml` needs no update.

## Open items

- EB-21's confirmation on the Home-presented paywall path (first-sync / locked-feature triggers,
  `HomeShellView`) uses the identical mechanism as the Settings-presented path and is unit-tested
  at the model level, but is not separately exercised by a UI test (no existing UI test completes
  a purchase through that path). Flagging rather than silently claiming full coverage.
- The backlog's longer EB-21 write-up also mentions a Share button and capturing Apple's own
  purchase-sheet/receipt text as evidence for counsel; the brief's own item list (plan, amount,
  renewal date, how to cancel; shown once; re-findable) does not include either, so neither
  shipped. Raise with the owner if counsel still wants them.
- EB-24(a)'s wording and EB-18's exact cancellation phrasing are both DRAFT, listed below for
  owner approval before merge, per the copy rules.
- No dedicated Audit-tour screen exists yet for the new Purchase Confirmation sheet itself (the
  dispatch below covers the paywall and Settings → Subscription, which already show the EB-18/
  EB-21 changes); adding one is a small follow-up, not done here to stay inside the LEAN CI
  budget.

## Copy for owner approval

New keys only (en `translated`, es `needs_review` — a first machine pass, reviewed later per the
L10N-04 owner decision). Two keys retired, never edited in place: `subscription.paywall.renewal`
and `subscription.feature.privacy`.

| Key | English | Translator comment |
|---|---|---|
| `subscription.paywall.renewalAutoCancel` | "Renews automatically at %@ until you cancel. Cancel anytime: Settings > Apple Account > Subscriptions, or Manage Subscription in Tally's Settings." | EB-18. Paywall, body size and the primary text colour, next to the purchase button: the price and period, that it renews automatically until cancelled, and how to cancel. The argument is the per-period price text, such as '$9.99/year' (never reformatted). |
| `subscription.paywall.trialEndsThenCharged` | "Your free trial ends %1$@. Unless you cancel at least 24 hours before, you're then charged %2$@." | EB-18. Paywall, body size and the primary text colour, shown only with an eligible free trial: the date the trial ends and the charge that follows unless cancelled in time. 1: the trial's end date. 2: the price per period. |
| `subscription.feature.privacyQualified` | "Your Canvas data stays on this iPhone — except what you choose to sync to Calendar or ask Siri." | EB-24(a), DRAFT for owner/counsel approval. Paywall, what's included: Tally has no server, but Calendar subscribing and Siri/Shortcuts leave the device through Apple's own systems. |
| `subscription.confirmation.title` | "You're All Set" | EB-21. The retainable confirmation's title. |
| `subscription.confirmation.amountLabel` | "Amount" | EB-21. The purchase confirmation: the row naming the price per period. |
| `subscription.confirmation.renewsLabel` | "Renews" | EB-21. The purchase confirmation: the row naming the renewal date. |
| `subscription.confirmation.done` | "Done" | EB-21. The purchase confirmation's close button. |
| `subscription.settings.viewConfirmation` | "View Purchase Confirmation" | EB-21. Settings > Subscription: re-opens the confirmation. Shown only for the student's own purchase, never a school-assigned seat. |

The owner approves these before merge (copy rule).

## Verification

Evidence and run IDs are in the journal (`build/logs/journal/2026-10-21-comp1.md`) and the hand-off
reply. Local Python hygiene checks and `make lint`/`make core-build`/`make core-test` all green;
this host has no Xcode, so the iOS build/tests/UI tests/a11y suite/Audit tour wait for CI.
