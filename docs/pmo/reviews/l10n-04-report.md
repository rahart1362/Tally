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

## 10. Evidence paths (round 1)

- Owner sheet: `/home/rahart1362/Documents/Tally-worktrees/pmo-audit/.build-audit/l10n-04/owner-sheet-l10n-04.jpg`
- Review CSV (for the native-speaker reviewer): `/home/rahart1362/Documents/Tally-worktrees/pmo-audit/.build-audit/l10n-04/es-review.csv` (772 rows; `scripts/l10n/es_review.py export`)
- Raw es/en Audit tour captures: `/home/rahart1362/Documents/Tally-worktrees/pmo-audit/.build-audit/l10n-04/{es,en}/audit-*`
- None of the above are committed to the repo (public; images and the CSV are excluded per the brief).

---

# Round 2 — gate-2 fixes

Author: Spanish Localization Engineer, round 2 (Claude Sonnet 5). PR #51, branch `l10n/es`,
starting at round 1's hand-off commit `5481437`. Task list: the PMO's Opus gate-2 design review,
`/home/rahart1362/Documents/Tally-worktrees/pmo-audit/.build-audit/l10n-04/review/verdict.md`.
Journal: `build/logs/journal/2026-10-12-l10n-04-r2.md`.

## R1. Verdict item → change → file/key → evidence

| Verdict item | Change | File / key | Evidence |
|---|---|---|---|
| Fix 1 (L1) | `onboarding.schoolSearch.searchPrompt` → "Escuela o dirección de Canvas" | `Localizable.xcstrings` | `112-schoolSearch-idle.png` (smallest std): full text, no ellipsis — owner sheet row 1 |
| Fix 2 (L2) | `courseDetail.override.menuRowTitle` → "Calificaciones externas" (23 chars) | `Localizable.xcstrings`; test expectation also fixed in `L10N04SpanishResolutionTests.postFreezeKeysResolveInSpanish` | `302-course1-gradesOutsideCanvas.png` (smallest AX5): wraps "Califica-/ciones/externas" on 3 lines, no truncation — owner sheet row 2 |
| Fix 3 (L3, T14) | `courseDetail.whatIfHeader` → "Simulador" | `Localizable.xcstrings` | `303-course1-whatIf.png` (smallest AX5): sheet title "Simulador" fits the toolbar — owner sheet row 3 |
| Fix 4 (L4) | `onboarding.schoolSearch.navigationTitle` → "Buscar escuela"; `onboarding.schoolSearch.cantFindIt` → "¿No aparece?" | `Localizable.xcstrings` | `112-schoolSearch-idle-UNSETTLED.png` (proMax AX5): both read in full |
| Fix 5 (L5, T19) | `freshness.updatedJustNow` → "Actualizado ahora" | `Localizable.xcstrings` | `63-todo-batchSelect.png` (smallest AX5) subtitle: full text |
| Fix 6 (L6), layout half | `LockedFeatureCard` reserves the floating tab bar's footprint (`TallySpacing.tabBarClearance` = 96 pt, `.safeAreaPadding(.bottom:)`) | `SubscriptionLockViews.swift`; new token in `Spacing.swift` | `156-lockedTab-card.png` (smallest AX5): "Ver planes" now sits with clean margin above the tab bar (round 1: button bled into/under it — see owner sheet row 4). The tap now reaches the button: `157-paywall-fromLockedTab-top.png` through `-scroll8.png` show the real paywall ("Tally Annual", "Qué incluye"), not the locked card — round 1 had the same bug (156 only, no paywall captures) |
| Fix 6, copy half | `subscription.locked.body` shortened | `Localizable.xcstrings` | same captures |
| Fix 7 (T1) | `widget.asOf` → "Datos de %@"; `widget.answer.asOf` → "Estos datos son de %@." | `Localizable.xcstrings` | not independently captured this round (not stale-data in the fixture's test data); catalog-verified |
| Fix 8 (T2) | 5 Week-ahead keys → "Próximos 7 días" (header) / "Tu semana" (widget, notification, toggle) | `Localizable.xcstrings`, widget catalog | catalog-verified; `widget-week-ahead-large-es-*.png` (see R4) |
| Fix 9 (T3) | `insights.completion.detail`/`.subtitle` reworded | `Localizable.xcstrings` | `77-insights-scroll1.png` (smallest std): "Entregaste a tiempo 36 de 41 tareas cuya fecha ya pasó." / "Tareas con fecha ya pasada que entregaste a tiempo este período." — owner sheet row 6 |
| Fix 10 (T4) | `courses.health.aboveGoalReason` → "%1$@ de tu meta de %2$@" | `Localizable.xcstrings` | catalog-verified (grammatical now, matches sibling `aboveCutoffReason`'s "del") |
| Fix 11 (T5) | New key `insights.category.other` (en "Other", es "Otras") for `InsightsProjection.swift:261`'s bare literal | `L10n+GradeScreensSweep.swift`, `InsightsProjection.swift`, `Localizable.xcstrings` | `77-insights-scroll1.png`: chart shows "Otras 30%" — owner sheet row 6 |
| Fix 12 (T6) | `freshness.delayed/failed/authExpired.long`, `subscription.banner.savedFrom`: placeholder moved mid-sentence, no sentence-final period after it | `Localizable.xcstrings` | `156-lockedTab-card.png`: "Mostrando datos guardados de oct 12, 2026, 5:39 a.m. — suscríbete para actualizar" (no double period) |
| Fix 13 (T7) | `courses.formatter.dueAtTime`/`.atTime`, `notification.dayAtTime`, `widget.answer.when.*`, `calendar.agenda.due.spoken`: comma, not "a las" | `Localizable.xcstrings` | `61-todo-default.png` (smallest std): "BIO 101 · Vence mañana, 1:00 p.m." on one line — **this is also L8's fix**, confirmed resolved by shorter wording (see R3) |
| Item 14 (L10, required) | Language row: primary-coloured label, trailing `arrow.up.forward`, value capitalized by locale (`Español`); footer replaced with the reviewer's round-2 draft (`settings.language.footerV2`) | `SettingsView.swift` (`languageSection`, `currentLanguageName`), `L10n.swift`, `Localizable.xcstrings` | `91-settings-top.png` (smallest std): black "Idioma" label, "Español ↗" value, new footer in full — owner sheet row 5 |
| Item 15 (T8–T30) | Applied T8, T9, T10, T11, T12, T13, T15–T20, T22–T28, T30; T21 resolved differently; T29 declined | `Localizable.xcstrings`, `AppIntents.xcstrings`, `es-glossary.md` | catalog-verified (see R2 for the per-item rationale already in each edit's inline comment, and R5 for T21/T29/T14 cross-references) |
| Item 16 | `TallyConfirmationAction`/`tallyDestructiveConfirmation` gained `accessibilityIdentifier`; Audit tour switched from English-text matches to ids; fixed the Rowan/Skyler misfile; fixed the To-Do batch-select filter and the slow-refresh breadcrumb (both now identifier-based, not a spoken English literal) | `DestructiveConfirmation.swift`, `SettingsView.swift`, `FamilySettingsViews.swift`, `ToDoScreen.swift`, `FreshnessViews.swift`, `AuditTourUITests.swift`, `ScreenUITestSupport.swift`, `ToDoUITests.swift` | **std legs (both devices): all 4 captured and correctly named** — `96-settings-signOutConfirm.png`, `186-family-unlinkConfirm.png`, `201-family-removeConfirm-Rowan.png`, `202-family-removeConfirm-Skyler.png`, `203-family-parentEmpty.png` (round 1: `settings-signOutConfirm` and `family-unlinkConfirm` were entirely missing on every leg; `removeConfirm-Skyler` showed Rowan's dialog). Breadcrumb: `216-slowRefresh-breadcrumb` present on every leg (round 1: `missing-breadcrumb` on every leg). **AX5 legs: still not captured** — see R3, this is a pre-existing, unchanged-by-this-round gap, not a regression |
| Item 5 (widget locale seam) | New `\.glanceLocaleOverride` environment value (`GlanceLocaleOverride.swift`), read by every `GlanceText.*` call site across the 3 `TallyGlance` view files; `WidgetFamilyRenderTests` updated to assert real Spanish content plus a default-unchanged test | `GlanceLocaleOverride.swift` (new), `GlanceWidgetViews.swift`, `GlanceListWidgetViews.swift`, `GlanceAccessoryViews.swift`, `WidgetFamilyRenderTests.swift` | `widget-due-soon-medium-es-light-pro-max.png`: "VENCE PRONTO", "Vence hoy, 18:00", "+2 más · 1 atrasada" — real Spanish, not the round-1 English-byte-identical renders (see R4) |

## R2. S3 items declined or resolved differently (item 15)

- **T21** (`subscription.name.student`): reviewer suggested matching App Store Connect's own es
  display name, or keeping "Tally Annual". This host cannot query App Store Connect, so the es
  value was changed **back to "Tally Annual"** (the safer of the two options the reviewer offered)
  rather than guessing a translation that might disagree with the real purchase sheet.
- **T29** (date formatting, `ScreenFormatter`/`TallyLocale`): declined. The verdict's own text for
  this row says "the native reviewer should confirm the es-US pattern" — that is the reviewer
  flagging genuine uncertainty, not a "clearly better" call this round should make unilaterally.
  Recorded as open (R6).
- **T14** was already covered by fix 3 (L3/item 3): one catalog edit serves both.

## R3. The AX5 confirmation-capture gap (item 16, partial)

Both std legs now capture and correctly name all four screens (`settings-signOutConfirm`,
`family-unlinkConfirm`, `family-removeConfirm-Rowan`, `family-removeConfirm-Skyler`,
`family-parentEmpty`). **Both AX5 legs still do not** — `testG_settingsSignedIn` and
`testN_sampleDataAndParentMode` pass (no assertion failure; `continueAfterFailure` plus
non-asserting `goScrolling`/`waitForExistence` calls that silently skip a capture when an element
isn't found), but neither reaches a `snap()` call for the sign-out/unlink confirmation at AX5;
`testO_parentEmptyState` gets as far as `201-family-missing-removeStudent-Skyler` (Rowan's own
removal must have succeeded silently) before failing to find the Skyler row.

**Confirmed pre-existing, not a round-2 regression**: round 1's own AX5 es captures
(`pmo-audit/.build-audit/l10n-04/es/audit-es-proMax-light-ax5/`) show the *identical* gap —
`201-family-missing-removeStudent-Skyler`/`202-family-missing-parentEmpty` with the same step
numbers, and no `settings-signOutConfirm`/`family-unlinkConfirm` captures at all, before any of
this round's identifier changes existed. The root cause is a separate, AX5-specific timing/element
gap (likely related to round 1's own open item 4, the `openSettings` AX5 timing issue) — outside
item 16's actual scope (which was the English-text-dependency bug, now fixed and confirmed on std)
and outside this round's remaining CI budget to chase further (the one Audit tour dispatch is
spent). Recorded as an open item (R6).

## R4. Widget locale seam — verification

`WidgetFamilyRenderTests` ran as part of the (green) PR run `38201921389` and the Audit tour's
proMax/std leg (which also exports that suite's attachments). Spot-checked at full resolution:

- `widget-due-soon-medium-es-light-pro-max.png`: header "VENCE PRONTO" (was "DUE SOON"), due lines
  "Vence hoy, 18:00" / "Vence jueves, 9:00" (T7's fix, visible end-to-end), footer "+2 más · 1
  atrasada" — real Spanish, not round 1's byte-identical-to-English renders.
- `widget-due-today-circular-es-light-pro-max.png` and the `-smallest` variant also present.
- The new `spanishSnapshot` test (`en` vs. `es` text compared, never-translated titles/course codes
  checked unaffected) and `localeSeamDefaultsToUnaffectedEnglish` (no-override path byte-identical
  to explicit English) both passed in the same green run.
- Not independently re-opened at 200% beyond the one spot check above (CI/time budget); no
  oversized or clipped Spanish widget text was observed in what was checked.

## R5. S3 layout (L7–L9, L11) — fixed only where shorter wording already did it

- **L8 resolved** by item 13/T7's wording fix (not a layout change): `61-todo-default.png` shows
  "BIO 101 · Vence mañana, 1:00 p.m." on one line, where round 1 wrapped to two with a hanging
  indent and a vertically-off-centre course code. No code layout touched.
- **L7** (mid-word hyphenation on single words — "Desbloquear con Face ID", "Cumplimiento",
  "Calificaciones", "Recordatorios"): no shorter wording exists for these without changing their
  meaning or breaking consistency with the glossary's chosen terms. Open (R6).
- **L9** (a date breaking mid-value, "…hasta oct / 11, 2027"): tied to T29's date-format question
  (day/month order, native-reviewer confirmation needed) — not touched for the same reason T29 was
  declined. Open (R6).
- **L11** (an orphaned "se acepta" on the Dashboard's Next-up meta line): the candidate shorter
  wording (dropping "Aún" from `dashboard.reason.stillAccepted`) would weaken the "still accepted"
  meaning (a real fact: late work past its due date but not yet closed off) — not a safe "clearly
  better" edit, and no S3 layout changes are in scope this round. Open (R6).

## R6. Open items (round 2)

1. **AX5 confirmation captures** (R3): `settings-signOutConfirm`, `family-unlinkConfirm`,
   `family-removeConfirm-Skyler`, `family-parentEmpty` are not captured at AX5 on either device —
   pre-existing, confirmed unchanged from round 1, root cause not chased (CI budget spent).
2. **L7, L9, L11** (R5): no safe shorter-Spanish-wording fix found; all three need either a layout
   change (out of scope for S3) or, for L9/T29, a native reviewer's date-format confirmation first.
3. **T29**: date formatting (`ScreenFormatter`/`TallyLocale`) needs the native reviewer's
   confirmation of the es-US day/month order before any change.
4. **T21**: `subscription.name.student` kept as the English "Tally Annual" rather than guessing a
   translation; needs the real App Store Connect es listing (or a reviewer decision) to settle.
5. Fix 7/T1 (`widget.asOf`/`widget.answer.asOf`) and fix 8/T2 (the week-ahead keys) were not
   independently visually re-verified this round beyond catalog correctness and the one widget
   spot check in R4 — no stale-data or week-ahead screen happened to appear in this round's
   captures.
6. Round 1's open items 5–7 (overlap/hit-target deltas not reclassified pair-by-pair; device
   checks are simulator/hosted only; the native-speaker review has not started) all still apply.
7. Every Spanish value remains `needs_review`; nothing in this round changed that state.

## R7. Strings PENDING owner approval (round 2)

The Language row footer: **round 1's draft is superseded** by a new round-2 key
(`settings.language.footerV2`); round 1's key (`settings.language.footer`) was removed from the
catalog (an unused key fails CI's "every key is used" check) — its English is preserved here
verbatim, unedited, for the owner to compare against the new draft:

| Draft | English | Spanish |
|---|---|---|
| Round 1 (`settings.language.footer`, removed from the catalog) | Tally uses your iPhone's language. iOS shows a Language choice here only when your iPhone has more than one preferred language. | Tally usa el idioma de tu iPhone. iOS muestra la opción de idioma aquí solo cuando tu iPhone tiene más de un idioma preferido. |
| Round 2 (`settings.language.footerV2`, current) | Tally uses your iPhone's language. To pick a language just for Tally, open Settings → Apps → Tally → Language. iOS shows that choice only after you add a second language in Settings → General → Language & Region. | Tally usa el idioma de tu iPhone. Para elegir un idioma solo para Tally, abre Configuración → Apps → Tally → Idioma. iOS muestra esa opción solo después de agregar un segundo idioma en Configuración → General → Idioma y región. |

`settings.language.label` ("Language"/"Idioma") is unchanged from round 1, still PENDING.

## R8. CI run IDs (round 2)

| Run | What | Result |
|---|---|---|
| 38188594780 | Round 1's own PR run, re-checked before round-2 work started | **green** (confirmed before any round-2 push) |
| 38195787377 | Push 1 (`d533a19`) | failed — `GlanceLocaleOverride.swift` missing `import TallyStrings` (fixed, `8ce19bc`) |
| 38196505757 | Push 2 (`8ce19bc`) | failed — `Character.uppercased(with:)` doesn't exist (fixed, `7658e85`); also prompted the Spanish-fixture regeneration (`b22cee3`), found by inspection, bundled into the same cycle |
| 38196873833 → 38197001967 (queue coalesced) | Push 3 (`b22cee3`/`7658e85`) | compiled and ran — `FamilyUITests` (pre-existing, not this round's file) failed on an identifier-prefix collision (fixed, `d677b86`) |
| 38201921389 | Push 4 (`d677b86`) | **green**, every required job |
| 38206798273 | es Audit tour (1/1): `devices=["proMax","smallest"]`, `appearances=["light"]`, `sizes=["std","ax5"]`, `widgets=true`, dispatched on `d677b86` | **green**, all 4 legs |

Every push's own PR re-run served as this round's "iteration run" (no separate `scope=quick`
dispatch was used — see the journal for why). One Audit tour dispatch used, as budgeted.

## R9. Gate 1 — round 2 layout-check counts vs. round-1 baselines

| | Captures | Missing | Truncation | Clipping | Overlap | Hit targets < 44 pt |
|---|---|---|---|---|---|---|
| es round 1 (baseline) | 376 | 18 | 0 | 164 | 2849 | 700 |
| es round 2 | 340 | 10 | **0** | **142** | 2446 | 608 |
| en round 1 (baseline) | 343 | 10 | 0 | 163 | 2348 | 601 |

**Truncation stays 0. Clipping dropped from 164 to 142** — now *below* the English baseline (163).
Overlap and hit-target counts also dropped (2446 vs. 2849; 608 vs. 700), consistent with shorter
Spanish wording producing fewer wrapped lines and fewer of the already-documented
"combined-element-vs-children" false positives (round-1 report §5). Missing captures dropped from
18 to 10 — the difference is exactly `settings-signOutConfirm`/`family-unlinkConfirm`/
`family-removeConfirm-Rowan` (std legs, now captured) and `slowRefresh-breadcrumb` (all 4 legs, now
captured); the remaining 10 are the pre-existing AX5 gap (R3) plus two unrelated, unchanged gaps
(`demoSignIn-firstSyncProgress` timing, `course2-missing-detail`) present identically in both
rounds.

Visually confirmed at full resolution (not just the owner-sheet thumbnails): L1–L6, L8, the
Language row, and the Insights "Otras" category all read correctly with no ellipsis and no
clipping, on the specific legs the verdict named. See R1's evidence column for each.

**Owner sheet:** `pmo-audit/.build-audit/l10n-04/es-r2/owner-sheet-l10n-04-r2.jpg` (478 KB) — es
round 1 vs. es round 2, six paired screens (L1, L2, L3, L6, the Language row, Insights "Otras").

## R10. Evidence paths (round 2)

- Owner sheet: `/home/rahart1362/Documents/Tally-worktrees/pmo-audit/.build-audit/l10n-04/es-r2/owner-sheet-l10n-04-r2.jpg`
- Review CSV, refreshed for round 2's edits: `/home/rahart1362/Documents/Tally-worktrees/pmo-audit/.build-audit/l10n-04/es-review.csv` (773 rows)
- Raw es round-2 Audit tour captures: `/home/rahart1362/Documents/Tally-worktrees/pmo-audit/.build-audit/l10n-04/es-r2/audit-es-*`
- CI job logs (downloaded for diagnosis, not evidence artifacts): `.build-l10n-04-r2/logs/` (git-ignored, inside the worktree)
- None of the above are committed to the repo (public; images, logs and the CSV are excluded).
