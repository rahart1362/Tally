# UX-FP4 report — contrast, targets and consistency

Branch `ux/fp4-consistency`, from `origin/main` @ `a99c0c0` (UX-FP1, UX-FP2, UX-FP6 and UX-FP3
merged; worktree pre-created and verified clean by the PMO). No merge of `origin/main` was needed
(still `a99c0c0` as of this report; rule 3). Journal: `build/logs/journal/2026-10-09-ux-fp4.md`.
Attribution: Claude Sonnet 5.

## Two shared pieces, used everywhere

- `TallySectionText` / `.tallySectionText()` (`TallyDesignSystem/ScreenChrome.swift`) —
  `TallyColor.textSecondary` on a `Section` header/footer `Text`, applied inside each
  `header:`/`footer:` closure (never on the `Section` itself, which would also recolour its
  content).
- `TallyLabeledContentStyle` / `.labeledContentStyle(.tallySecondaryValue)`
  (`TallyDesignSystem/ScreenChrome.swift`) — a custom `LabeledContentStyle` wraps
  `configuration.content` in `.foregroundStyle(TallyColor.textSecondary)` explicitly, applied once
  per `Form` (Settings, Subscription). A plain ambient `.foregroundStyle(...)` was not used: SwiftUI
  resolves a `LabeledContent` value's default `.secondary` style *hierarchically* (a dimmed variant
  of whatever primary is in scope), not as the literal `textSecondary` colour.

## Defects

"Before" captures: `pmo-audit/.build-audit/fp3/after-37936616803/` (current-main baseline, PM std,
light + dark). "After": Audit tour run **37990973140**, all 8 legs, widgets off.

| Defect | What changed | `file:line` | Evidence | Layout delta |
|---|---|---|---|---|
| **D30 (S2)** sheets lose the Tally tint (system iOS blue, not `accent`) | `.tint(TallyColor.accent)` was chained onto the `TabView` node only — a sibling scope to `.sheet(item: presentedSheet)`, not an ancestor of it. Wrapped the sheet's `switch` content in a `Group` with its own `.tint(...)`: fixes Settings directly, and Subscription/Family for free (pushed from Settings' own `NavigationStack`, which inherits it). `SubscriptionSettingsView` presents its own, separate `.sheet(item: $paywall)` for the Paywall — added the identical explicit `.tint(TallyColor.accent)` there too. | `Home/HomeShellView.swift:181-202`; `Settings/SubscriptionSettingsView.swift:96-105` | `evidence/D30.jpg` | counts fell (see "Layout-check totals" below) |
| **D07 (S2)** system secondary grey fails 4.5:1 | `.tallySectionText()` on every header/footer `Text` in Course detail, the Grades tab, the What-If header (Course detail's entry point), To-Do, Calendar, Settings (+ embedded Linked-students/Reminders/Family-sharing), Subscription and Family (incl. its sheets); `.labeledContentStyle(.tallySecondaryValue)` once on Settings' and Subscription's `Form`; `CategoryWeightsChart`'s y-axis `AxisValueLabel` styled in `.chartYAxis { ... }` (one component behind *both* Course detail's and Insights' chart — confirmed one `struct CategoryWeightsChart`, called from both screens). `CourseDetailView.swift`'s `Section(section.title)` convenience init was converted to an explicit `header: { Text(...) }` so the assignments-list header (same under-contrast grey) could take the modifier too. | `CourseDetail/CourseDetailView.swift` (8 sites); `CourseDetail/WhatIfSheet.swift`: not touched (see Open items); `Insights/ScreenCharts.swift:29-35`; `ToDo/ToDoScreen.swift:29`; `Calendar/CalendarScreen.swift:37,54`; `Settings/SettingsView.swift` (8 header/footer sites + `.labeledContentStyle` at :97); `Settings/SubscriptionSettingsView.swift:44,82`; `Reminders/RemindersViews.swift:142,150`; `Family/FamilySettingsViews.swift` (9 sites) | `evidence/D07.jpg` | counts fell |
| **D10 (S2)** custom tap targets under 44 pt | Moved `.frame(minHeight: 44).contentShape(Rectangle())` **inside the label**, ahead of the button style — `WhatIfSheet.swift`'s chips already had the frame, but chained *after* `.buttonStyle(.bordered)`, the exact bug D10 describes (it sizes the layout box, not the style's own hit region). Converted the convenience `Button(title) { action }`/`Link(dest) { Text }` calls to the label-closure form for Paywall Restore/Redeem, the two legal links, the What-If chips, and School search's Retry. | `Subscription/PaywallView.swift:215-234` (Restore/Redeem), `:261-274` (Terms/Privacy); `CourseDetail/WhatIfSheet.swift:198-216` (chips); `Onboarding/SchoolSearch/SchoolSearchView.swift:165-171` (Retry) | `evidence/D10.jpg` | hit-target counts fell sharply (below) |
| **D12 (S2)** Paywall feature icons have no fixed width (ragged text edge) | `.frame(width: 28)` on the feature icon, matching `WelcomeView.swift`'s `BenefitRow` exactly. | `Subscription/PaywallView.swift:109-112` | `evidence/D12.jpg` | no change (no element moved/added) |

### Measured contrast (pixel-sampled from the "after" captures, Pro Max std unless noted; WCAG relative luminance)

| Control | Light | Dark | Needs |
|---|---|---|---|
| D30 Settings "Turn On Reminders" | 3.52 → **7.97:1** | 4.31 → **6.71:1** | ≥ 4.5:1 |
| D30 Paywall "Restore Purchases" | 3.14 → **7.11:1** | 6.20 → **9.64:1** | ≥ 4.5:1 |
| D30 Subscription "Redeem Code" | 3.52 → **7.97:1** | — (not separately captured; same `accent` token as the rows above) | ≥ 4.5:1 |
| D07 Course detail footer ("Set by your instructor") | 3.30 → **6.98:1** | 6.31 → 10.01:1 (already passed; confirmed no regression) | ≥ 4.5:1 |
| D07 Category-weights chart label ("Lab Reports") | 3.44 → **7.69:1** | not separately sampled (chart uses the same `textSecondary` token in both appearances) | ≥ 4.5:1 |

Sampled fg colours matched the source tokens exactly: light `(29,78,158)` = `#1D4E9E` (`accent`
Any); dark `(141,180,255)` = `#8DB4FF` (`accent` Dark); the D07 text samples `(71,84,103)` /
`(174,184,200)` match `textSecondary`'s Any/Dark appearances. Method: `python3 -m PIL`, most-common
colour in the region vs. the pixel farthest in luminance from it, WCAG contrast computed directly —
script (`measure.py`) and raw numbers are in `.build-audit/fp4/` (git-ignored by its parent
worktree's convention; not committed, the repo is public). Spot-checked `smallest`-device and
AX5-size legs visually (read, not auto-measured, since the Settings-screen crop coordinates are
Pro-Max-calibrated) — `Turn On Reminders` renders in `accent` on `smallest-light-std` and
`smallest-dark-std` alike.

### Measured hit targets (from the Audit tour's own `hitTargetsUnder44pt` check, Pro Max std)

| Screen | Before (flagged) | After (flagged) |
|---|---|---|
| Paywall top | 5: Not Now, **Restore**, **Redeem**, **Terms**, **Privacy** | 1: Not Now (not mine — see Open items) |
| What-If (course 1) | 10: Sheet Grabber, Done, **8 quick-fill chips** | 2: Sheet Grabber, Done (system, not mine) |
| School search failure | 4: **Retry** (18 pt), Clear text, close, Continue | 4: **Retry** (now 44 pt tall, 36.67 pt wide — see Open items), Clear text, close, Continue |

Confirmed directly from the layout JSON: Retry's frame went from `{height: 18, width: 36.67}` to
`{height: 44, width: 36.67}` — it still appears in the list because its *width* (a short word) is
under 44 pt, which `.frame(minHeight: 44)` never touches (same shape as the already-accepted "See
Plans" fix, `SubscriptionLockViews.swift`, which is also height-only). See Open items.

### Layout-check totals (all 8 legs, matched by filename)

| Check | Before | After |
|---|---|---|
| `overlap` | 4880 | 4767 |
| `offscreenOrClipped` | 481 | 297 |
| `hitTargetsUnder44pt` | 1443 | 1286 |

All three fell in aggregate — no systemic regression. A per-file diff found 85 individual
file/metric increases, concentrated on screens this package never touched (Dashboard, Insights,
`demoSignIn-missing-firstSyncProgress`) as much as ones it did, and inspecting the largest ones
(e.g. `course1-scroll1` dark std, +8 `overlap`) shows the same categories `defects.md`'s own
"Layout-check triage" already discards as noise — `BackButton`/`courseDetail.menu` vs. a row's text
("content under nav/toolbar items… Promoted → D01", a captured-mid-scroll artifact, not a real
overlap) — consistent with this package's changes being colour/tint/`frame(minHeight:)`/
`chartYAxis` only, none of which can move an element under a different row on an unrelated screen.

## S3s done

- **Increase Contrast**: `accent.fill.colorset` gets a High Contrast appearance — Any `#123C80`
  (reusing `accent`'s own High Contrast Any; both tokens already share the same normal-contrast Any,
  `#1D4E9E`), Dark `#1F4690` (computed: `accent.fill` is always a background *fill* behind a white
  label in both appearances, so its HC moves *darker*, unlike `accent` itself, which is foreground
  text and moves lighter in dark). Computed white-on-fill: light 7.97 → 10.59:1, dark 5.99 → 8.98:1.
  **UNVERIFIED on a device** — no Increase Contrast capture exists to measure from; computed from
  the asset's own sRGB components with the WCAG formula. `TallyColor.swift:58-67`,
  `accent.fill.colorset/Contents.json`.
- **Welcome AX5 grey haze**: confirmed ours — `WelcomeView.swift`'s `ScrollView` has no nav bar
  (`.toolbar(.hidden, for: .navigationBar)`) and never picked up any half of
  `tallyScreenChrome()`/`tallyLargeTitleScreenChrome()`, so the tall navy brand panel scrolling
  under the status bar at AX5 got the system's default `.soft` fade. Added
  `.scrollEdgeEffectStyle(.hard, for: .top)` alone (the `toolbarBackground` half is moot with no
  bar) — the same fix D01 uses everywhere else. `WelcomeView.swift:60-65`.

## S3s evaluated, not done

- **What-If chip consistency** — decision, no code change. `.tallySecondary`'s label is `accent`
  via `.tint`, which is exactly what ux-fp6's D32 measured at 4.02:1 in dark on the chip's `bgCard`
  — below 4.5:1. The chips' `textPrimary` label (D32, already merged) is the only one of the two
  that clears ≥ 4.5:1 in both appearances; matching "every other bordered button" would regress
  D32. Keeping `textPrimary` is the decision — compact in-row selectors read differently from
  primary/secondary CTAs by design, not as an unresolved inconsistency.
- **Form bar's own High Contrast appearance** — declined. `ScreenChrome.swift`'s own round-3
  comment already flags that swapping the fixed hex (`#F2F2F7`/`#1C1C1E`) for
  `Color(uiColor: .systemGroupedBackground)` might resolve at the sheet's *base* grouped level
  (`#000000` dark) rather than the *elevated* level it was deliberately measured and set to match —
  unresolved then for the same reason it's unresolved now (no device, no Xcode on this host).
  Risking a silent regression of an already-verified D01 fix for a minor HC benefit on a background
  bar was not worth it.

## CI and Audit tour runs

- **CI iteration run 1 of 3**: **37981757326** (`-f scope=quick`), head `f371d24` — **success**,
  1h22m17s. Required jobs: `hygiene`, `core-linux`, `lint`, `core-sanitizers`, `ios-build` all
  green. No `Failed attempt (retried once)` warnings.
- **Audit tour dispatch 1 of 2**: **37990973140**, all 17 `AuditTourUITests` methods, `-f widgets=false`
  — **success**, all 8 legs green. Downloaded to
  `pmo-audit/.build-audit/fp4/after-37990973140/` (1,694 files; 0 filenames outside
  `[A-Za-z0-9._-]`). 30 `missing-*` captures across all legs, all pre-existing documented gaps
  (`demoSignIn-missing-firstSyncProgress`, `course2-missing-detail`,
  `schoolSearch-missing-field`/`-searchField`) — none on a screen this package touches.
- No mutation run: nothing in this package adds a new guard/gate to mutate.

## Strings PENDING owner approval

None. Every fix here is a colour/tint/frame/width change; no copy, no new `L10n` key.

## Evidence and owner-sheet paths

- `pmo-audit/.build-audit/fp4/evidence/D30.jpg`
- `pmo-audit/.build-audit/fp4/evidence/D07.jpg`
- `pmo-audit/.build-audit/fp4/evidence/D10.jpg`
- `pmo-audit/.build-audit/fp4/evidence/D12.jpg`
- `pmo-audit/.build-audit/fp4/evidence/owner-sheet-ux-fp4.jpg` (904×3597, 323 KB)
- Raw "after" captures: `pmo-audit/.build-audit/fp4/after-37990973140/audit-<proMax|smallest>-<light|dark>-<std|ax5>/`
- Scripts (not evidence, but reproduce it): `pmo-audit/.build-audit/fp4/{lib.py,make_evidence.py,make_owner_sheet.py,measure.py}`

None of this is committed to the repo (public); it stays under `pmo-audit/.build-audit/fp4/` per
the brief.

## Open items

- **D10's "Retry" still appears in `hitTargetsUnder44pt`** — its height is now 44 pt (fixed); its
  *width* (36.67 pt, a one-word label) is not, because `.frame(minHeight: 44)` only grows height.
  This matches the already-accepted pattern for "See Plans" (`SubscriptionLockViews.swift`, height
  only) and what the brief's own fix text asks for ("`.frame(minHeight: 44)`", not `minWidth`); not
  changed further, but flagged since the audit's automated check still technically flags it. A
  device check could confirm whether the real tap target (vs. the accessibility frame) is wider
  than the label frame, as iOS sometimes extends small controls' hit regions.
- **`WhatIfSheet.swift`'s own internal category-group headers** (its `header:`/`footer:` closures at
  roughly lines 39-45, 254-256, 429-431) render in the same under-contrast system grey D07 fixes
  everywhere else, but are not named in D07's "Where" list and were not flagged by the audit —
  left unfixed per "fix only your package's defects," recorded here rather than guessed at.
- **`accent.fill`'s High Contrast values are computed, not device-verified** (see "S3s done").
- **D30's Subscription-screen dark contrast** was not separately pixel-sampled (same `accent` token
  as the Settings/Paywall rows already measured in both appearances; visually confirmed instead).
- Anything needing a real device: Increase Contrast rendering, and whether iOS extends "Retry"'s
  real tap region beyond its accessibility frame (both above).

## Gate 2 (PMO, 2026-10-09)
The Opus review (`pmo-audit/.build-audit/fp4/review/verdict.md`) found:
- **FIXED:** D07 (6.89–7.69:1 light, 10.01:1 dark, 20 sites) and D30 (no system blue in any sheet on 8/8 legs).
- **PARTIAL:** D10 and D12.
- **One S2 regression:** at AX5 the Paywall feature glyphs (43–65 pt) spilled out of the fixed 28 pt column onto their text and into the margin.

PMO fixes:
- the Paywall icon column now scales with the text (`@ScaledMetric(relativeTo: .body)`, 28 pt at the default size);
- "Retry" gets a 44 pt minimum width as well as height;
- the What-If sheet's section headers and footers (still the system grey, 3.30:1, though missing from D07's list) use `tallySectionText()`.

Noted, not changed (S3):
- the What-If chips' new 44 pt height makes them near-circles;
- the Paywall legal links sit further apart;
- onboarding still uses system blue (out of scope; next pass).
