# MVP-2b report: fix the accessibility audit

Author: Accessibility Design Engineer (work package MVP-2b), Claude Opus 5.5. Branch
`mvp/a11y-fixes`, from `origin/main` @ `5f6a730`. This host has no Xcode; every iOS claim below
cites the CI run that showed it. Journal: `build/logs/journal/2026-10-12-mvp2b.md`. Evidence
(outside the repo): `pmo-audit/.build-audit/mvp2b/`.

## Result

__GATE_RESULT__

Issue counts, every audit test of the three classes (Light std + AX5, Dark std, Increase
Contrast), the `FamilyUITests` audits excluded:

| Audit type | Before: run 38338079168 (app = `main`) | After: run 38370696712 (last scope=a11y) | After: release gate __GATE_ID__ |
| :--- | ---: | ---: | ---: |
| `contrast` | 128 | 0 | __G_C__ |
| `dynamicType` | 71 | 0 | __G_D__ |
| `textClipped` | 31 | 3 (Calendar, fixed after; see cause 14) | __G_T__ |
| `elementDetection` | 9 | 0 | __G_E__ |
| `sufficientElementDescription` | 2 | 0 | __G_S__ |
| `hitRegion` | 2 | 0 | __G_H__ |
| **Failing** | **243** | **3** | **__G_TOTAL__** |
| Waived (exact pairs) | 24 issues (MVP-2's 8 waivers) | 45 issues (21 of today's 24 waivers) | __G_W__ |
| Held by the audit-position rule | — | 109 | __G_HELD__ |

Run 38338079168 recorded 237 failing issues; `calendar-light-ax5`'s JSON was lost (the test failed
to terminate the app) and its log lists 6 more (2 `dynamicType`, 4 `textClipped`): 243. MVP-2a's
inventory counted 234: its suite never ran the AX5 audit on the 13 screens whose default-size audit
failed (`continueAfterFailure` was restored before the assertion), which this package fixed first.

## Method

1. **Measurable from CI.** `runA11yAudit` now attaches, per audit, the screen at rest (PNG), the
   window frame and every element with its frame, and per issue the element's frame, type and
   detailed description. No device needed.
2. **Measured.** `pmo-audit/.build-audit/mvp2b/contrast-measurements.md`: every contrast issue of the
   before run on its own pixels (Python + Pillow; the glyph cores, not anti-aliased edges; WCAG 2.x;
   4.5:1 under 18 pt, 3:1 large text). **No colour token failed.** Increase Contrast was really on
   (the restore link reads `#123C80`, `accent`'s High Contrast value, there and `#1D4E9E` in Light),
   so no High Contrast variant was needed, and the glass primary button ("Find My School", 8.07:1)
   was never flagged.
3. **Clustered by cause and fixed once per cause** (table below), then **five scope=a11y runs**
   (38338079168, 38350587735, 38357314250, 38363059477, 38370696712): 243 → 59 → 22 → 8 → 3.

## Root causes

| # | Cause | Elements (before) | Fix or disposition | Where | Before → after |
| ---: | :--- | :--- | :--- | :--- | :--- |
| 1 | Text that scrolls, measured where it is not in view: under the floating tab bar or iOS 26's scroll-edge dimming (`AdditionalDimmingOverlay`), under the top bars or Calendar's pinned strip, or partly off-screen | 70 contrast measured (58 / 4 / 8), e.g. Dashboard "Worksheet 3…" 1.29:1 under the dimming; text in view there passes (e.g. "Participation: September" 15.27:1) | **Audit-position rule** in the suite (not a waiver; `docs/pmo/a11y-waivers.md` has the definition and why no exact pair can name these rows) | `AccessibilityAuditUITests.swift:777` (`A11yScene`), `:853` (`heldReason`) | contrast failing 128 → 0; 106 held in run 38370696712, each with its reason |
| 2 | Contrast measured as passing on the audit's own pixels | Explore with Sample Data 5.44:1 / 7.02:1 (IC); Choose a Different School 5.44 / 7.02; Restore Purchases 7.24 / 9.61; Calendar day letter 9.41 / 9.52; Settings "Account" 8.80 | Exact waivers with the measurement (identifiers added where missing) | registry `AccessibilityAuditUITests.swift:302`; `CalendarScreen.swift` weekday letter, `SettingsView.swift` header, `SignInHandoffView.swift` button | 5 elements → waived |
| 3 | Disabled Reset (toolbar) | 2.08:1 Light, 2.51:1 Dark | MVP-2's toolbar waiver, now with the measurement: an inactive control has no WCAG 1.4.3 requirement | `WhatIfSheet.swift:78` | waived |
| 4 | Dynamic Type at the default size: rows the audit's own growth pushes below the fold | Settings' seven lower rows, Light and Dark (absent at AX5) | **Dynamic Type audited at AX5** (`light-ax5`, every screen) | `AccessibilityAuditUITests.swift:404` | 14 → 0 |
| 5 | Pinned chrome capped at AX2 by design (D04/D05, FP-3; ASC-14) | SAMPLE DATA banner ×2 on 10 screens, Welcome's two actions, What-If's summary ×3 | Waived (deliberate); each now offers the Large Content Viewer (HIG) — the audit still flags them | `SampleDataBanner.swift:19,30`, `WelcomeView.swift:144,150`, `WhatIfSheet.swift:118,148` | waived |
| 6 | A one-word web address wrapped mid-word ("canvas.northfield.ex- / ample"; AX5 "can- / vas.north- / field.exam- / ple") | hand-off title, button, address tag (`textClipped`) | **`TallyTokenBreaks`** (new, design system): break opportunities after `.`/`/` before a letter; the element's label stays plain | `TokenBreaks.swift:15`; `SignInHandoffView.swift:40,110,165` | title, button: no longer flagged; tag: waived (whole at AX5, screenshot) |
| 7 | The address alone as an element label | `sufficientElementDescription` ×2 | Tag reads "School" (Settings' existing key) with the address as its value; rounded rectangle from AX1 | `SignInHandoffView.swift:155` | 2 → 0 |
| 8 | A combined label with no trait, read as tappable | `whatif.simulationLabel` `hitRegion` ×2 | `.isStaticText` (and on `whatif.projected`) | `WhatIfSheet.swift:117,147` | 2 → 0 |
| 9 | Chip label not containing its visible text ("100%" labelled "Set Lab Report 4 to 100 percent") | What-If `elementDetection` | Label = the visible text (WCAG 2.5.3), the sentence (same key) moves to the hint | `WhatIfSheet.swift:252–253` | with #10: 9 → 0 |
| 10 | What-If at its medium height is drawn at 0.96 scale (Reset 64.65 × 34.57 vs 67.33 × 36 pt) | summary, header, chips: `textClipped` ×4, `elementDetection` ×4 per run | **Audited pulled up** to its large height (the same sheet passed every type there, run 38350587735) | `AccessibilityAuditUITests.swift:661` | 8/run → 0 |
| 11 | Course names held to two lines below AX1 (cut at xLarge–xxxLarge) | Courses, element-less `textClipped` ×2 | No line limit | `CoursesScreen.swift:129` | Courses passes from run 38363059477 |
| 12 | Word chips held to one line below AX1 | (same Courses finding, with #11) | Up to two lines at every size; one line where they fit (the default size) | `ScreenComponents.swift:127` | as #11 |
| 13 | The two checks that grow the text reflow the screen before the rest are read | 50 contrast/clipping issues with no element; Calendar's agenda moving mid-audit | Pass order: still checks, then `textClipped`, then `dynamicType` | `AccessibilityAuditUITests.swift:409` | 50 element-less → 0 |
| 14 | Calendar opens scrolled to today: rows above sit hidden behind the banner, bar and strip | 1–4 element-less `textClipped` per variant, every run | Audited at the agenda's first day (the reach taps it); the strip and place text also keep one view tree | `AccessibilityAuditUITests.swift:687`; `CalendarScreen.swift:190,305` | 3 → __G_CAL__ |
| 15 | Paywall price: VoiceOver's words ("$9.99 per year", PAY-05) differ from "$9.99/year" on screen | `paywall.price` `textClipped` | Waived: the tour shows it whole at AX5 on the smallest iPhone | `PaywallView.swift` | waived |
| 16 | What-If score field and category header at AX5 (seen in run 38357314250 only) | `dynamicType` | Waived: measured scaling (placeholder 12.0 → 38.7 pt; header 40 → 145 pt) | registry | waived |
| 17 | The system keyboard's predictive cells (Find School, Dark) | `sufficientElementDescription` ×3 | The rule's keyboard case (`inputView`) | `AccessibilityAuditUITests.swift:853` | 3 → held |
| 18 | First Sync's second launch opened signed in (the first audit had synced) | reach failure | `resetAppState()` between the two audits | `AccessibilityAuditUITests.swift:89` | flake gone |
| 19 | `FamilyUITests`' `family.` prefix filter | hid 11 (std) / 4 (AX5) issues, none on family elements | Replaced by the shared rules (`runA11yAudit`); `isFamilyElement` removed | `FamilyUITests.swift:79,95` | filter gone |

## Waivers

24 exact (element, type) pairs, one row each in `docs/pmo/a11y-waivers.md`: MVP-2's 8 toolbar
buttons (now with the Reset measurement) and 16 from MVP-2b — 7 deliberate AX2 caps on pinned
chrome (banner ×2, Welcome ×2, What-If summary ×3), 5 measured contrast false positives, 2
measured clipping false positives (price, address tag), 2 measured Dynamic Type false positives
(What-If field and header). One speculative waiver (What-If's change line, never flagged) was
dropped. Three audit-configuration decisions and the audit-position rule are documented there with
their evidence; they are the parts gate 2 most needs to judge.

## Visual regression check (owner's bar)

- **Tours:** before = run 38339844918 on `ad7688f` (UI identical to `main`), after = run
  38372167047 on `52c5876` (the final app code; later commits change tests and docs only). All 8 legs
  each. The after leg proMax/light/std reports failure: `AuditTourUITests.testI_demoSignInProgress`
  missed the search field once ("Activation point invalid") and passed on its retry; its captures are
  complete. The tour does not capture the sign-in hand-off (it taps through it): that screen's
  before/after is the a11y screenshots, four variants.
- **Layout checks over the captures both tours have:** overlap 4239 → 4276, offscreenOrClipped
  282 → 269, hit targets < 44 pt 1105 → 1109, truncation 0 → 0 (`layoutcounts.md`). Every new entry
  is classified in `rises.md`: content under the floating tab bar (1277, triage 1991), the scroll-
  edge dimming (157, triage 891), content scrolled under the top bar (112, D01's opaque fill), a
  combined element and its own text or icon (101; 8 of them What-If's two summary elements, now
  static text, so the check counts them), rows under Calendar's pinned strip (76), the keyboard,
  44-pt targets read as 43.99999, the Settings stepper and To-Do's mid-swipe row; the 63 left for
  review by hand are of the same kinds (combined rows whose label words differ from their texts,
  content under the batch bar or a toolbar button, the keyboard's Continue bar). Sample data is
  relative to today, so the two tours show different dates, times and rows.
- **At 200%** (`pairs/`): Calendar's week strip (moved into its scroll view) is identical at the
  default size and at AX5 on both devices; Courses' cards, What-If, Welcome and the SAMPLE DATA
  banner are identical apart from date-dependent text. The visible changes are the hand-off's
  address (`evidence/handoff-*-before-after.jpg`) and, at xLarge–xxxLarge only (no tour leg), course
  names and chips that wrap instead of truncating.
- **Owner sheet:** `pmo-audit/.build-audit/mvp2b/evidence/owner-sheet-mvp2b.jpg`.

## Strings PENDING owner approval

None: no new keys. VoiceOver wording changes made with existing keys (for the owner's review, not
copy changes): What-If's quick-fill chips read their visible text ("100%") with the existing
sentence as the hint; the hand-off's address tag reads "School, canvas.northfield.example"
(Settings' existing "School").

## CI runs

- scope=a11y: 38338079168, 38350587735, 38357314250, 38363059477, 38370696712 (5 of 5).
- Audit tour: 38339844918 (before), 38372167047 (after) (2 of 2).
- Release gate: __GATE_ID__ __GATE_COUNTS__ (__GATES_USED__ of 2).
- PR run: in the hand-off reply.

## Open items

- **Gate 2 (PMO's Opus review)** of the audit-position rule, the three audit-configuration
  decisions (Dynamic Type at AX5; What-If pulled up; Calendar at its first day) and every waiver.
- **Device checks not done** (no device on this host): VoiceOver (the chips' label and hint, the
  address tag, What-If's summary as static text), Switch Control, a real Increase Contrast setting
  (CI sets it with `simctl` plus the launch argument; the screenshots show it took effect), and the
  Large Content Viewer on the banner, Welcome and What-If (long press).
- **Environmental:** in run 38363059477 a system notification ("Ready for Apple Intelligence")
  covered the banner's Exit on Insights (Dark) at the audit moment; it did not recur. The release
  gate retries a failed test once.
- **Not audited:** What-If at its medium height (cause 10) and Calendar opened on today (cause 14);
  both states hold the same components the audited states show.
- **Seen, not fixed (not this package's):** AX5 titles that hyphenate mid-word ("Respira- / tion" in
  Calendar, present before and after); the release gate's accessibility step builds three times
  (67 min of its 120-min job in run 38321522188).
- `FamilyUITests` now judges the whole parent-mode screen in every PR run (it used to look at the
  family's own elements only); a future content change there can fail it.
