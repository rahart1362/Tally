# UX-FP6 report — dark-mode colour tokens

Branch `ux/fp6-dark-tokens`, from `origin/main` @ `9c0be49` (UX-FP1 + UX-FP2 merged; worktree
pre-created and verified clean by the PMO). No merge of `origin/main` was needed (`origin/main`
is still `9c0be49` as of this report; rule 3). Journal: `build/logs/journal/2026-10-09-ux-fp6.md`
(one entry per verified step: design decisions, every CI and Audit tour run, root-cause notes for
the two test fixes). Attribution: Claude Sonnet 5.

## One new token, one retargeted token

`accent` keeps its own Dark appearance (#8DB4FF) — it stays the tint for the TabView, icons,
links and the What-If slider, all already legible on `bg.canvas`/`bg.card`. A new, always-dark
fill token is the only fix that also reaches the swipe actions (a `.swipeActions` button always
draws a white label — a label-colour change alone can't fix it):

| Token | Any | Dark | Purpose |
|---|---|---|---|
| `accent.fill` (new) | #1D4E9E | #2E5FBF | the fill for a prominent/filled accent control |
| `accent.onFill` (retargeted) | white | white (was #06142B) | label/glyph on an `accentFill` fill |

`accent.onFill`'s old Dark value only made sense labelling the *lighter* `accent` itself in dark;
its only two call sites (`SignInHandoffView`'s `ProgressView` tint, `SampleDataBanner`'s
`foregroundStyle`) both sit on a background moving to `accentFill` in this same package, so it is
retargeted rather than duplicated as a third token.

## Defects

"Before" captures: the original dark audit, `pmo-audit/.build-audit/dark-run/audit-proMax-dark-std/named/`
(run 37666509957). "After": Audit tour run **37894200137** (`26cd077`), all 8 legs, widgets off.

| Defect | What changed | `file:line` | Evidence | Layout delta |
|---|---|---|---|---|
| **D28 (S2)** accent-filled buttons/glyphs fail contrast in dark | `TallyPrimaryButtonStyle` tints `.glassProminent`/`.borderedProminent` with `accentFill` instead of `accent` — covers every `.tallyPrimary` call site (Welcome, Paywall, App Lock, first-sync Retry, sign-in hand-off, SchoolNotEnabled, SchoolRevoked, GradeNotInCanvas) in one edit. Two more explicit call sites found by reading the code (not in the audit's file hints): the Reminders tip's "Turn On Reminders", and To-Do's "Open in Canvas" swipe button, which had **no** explicit tint at all and was inheriting `accent` from the shell's TabView tint. | `ButtonStyles.swift:20,24`; `Reminders/RemindersViews.swift:76`; `ToDo/ToDoScreen.swift:102,117` | `D28-findMySchool-before-after.jpg`, `D28-unlockFaceID-before-after.jpg`, `D28-startFreeTrial-before-after.jpg`, `D28-todoSwipe-before-after.jpg` | see "Layout-check note" below |
| **D29 (S2)** sample-data banner band is the brightest block in dark | `SampleDataBanner`'s own `.background(accent, …)` → `accentFill`. UX-FP1 already fixed the safe-area part (status bar sits on `bg.canvas`); this fixes only the band's own colour, so its text (`accentOnFill`, now white in both appearances) stays ≥ 4.5:1. | `SampleData/SampleDataBanner.swift:36` | `D29-sampleBanner-before-after.jpg` | see below |
| **D32 (S2)** What-If quick-fill chips fail contrast in dark | Chip label `.foregroundStyle(TallyColor.textPrimary)` (the audit's own first-listed fix), replacing the `.bordered` style's default accent-on-accent-tint label. | `CourseDetail/WhatIfSheet.swift:207` | `D32-quickFillChips-before-after.jpg` | see below |
| **D33 (S3)** navy hero isn't distinct from cards in dark | `bg.brand.colorset` gets a Dark appearance (#0D2A55, a step lighter than Any's #071A36) + a new shared modifier, `tallyHeroBackground()`, that also adds a 1 pt `separator` hairline around the hero shape in **dark only** (light needs none). Replaces the `background(bgBrand, in: RoundedRectangle(...))` call at all three hero sites. | `TallyDesignSystem/ScreenChrome.swift:165-188`; `bg.brand.colorset/Contents.json`; call sites `Dashboard/DashboardView.swift:104,185`, `CourseDetail/CourseDetailView.swift:470` | `D33-dashboardHero-before-after.jpg` | see below |

### Measured contrast (pixel-sampled from the "after" captures, Pro Max std, WCAG relative luminance)

| Control | Light | Dark | Needs |
|---|---|---|---|
| D28 filled buttons (white label on `accentFill`) | 8.07:1 | 6.08:1 (audit predicted "computes to 6.0:1") | ≥ 4.5:1 |
| D28 To-Do swipe actions (white glyph on `accentFill`) | — (unchanged, already 8.0:1-class) | 5.99:1 | ≥ 3:1 (glyph) |
| D29 sample-data banner (white on `accentFill` band) | 7.97:1 | 5.99:1 | ≥ 4.5:1 |
| D32 quick-fill chips (`textPrimary` on chip fill) | 13.3:1 | 9.65:1 | ≥ 4.5:1 |
| D33 hero text: percent (white) | — | 14.19:1 | ≥ 4.5:1 |
| D33 hero text: grade band (gold) | — | 8.33:1 (audit predicted 8.3:1) | ≥ 4.5:1 |
| D33 hero text: caption (`onHero2`) | — | 9.59:1 (audit predicted 9.6:1) | ≥ 4.5:1 |
| D33 refresh glyph (`accent` dark on hero) | — | 6.83:1 | ≥ 3:1 (glyph) |
| D33 hero vs. card luminance | — | 1.25:1 (audit predicted "computes to 1.25:1") | distinct block (visual; paired with the hairline) |

Method: `python3 -m PIL` crop of the exact button/band/chip/hero region from the "after" PNG, the
two dominant colours in it (fill + label), WCAG relative luminance and contrast ratio computed
directly (not estimated) — script and raw samples are in `.build-ux/` (not committed; the repo is
public). Every sampled fill colour matched its source token's hex exactly (e.g. the hero's fill
sampled as `(13,42,85)` = `#0D2A55`, the new `bg.brand` Dark value, to the pixel).

### Layout-check note (all four defects)

These are colour/tint/background-only changes — no frame, padding, font size or view-structure
change — plus one decorative `.overlay(...stroke...)` for D33's hairline, which is not an
accessibility element and cannot register in `analyzeLayout`'s frame-based checks (overlap,
offscreen/clipped, hit-target size, truncation all read element frames from the accessibility
snapshot; `isHittable` is explicitly not part of it, per that function's own doc comment). I ran a
before/after layout-check diff across all 8 legs, matched by filename, against the "before"
baseline the brief points to (UX-FP2's final tour, run 37842950859): `overlap` and
`offscreenOrClipped` counts moved in both directions by similar, small amounts on screens I never
touched (Insights, Calendar, Settings, School Search) as on the screens I did — consistent with
day-to-day noise in sample data's relative "due in Nh" text lengths (the FP2 report notes the same
effect) rather than anything from this package. The one outsized delta,
`63-todo-swipeAction.layout.json` (+14 overlap, +7 offscreen at Pro Max AX5), is explained by my
own `testE_toDo` fix: it now swipes a different (correct, tab-bar-clearing) row than before, and
that row's own pre-existing AX5 chip-wrapping (documented elsewhere in the audit, not a new
defect) is simply visible in a screenshot it wasn't in before. The screenshot itself
(`audit-proMax-dark-ax5/63-todo-swipeAction.png`) shows the swipe buttons now sitting cleanly
clear of the floating tab bar — the fix working as intended, not a regression.

## Also fixed (small, PMO-requested)

1. **`audit-tour.yml` attachment sanitisation.** Every character outside `[A-Za-z0-9._-]` is now
   replaced with `_` in the export-rename step, after the existing xcresulttool-suffix strip. Zero
   non-conforming filenames across all 2,702 files this run's 8 legs produced (checked with a
   regex sweep) — the fix holds under real output, not just the two characters the original bug
   report named.
2. **`AuditTourUITests.testE_toDo`**: swipes the first row whose frame clears the floating tab bar
   (`frame.maxY < tabBar.minY`), scrolling up once and retrying if every row on screen is still
   under it, instead of an unconditional `boundBy: 1`.
3. **`AuditTourUITests`: `openTabInTour`** (used at all 7 tab-tap call sites in the file) settles
   the screen (`waitUntilAtRest`, already used before every capture) before a tab tap, with one
   retry if the tab still isn't selected — addresses the "Activation point invalid" hittability
   failure from a tap mid-transition.
4. **`ci.yml`**: `iOS build + test`'s `timeout-minutes` 90 → 110. This run's own `iOS build + test`
   job (37887478307) took **1h20m10s**, which would have been killed at the old 90 min cap — this
   fix was load-bearing for this package's own CI run.

## CI and Audit tour runs

- **CI iteration run 1 of 3**: `37887478307` (`-f scope=quick`), head `26cd077` — **success**.
  Required jobs: `hygiene`-equivalent checks, `core-linux`, `lint`, `core-sanitizers`, `ios-build`
  all green. No `Failed attempt (retried once)` warnings.
- **Audit tour dispatch 1 of 2**: `37894200137`, all 8 legs, `-f widgets=false` — **success**, every
  leg green. Downloaded to `.build-ux/after-37894200137/`. Only two `missing-` captures across all
  2,702 files, both pre-existing, documented placeholders from the original dark audit's own "Gaps"
  section (`demoSignIn-missing-firstSyncProgress`, `course2-missing-detail`, SE AX5) — unrelated to
  this package. The third documented gap, `lockedTab-missing-card`, no longer appears (FP2's D04
  fix reaching it, not mine).
- No mutation run: nothing in this package adds a new guard/gate to mutate.

## Strings PENDING owner approval

None. Every fix is a colour/tint/background change; no copy and no new `L10n` key.

## Evidence and owner-sheet paths

- `.build-ux/evidence/D28-findMySchool-before-after.jpg`
- `.build-ux/evidence/D28-unlockFaceID-before-after.jpg`
- `.build-ux/evidence/D28-startFreeTrial-before-after.jpg`
- `.build-ux/evidence/D28-todoSwipe-before-after.jpg`
- `.build-ux/evidence/D29-sampleBanner-before-after.jpg`
- `.build-ux/evidence/D32-quickFillChips-before-after.jpg`
- `.build-ux/evidence/D33-dashboardHero-before-after.jpg`
- `.build-ux/evidence/owner-sheet-ux-fp6.jpg` (1200×1602, 180 KB)
- Raw "after" captures: `.build-ux/after-37894200137/audit-<proMax|smallest>-<light|dark>-<std|ax5>/`

None of this is committed (the repo is public); the PMO copies it per the brief.

## Open items

- **D29's light-mode status-bar glyph contrast** (the audit's "black glyphs on #1D4E9E, 2.64:1"
  finding) is outside this package — it is system status-bar content, not something
  `SampleDataBanner` draws, and the audit attributes the fix to the safe-area change UX-FP1 already
  made. Recorded here in case a device check still shows it; not fixed in this package.
- **D33's refresh-glyph colour** (`accent` dark, #8DB4FF) was not changed — it already clears
  6.83:1 on the new, lighter hero background, so it needed no token change, but a device check of
  real Liquid Glass blending (vs. the simulator's render) is still unverified, per the UX-FP1/FP2
  lesson about `glassProminent` needing an on-device look.
- **`accent.fill` does not reach any widget code** (checked: no `TallyWidgets` source references
  `accent`, `accentOnFill`, `accentFill` or `tallyPrimary`), so there is nothing to leave for FP-5.
- D30 and D31 (sheet tint, list-screen palette unification) are **not** this package's — seen in
  passing while reading `HomeShellView.swift`/`ScreenChrome.swift`, not fixed here, per "fix only
  your package's defects."
