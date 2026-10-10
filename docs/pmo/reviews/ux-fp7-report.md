# UX-FP7 report — widget follow-up (N1, N2, D23 polish, G2 fidelity)

Branch `ux/fp7-widget-polish`, from `origin/main` @ `2a47545` (PRs #42–#47, the whole design-audit
fix wave, merged; worktree pre-created and verified clean by the PMO). No merge of `origin/main`
was needed (its tip is still `2a47545` as of this report; rule 3). Journal:
`build/logs/journal/2026-10-10-ux-fp7.md`. Attribution: Claude Sonnet 5. No parallel stream.

Order of work followed the brief: G2 first (trustworthy renders), then N1/N2/D23, verified on the
new renders at 200% (in practice, well past 200% — every review render is now scale 3, the device
scale, so 1 render pixel = 1 device pixel and a 100% crop already shows device-resolution detail).

## G2 — review render fidelity (test-only)

`WidgetFamilyRenderTests.swift`'s own gate-2 review (FP5 verdict.md, "G2: the four gaps") found
four problems with the renders used to judge widget layout. All four fixed in `hostedPNG()`
(`apps/TallyiOS/TallyAppTests/WidgetFamilyRenderTests.swift:221-254`), commit `d579129`:

1. **False `bg.brand` in accented/vibrant.** The system removes a widget's `containerBackground` in
   those two modes; painting it anyway produced a false "dark glyph on navy" reading. Those renders
   now get a neutral stand-in (`Color(white: 0.55)` light / `Color(white: 0.07)` dark) and the
   attachment name gets a `-neutral-bg` suffix (`backdropLabel`, `WidgetFamilyRenderTests.swift:
   264-268`).
2. **`AccessoryWidgetBackground()` draws nothing under `ImageRenderer`.** The two Lock Screen
   accessories that use it now get a visible `Color.black.opacity(0.55)` stand-in chip, labelled
   `-standin-bg`.
3. **No hosted render included the Mark Done button.** Added `dueSoonWithMarkDoneHostedSnapshot()`
   (`WidgetFamilyRenderTests.swift:348-369`), light and dark.
4. **2x renders on a 3x device.** `hostedPNG`'s `renderer.scale` is now 3. Left the plain, unbacked
   `renderer()` (the functional/pixel tests — contrast, alpha, locked-rendering identity) at 2x:
   nothing asked for those to change and scale doesn't affect what they measure.

Also added, per the brief's own gap 5 and N1/N2's own notes ("widgets are rendered only at Pro Max
sizes"): `PhoneClass` (`WidgetFamilyRenderTests.swift:122-134`) with the 390 pt-wide class's
documented small/medium sizes (158×158, 338×158 — Apple's HIG "Specifications," the same source
already cited for the Pro Max sizes), and `smallestPhoneSnapshot(surface:mode:)`
(`WidgetFamilyRenderTests.swift:330-342`) over the four families N1 and N2 are about.

Every existing assertion is unchanged. Confirmed in CI (run 38039203669): `Exported 48 attachments
for: snapshot(surface:mode:)`, `Exported 24 attachments for: smallestPhoneSnapshot(surface:mode:)`
(4 surfaces × 3 modes × 2 appearances), `Exported 2 attachments for:
dueSoonWithMarkDoneHostedSnapshot()`.

## Defects

"Before": FP5's last widget renders, `pmo-audit/.build-audit/fp5/after-38023201467/
audit-proMax-light-std/` (2x, no backdrop labelling, Pro Max only — G2 wasn't fixed yet). "After":
Audit tour run **38048446466** (N2, D23; final — see "CI and Audit tour runs"), plus the PR run's
own `ui-test-screenshots` artifact for N1's final state (both Audit tour dispatches were spent
before N1's last fix landed; see "N1" below).

| Defect | What changed | `file:line` | Evidence | Measured |
|---|---|---|---|---|
| **N1 (S2)** Standing (small) truncates "3 courses not includ…" | See "N1" below — went through three attempts; final one shrinks the caption to fit instead of wrapping it. | `packages/TallyAppleKit/Sources/TallyGlance/GlanceWidgetViews.swift:258-264` | `pmo-audit/.build-audit/fp7/widget-sheet-ux-fp7.jpg` | See "N1" below |
| **N2 (S3)** Due soon (medium) content ~12 pt taller than its box | `DueSoonWidgetView` wraps its row list in `ViewThatFits(in: .vertical)`: tries `dueSoonRows` (3) first, falls back to `dueSoonRows - 1` (2) only when 3 doesn't fit the height the system actually proposes. | `packages/TallyAppleKit/Sources/TallyGlance/GlanceListWidgetViews.swift:38-47` | `widget-due-soon-medium-full-color-{light,dark}{,-smallest}.png` | Pro Max: top **16.00 pt**, bottom **18.67 pt** (was 9/11.5). Smallest phone (338×158): same, top **16.00 pt**, bottom **18.67 pt**. Both ≥ the 16 pt target — no overflow, no clipping risk. |
| **D23 (S3)** Week ahead's lower part reads empty, two unequal gaps (36 pt / 88 pt) | Extracted `GlanceItemRows` (rows only, no footer/spacer) out of `GlanceItemList`. `WeekAheadWidgetView` now places two `Spacer(minLength: TallySpacing.sm)`s and the footer as direct siblings of the week strip and the rows, in one `VStack`, instead of one `Spacer` living a level down inside `GlanceItemList`'s own `VStack` — so SwiftUI's single-level space distribution splits the slack between the two (now sibling) spacers. | `packages/TallyAppleKit/Sources/TallyGlance/GlanceListWidgetViews.swift:62-92` | `widget-week-ahead-large-full-color-{light,dark}.png` | The two gaps: **63.00 pt and 62.33 pt — ratio 1.01:1** (was 2.44:1), identical in light and dark. ≤ 2:1 bar met with wide margin. |

### N1 — three attempts, the third one measured correctly

All three were measured against real renders, not assumed:

1. **`lineLimit(2)`, both captions** (commit `0af5788`). Fixed the reported defect on Pro Max
   (confirmed: "3 courses" / "not included," no ellipsis). But the smallest-phone render (158 pt,
   narrower than Pro Max's 170 pt) showed a **new** truncation on the *first* caption instead —
   "Average of 2 cours…" — not something the original defect report was about.
2. **Only the second caption gets `lineLimit(2)`** (commit `1689063`), reasoning that the two
   captions were competing for vertical room. Re-measured against Audit tour dispatch 2
   (38048446466): **identical** truncation, pixel-for-pixel the same line height as attempt 1.
   Wrong diagnosis — reverting the first caption's `lineLimit` to 1 didn't change what it was
   actually being given room for.
3. **`lineLimit(2)` + `.layoutPriority(1)` on both captions** (commit `f30c495`), to make the two
   `Spacer(minLength: 0)`s in that `VStack` yield first. Measured against CI run 38049570479's own
   `ui-test-screenshots` artifact (both Audit tour dispatches were spent by this point — confirmed
   a plain CI run uploads the same `WidgetFamilyRenderTests` attachments the Audit tour does, as
   this artifact): **still identical** — 12.33 pt, one line, unchanged. `layoutPriority` did not
   move this needle either.
4. **Final (commit `8a846cc`): `lineLimit(1)` + `.minimumScaleFactor(standingCaptionMinimumScale)`
   (0.8)**, both captions. Measured the actual shortfall instead of guessing again: the truncated
   "Average of 2 cours…" already fills 122.33 pt of the ~126 pt available width — only a few points
   short, not a whole line. A mild scale-down (0.8 is the gentlest token already in this file;
   `bandMinimumScale`/`accessoryMinimumScale` are 0.6, `dayCountMinimumScale` 0.7) sidesteps the
   vertical-space question entirely, since it only asks for horizontal room.

**Status at hand-off:** [FILL AFTER PR RUN — see "Open items" if still pending]

## CI and Audit tour runs

| Run | Kind | Commit | Result |
|---|---|---|---|
| 38039203669 | CI `scope=quick` (iteration 1/3) | `1fe09ff` | ✅ all required jobs green; 649 tests, 0 failed, 0 retry warnings |
| 38043495425 | Audit tour (dispatch 1/2) | `1fe09ff` | ✅ |
| 38044640380 | CI `scope=quick` (iteration 2/3) | `1689063` | ✅ all required jobs green |
| 38048446466 | Audit tour (dispatch 2/2, final) | `1689063` | ✅ |
| 38049570479 | CI `scope=quick` (iteration 3/3, final) | `f30c495` | ✅ all required jobs green |
| [PR run — fill] | CI (PR, required) | `8a846cc` or later | [fill] |

No `Failed attempt (retried once)` warning appeared in any run.

## Strings PENDING owner approval

None. Every fix in this package is layout-only; copy was never touched (frozen, per the brief).

## Evidence and widget sheet

- `pmo-audit/.build-audit/fp7/after-38043495425/`, `after-38048446466/` — Audit tour downloads.
- `pmo-audit/.build-audit/fp7/ci-38049570479/` — the CI run's own `ui-test-screenshots` artifact
  (used once the Audit tour dispatch budget was spent).
- `pmo-audit/.build-audit/fp7/review/measure.py`, `d23_gaps.py` — the pixel measurement scripts
  (content bounding box vs. `bg.brand`'s real hex from `bg.brand.colorset/Contents.json`, never a
  guessed value; content-band gap detector).
- Widget contact sheet: `pmo-audit/.build-audit/fp7/widget-sheet-ux-fp7.jpg`.

## Open items

1. **N1's final state needs the "Status at hand-off" line above filled in** once the PR's own run
   is read (see journal step 9) — both Audit tour dispatches and all 3 CI iteration runs were spent
   before the third attempt landed, so this package's own dispatch budget couldn't confirm it.
2. Device checks: none of N1/N2/D23 have been seen on a physical device or the Simulator directly
   (this host has no Xcode) — only through `ImageRenderer`'s hosted composition, which is the same
   method FP5's G2 fix established as trustworthy (real `containerBackground`, real system margins,
   real device scale).
3. `GlanceItemRows` is `internal`, not `public` — matches `GlanceItemList`'s existing access level,
   not a new widening.
4. Out of scope, not touched: any defect outside N1/N2/D23/G2 (none were noticed while reading
   these files).
