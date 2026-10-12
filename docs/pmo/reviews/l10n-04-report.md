# L10N-04 report — Spanish + Settings → Language row

Author: Spanish Localization Engineer (work package L10N-04), Claude Sonnet 5. Branch `l10n/es`,
from `origin/main` @ `385aebd`. This host has no Xcode; every claim about Xcode compiling or
running something is sourced from a CI run cited by its run ID, never assumed.

## 1. Key counts (from the files)

| Catalog | Keys |
|---|---|
| `packages/TallyAppleKit/Sources/TallyStrings/Resources/Localizable.xcstrings` | 706 (+2 new, pending approval — §6) |
| `apps/TallyiOS/TallyWidgets/Localizable.xcstrings` | 14 |
| `apps/TallyiOS/TallyWidgets/Shared/AppIntents.xcstrings` | 24 |
| `apps/TallyiOS/Tally/AppShortcuts.xcstrings` | 6 |
| `apps/TallyiOS/Tally/InfoPlist.xcstrings` | 1 |
| `apps/TallyiOS/TallyWidgets/InfoPlist.xcstrings` | 1 |
| **Total** | **752** (754 including the 2 new Settings → Language keys) |

Matches the PMO's own count in the brief (706/14/24/6/1/1). The two post-freeze keys
(`courses.sparkline.trend.up/down/steady`, `courseDetail.override.menuRowTitle`) are translated.

## 2. The needs_review path (owner decision 2026-10-11) — CONFIRMED, no fallback needed

Every Spanish value is written at state `needs_review`. `scripts/ci/check_string_catalogs.py`
accepts `translated` or `needs_review` for a shipping language by default, and added `--release`,
which requires `translated` everywhere (self-tests for both; verified locally: normal mode 0
problems across 754 keys, `--release` correctly fails all of them).

**Verification: does Xcode compile a `needs_review` value into the build and resolve it at run
time?** **Yes.** Two independent pieces of evidence, both observed, neither assumed:
- CI run **38168789547** (quick, green): `L10N04SpanishResolutionTests` passed — 527
  placeholder-free keys resolved via `Bundle.localizedString(forKey:)` on the compiled `es.lproj`
  sub-bundle, plus plural/placeholder/post-freeze/Language-row spot checks through the real `L10n`
  wrappers, all under the `es` locale.
- The *same* run's `ScreenFormatterLocaleTests` (a pre-existing, not-mine file) failed on 3
  functions whose `es_ES` expectations assumed `es` had no translations yet — because it now does,
  `String(localized:)` returned real Spanish ("92 de 100", "1 tarea faltante aún se acepta" / "3
  tareas faltantes aún se aceptan", "Racha de 1 día" / "Racha de 5 días"), matching this work
  package's own catalog exactly. Fixed in commit `62e79ce` (CI run **38168789547**, green after the
  fix, confirming it).
- The Audit tour's own `es` dispatches (runs 38175021381, 38179171050; see §5) show real Spanish
  throughout the app, visually confirmed (see the owner sheet).

**Path taken: `needs_review`, no fallback.** `docs/l10n/es-review-status.md` was not needed.

## 3. Glossary

`docs/l10n/es-glossary.md` — the Canvas-vocabulary table, voice/variant notes, terms chosen that
weren't in the brief's seed (flagged for the reviewer to confirm), and the never-translated list.

## 4. Length fixes (Spanish rewordings and layout changes)

- `dashboard.greeting` ("Good %1$@, %2$@" → "%1$@, %2$@"): Spanish has no single "Good <word>" stem
  that composes with morning/afternoon/evening the way English does ("Buenos días" / "Buenas
  tardes" / "Buenas noches" differ in both the adjective's number and the noun, not just the noun).
  The greeting-word keys now carry the whole greeting; the template keeps both placeholders, same
  types, same order.
- No view-layout changes were made (this work package only adds accessibility identifiers, which
  draw nothing).

## 5. Gate 1 — Spanish vs. English layout-check counts

4 es legs (runs 38175021381 + 38179171050, the ax5 pair re-run once after fixes) vs. 4 fresh en
legs (run 38185483478, same commit `82893aa`, same device/appearance/size matrix — chosen over the
PMO's older `fp7`/`fp5/after-*` baseline because that baseline has no `ax5` captures at all, and
the brief asks to look "especially [at] the smallest iPhone at AX5"):

| Leg | Captures | Truncation | Clipping (offscreenOrClipped) | Overlap | Hit targets < 44 pt |
|---|---|---|---|---|---|
| es proMax std | 60 | 0 | 22 | 476 | 135 |
| en proMax std | 53 | 0 | 33 | 363 | 106 |
| es smallest std | 89 | 0 | 31 | 757 | 194 |
| en smallest std | 59 | 0 | 23 | 490 | 132 |
| es proMax ax5 | 107 | 0 | 61 | 774 | 183 |
| en proMax ax5 | 111 | 0 | 53 | 793 | 185 |
| es smallest ax5 | 120 | 0 | 50 | 842 | 188 |
| en smallest ax5 | 120 | 0 | 54 | 702 | 178 |
| **Total** | es 376 / en 343 | **0 / 0** | 164 / 163 | 2849 / 2348 | 700 / 601 |

**Truncation: 0 in both — holds.** **Clipping: 164 vs. 163 — essentially flat** (es's capture count
is 376 vs. en's 343, so per-capture clipping is *lower* in Spanish: 0.44 vs. 0.48). Both explicit
gate-1 criteria ("truncation and clipping counts may not rise") **pass**.

Overlap (+21%) and small-hit-target (+16%) counts are higher in Spanish; visually confirmed (owner
sheet, and a sample of the raw `.layout.json` overlap pairs) that the largest contributor is the
**already-documented false-positive pattern** in `pmo-audit/.build-audit/review/defects.md`'s
"Layout-check triage": "combined accessibility element vs. its children" — e.g. the new Language
row's own label element ("Idioma") overlapping its combined "Idioma, español" accessibility
element, the same pattern already catalogued there for "Average of 5 courses, 88.3%, B ⊃ 88.3%"
etc. Longer Spanish strings wrap to more lines more often, which mechanically produces more of
these container/child pairs; this was not reclassified line-by-line for all 2849 pairs (out of
scope for the time available), so the overlap/hit-target deltas are reported as-is, with this
pattern named as the probable majority cause rather than asserted as fully explained.

Visual spot check (dashboard, settings, Course Options menu, at smallest+AX5 and proMax+std):
clean wrapping, no ellipsis truncation, no clipped text, in both languages — see the owner sheet.

**Owner sheet:** `pmo-audit/.build-audit/l10n-04/owner-sheet-l10n-04.jpg` (0.54 MB) — Dashboard
(smallest, AX5), Settings (smallest, std), Course Options menu (proMax, std), es left / en right,
plus a note on the widget gap (§8 item 1).

## 6. Strings PENDING owner approval (new English + Spanish)

| Key | English | Spanish |
|---|---|---|
| `settings.language.label` | Language | Idioma |
| `settings.language.footer` | Tally uses your iPhone's language. iOS shows a Language choice here only when your iPhone has more than one preferred language. | Tally usa el idioma de tu iPhone. iOS muestra la opción de idioma aquí solo cuando tu iPhone tiene más de un idioma preferido. |

## 7. Device checks

- The Settings → Language row and `UIApplication.openSettingsURLString`: **UNVERIFIED on a
  device** (none available to this work package). The row renders correctly on the simulator
  (visually confirmed, e.g. `185-family-linkedStudents` capture: "Idioma" / value "español"). The
  L10N-01 spike already found, on the simulator, that `openSettingsURLString` opens Settings at its
  root, not Tally's own page — unchanged, pre-existing, not re-tested here.
- A widget on a Spanish Home Screen: **UNVERIFIED, and the hosted test does not substitute for
  it** — see open item 1 below.

## 8. Open items

1. **`WidgetFamilyRenderTests.spanishSnapshot` does not verify Spanish content.** Found by visually
   inspecting the attached PNGs (they are in English). Root cause: `GlanceWidgetViews`' views take
   no `locale` parameter; they call `GlanceText.*`, which defaults to `TallyLocale.effective` (read
   from `Bundle.main.preferredLocalizations` at the call site), never SwiftUI's `\.locale`
   environment. A real fix needs a `locale:` parameter threaded into the widget views themselves —
   a `TallyGlance` production-code change outside this work package's ownership, and unverifiable
   now (CI budget spent). The test's doc comment and title were corrected so it no longer claims to
   verify Spanish; it still renders and attaches the PNGs as a draws-without-crashing smoke test.
   On a real device, the widget extension's own `Bundle.main.preferredLocalizations` does reflect
   the per-app Language setting (L10N-01 spike, run 36775064980, observed directly), so this is
   believed to be a test-harness gap, not a known production one — "believed" because it was not
   re-verified on a device by this work package.
2. **Destructive confirmations remain English-label-dependent in the Audit tour**: Sign Out &
   Erase / Unlink / Remove's Cancel and destructive buttons, and their confirmation titles
   (`TallyConfirmationAction`, `Support/DestructiveConfirmation.swift`). Fixing it needs a new
   field on that shared component plus call-site updates in three files — out of scope for "add
   `.accessibilityIdentifier`, nothing else changes."
3. **Two soft-degrading English-label checks** in the Audit tour, neither a crash under `es`: the
   To-Do batch-select "already done" filter (`label CONTAINS 'Marked done in Tally'`) just stops
   filtering; the slow-refresh breadcrumb check (`label BEGINSWITH 'Live refresh is taking
   longer...'`) just records a "missing-breadcrumb" screenshot instead of "breadcrumb".
4. **`openSettings`'s AX5 fix (commit `82893aa`) could not be re-verified in Spanish**: the es
   budget (2 dispatches, each already retried once for this exact failure) was spent finding and
   fixing it. The *English* check (run 38185483478, same commit, same AX5 legs) passed cleanly
   end-to-end, including the method that found the bug (`testO_parentEmptyState`) — strong but
   indirect evidence, not a direct Spanish re-verification.
5. Overlap/hit-target count deltas (§5) were not reclassified pair-by-pair against
   `defects.md`'s full triage list; the probable majority cause is named, not proven exhaustively.
6. Device checks (§7) are simulator/hosted only.
7. The native-speaker review itself has not started; every Spanish value is `needs_review`.

## 9. CI run IDs

| Run | Scope | Result |
|---|---|---|
| 38162093324 | quick (1/3) | failed — `L10N04SpanishResolutionTests` compile errors (fixed, `aa165da`) |
| 38163491969 | quick (2/3) | failed — `ScreenFormatterLocaleTests` stale es_ES expectations (fixed, `62e79ce`) |
| 38168789547 | quick (3/3) | **green** — confirms needs_review resolves at run time (§2) |
| 38175021381 | Audit tour, es (1/2) | failed — Tab() identifier gap + shared-helper English literal (fixed, `8b65c57`); std legs' root causes fixed, ax5 legs partially |
| 38179171050 (+ 1 rerun of its failed jobs) | Audit tour, es (2/2) | std legs green; ax5 legs failed on one AX5-specific `openSettings` timing bug (fixed, `82893aa`, unverified in es — open item 4) |
| 38185483478 | Audit tour, en (1/1) | **green**, all 4 legs — the English tour still passes |

## 10. Evidence paths

- Owner sheet: `/home/rahart1362/Documents/Tally-worktrees/pmo-audit/.build-audit/l10n-04/owner-sheet-l10n-04.jpg`
- Review CSV (for the native-speaker reviewer): `/home/rahart1362/Documents/Tally-worktrees/pmo-audit/.build-audit/l10n-04/es-review.csv` (772 rows; `scripts/l10n/es_review.py export`)
- Raw es/en Audit tour captures: `/home/rahart1362/Documents/Tally-worktrees/pmo-audit/.build-audit/l10n-04/{es,en}/audit-*`
- None of the above are committed to the repo (public; images and the CSV are excluded per the brief).
