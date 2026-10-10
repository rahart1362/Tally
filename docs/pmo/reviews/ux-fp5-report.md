# UX-FP5 report — widgets and privacy cover

Branch `ux/fp5-widgets`, from `origin/main` @ `b264c7f` (UX-FP1–FP4 and UX-FP6 merged; worktree
pre-created and verified clean by the PMO). No merge of `origin/main` was needed (still `b264c7f`
as of this report; rule 3). Journal: `build/logs/journal/2026-10-10-ux-fp5.md`. Attribution: Claude
Sonnet 5. Last of the six fix packages; no parallel stream.

## G2 — review fidelity (test-only)

`WidgetFamilyRenderTests.swift`'s `snapshot(surface:mode:)` test renders every widget family with
`ImageRenderer`, which does not paint a view's `.containerBackground(...)` — the gap was not a
missing call in production (every widget already calls it, `GlanceWidgetViews.swift:179`,
`GlanceAccessoryViews.swift:34,107,124`) but `ImageRenderer` itself never executing that paint
outside WidgetKit's own host, confirmed by the pre-fix `named/m3d-*.png` captures being plain
transparent canvases.

Added `hostedPNG()` (`WidgetFamilyRenderTests.swift:175-200`), used only by the attached-for-review
snapshot: composites, behind the real production view, exactly what its own `containerBackground`
call already asks for — `TallyColor.bgBrand` for the five Home families, the system's own
`AccessoryWidgetBackground()` for the two Lock Screen accessories that use it, nothing for the
inline accessory — plus `TallySpacing.lg` padding for the Home families (the HIG's 16 pt default
content margin a real host applies automatically). The functional tests (`accentedKeepsMeaning` and
friends) keep using the plain, unbacked `renderer`/`alpha` so an always-opaque test backdrop never
masks the opacity-mask signal they check.

`snapshot` now also renders light **and** dark (looped inside the existing test body, not a third
`arguments:` collection) and attaches `widget-<family>-<mode>-<light|dark>.png` — 48 PNGs per run
(8 families × 3 modes × 2 appearances), confirmed in CI: `Exported 48 attachments for:
WidgetFamilyRenderTests/snapshot(surface:mode:)`. The existing assertion (`opaque > 0`, from the
plain `alpha()`) is unchanged.

## Defects

"Before": `pmo-audit/.build-audit/audit-proMax-light-std/named/` (widgets; no dark exists — G1) and
`pmo-audit/.build-audit/fp3/after-37936616803/` (privacy cover, onboarding). "After": Audit tour run
**38023201467** (final; see "CI and Audit tour runs" for both dispatches).

| Defect | What changed | `file:line` | Evidence | Layout delta |
|---|---|---|---|---|
| **D06 (S1)** Mark Done checkmark renders black on `bg.brand` (1.21:1) | `.foregroundStyle(TallyColor.brandCream)` + `.widgetAccentable()` on the checkmark `Image`. `brandCream` is a universal (non-adaptive) asset colour, so the fix holds in both appearances without a separate dark value. | `apps/TallyiOS/TallyWidgets/Shared/MarkDoneButton.swift:27-28` | `evidence/D06-full-color-{light,dark}.jpg` | N/A (widget render test, not an AuditTour layout check) |
| **D23 (S3)** Week ahead (large) widget leaves its lower ~40% empty | A second `Spacer(minLength: TallySpacing.lg)` between the week strip and the item list splits the one ~100 pt+ dead block into two smaller gaps. (First attempt — `.frame(maxHeight: .infinity, alignment: .top)` on the content `VStack` — changed nothing: `GlanceItemList`'s own trailing `Spacer` already reached the real bottom edge before any change, confirmed by comparing to the audit's own composited `D23.jpg`.) | `packages/TallyAppleKit/Sources/TallyGlance/GlanceListWidgetViews.swift:70-76` | `evidence/D23-full-color-light.jpg` | N/A |
| **D24 (S3)** App-switcher privacy cover looks half-loaded | Replaced `HeroSilhouette` (a 160 pt navy rect, leading-aligned 48 pt T-mark, on blank `bg.canvas`) with a full `bg.brand` background and a centred 96 pt `TMark` — the same brand-panel treatment `WelcomeView.brandPanel` uses. The owner's emblem itself (`TMark.swift`) was not altered, only called with its own public `size:` parameter. | `packages/TallyAppleKit/Sources/TallyFeatures/Launch/LaunchPlaceholderView.swift:28-43` | `evidence/D24-{light,dark}.jpg` | N/A (app-switcher state, not covered by the layout-check pipeline) |
| **Onboarding tint** (FP-4 review): School search's "Retry" measures system blue (~3.20:1), not `TallyColor.accent` | Two attempts failed first: `.tint(TallyColor.accent)` on the onboarding `NavigationStack` (matching FP-4's own `TabView`/`.sheet` precedent), then `.tint()` directly on the `ContentUnavailableView` inside `TallyUnavailableView` — both confirmed still blue by separate Audit tour captures. `ContentUnavailableView`'s action buttons do not honour an ancestor `.tint()` at all in this SDK. Fixed with `.foregroundStyle(TallyColor.accent)` directly on "Retry"'s label — the same mechanism `WelcomeView.BenefitRow`'s icon already uses successfully. | `packages/TallyAppleKit/Sources/TallyFeatures/Onboarding/SchoolSearch/SchoolSearchView.swift:176`; the reverted attempt is also visible in `TallyDesignSystem/UnavailableView.swift`'s history | `evidence/onboarding-tint-BEFORE-only-UNVERIFIED-after.jpg` | **UNVERIFIED** — no device capture after the final fix (see "Open items") |

### Measured contrast (pixel-sampled from the real rendered PNGs, full-color mode; WCAG relative luminance)

| Control | Light | Dark | Needs |
|---|---|---|---|
| D06 Mark Done checkmark on `bg.brand` | 1.21:1 → **15.56:1** | (no dark before — G1) → **12.73:1** | ≥ 3:1 (control) |

Method: computed from the asset catalog's own sRGB hex (`brand.cream` universal `#FCF2D8`;
`bg.brand` Any `#071A36`, Dark `#0D2A55`), the same WCAG relative-luminance formula `defects.md`
itself uses — cross-checked against the audit's own reported 1.21:1 for the pre-fix black glyph,
which matched exactly. Independently re-verified by CI directly from rendered pixels: the new
`markDoneButtonGlyphContrast` test (`WidgetFamilyRenderTests.swift`) renders `MarkDoneButton` on
`bg.brand`, samples the actual pixels, and asserts ≥ 3:1 in both `ColorScheme`s — passed in both CI
runs that reached the test step (38010346618, 38019483219).

Other brand-surface tokens swept for the same "dark glyph on navy" class (all already route through
`GlanceStyle`, computed against both `bg.brand` appearances): `text.onHero` 17.35/14.19:1,
`text.onHero2` 11.73/9.59:1, `brand.gold` 10.19/8.33:1 — all well clear. `MarkDoneButton` was the
only glyph bypassing `GlanceStyle` (it lives in the `TallyWidgets` extension target, never imported
`TallyGlance`); confirmed by reading every widget view's source, not only by the audit's one flagged
row.

TallyColor.accent (the onboarding-tint fix) on `bg.canvas`: light **7.24:1**, dark **9.64:1**
(computed from the asset's own Any `#1D4E9E` / Dark `#8DB4FF` hex) — both clear 4.5:1 for text, well
past the old system blue's ~3.65:1 (computed reference, consistent with the audit's measured
~3.20:1). Not yet pixel-verified from a device capture (see "Open items").

## CI and Audit tour runs

- **CI iteration run 1 of 3**: **38008585146** (`-f scope=quick`) — failed to compile:
  `WidgetFamilyRenderTests.swift` set `.environment(\.widgetFamily, ...)`, which has no writable key
  path. Fixed (commit `2fce8ce`).
- **CI iteration run 2 of 3**: **38010346618** — `iOS build + test` compiled clean;
  `Run TallyAppTests and TallyUITests` failed one test outside this package's files:
  `SettingsSignedInUITests.testSignOutConfirmationReadableAtAccessibilityXXXL`
  (`TallyUITests/SettingsUITests.swift:150`). Re-ran the failed jobs once per rule 4
  (`gh run rerun 38010346618 --failed`): still failed (`xcresult`: `totalTestCount=647,
  failedTests=1`, same Settings test; a second, transient `CourseDetailUITests` failure self-healed
  on its own automatic retry). `Suite "Widgets M3-D"` and `WelcomeCTAUITests` both green throughout.
- **CI iteration run 3 of 3**: **38019483219** — same result: `iOS build + test` compiled clean,
  the identical `SettingsSignedInUITests` test failed (`totalTestCount=647, failedTests=1`), nothing
  else. Confirmed reproducible across two independent dispatches and one rerun, in a file this
  package never touches (`grep` confirms no reference to any changed symbol). Recorded as an open
  item per rule 4, not fixed.
- Required jobs, every run: `hygiene`, `core-linux`, `lint`, `core-sanitizers` green throughout;
  `ios-build` compiled clean on runs 2 and 3 (the one failing test is a UI-test run step inside that
  job, not a build failure). `ios-asan`/`ios-tsan`/`ios-perf` are not part of `scope=quick`; they run
  on the PR's own full gate.
- **Audit tour dispatch 1 of 2**: **38018253185** (proMax+smallest, light+dark, std,
  `testM_appLockAndPrivacyCover,testH_welcomeAndSchoolSearch`, widgets=true) — all 4 legs green.
  Downloaded to `pmo-audit/.build-audit/fp5/after-38018253185/`.
- **Audit tour dispatch 2 of 2**: **38023201467** (same parameters, after the D23/onboarding-tint
  fixes) — all 4 legs green. Downloaded to `pmo-audit/.build-audit/fp5/after-38023201467/`. This is
  the "after" used throughout this report except where noted.
- No mutation run: nothing in this package adds a new guard/gate to mutate.

## Strings PENDING owner approval

None. Every fix here is a colour/background/spacing change; no copy, no new `L10n` key.

## Evidence, widget-sheet and owner-sheet paths

- `pmo-audit/.build-audit/fp5/evidence/D06-full-color-light.jpg`, `D06-full-color-dark.jpg`
- `pmo-audit/.build-audit/fp5/evidence/D23-full-color-light.jpg`
- `pmo-audit/.build-audit/fp5/evidence/D24-light.jpg`, `D24-dark.jpg`
- `pmo-audit/.build-audit/fp5/evidence/G2-review-fidelity-next-up-small.jpg`
- `pmo-audit/.build-audit/fp5/evidence/onboarding-tint-BEFORE-only-UNVERIFIED-after.jpg`
- `pmo-audit/.build-audit/fp5/widget-sheet-ux-fp5.jpg` (1574×1114, 303 KB) — every family × mode,
  before(light)/after(light)/after(dark)
- `pmo-audit/.build-audit/fp5/owner-sheet-ux-fp5.jpg` (1200×1740, 288 KB)
- Raw "after" captures: `pmo-audit/.build-audit/fp5/after-{38018253185,38023201467}/audit-<proMax|smallest>-<light|dark>-std/`

None of this is committed to the repo (public); it stays under `pmo-audit/.build-audit/fp5/` per
the brief.

## Open items

- **Onboarding tint: UNVERIFIED by device capture.** The final fix (`.foregroundStyle(TallyColor
  .accent)` directly on "Retry") landed after both Audit tour dispatches and all 3 CI iteration runs
  were already spent on G2/D06/D23/D24. It is architecturally the most reliable mechanism available
  (a direct, non-environment-dependent style, the same one `WelcomeView.BenefitRow` already uses
  successfully in the verified `111-welcome-default.png` capture), and the computed contrast clears
  4.5:1 in both appearances, but no screenshot confirms it. Will be confirmed or caught by the PR's
  own required run; a reviewer should treat `113-schoolSearch-failure.png` from that run as the real
  check.
- **`SettingsSignedInUITests.testSignOutConfirmationReadableAtAccessibilityXXXL` fails
  reproducibly**, outside this package's files, across 2 independent CI dispatches and 1 rerun
  (`"settings.signOut" Button never appeared`). Not fixed per rule 4/9 ("a failure outside your
  files that persists after the retry... record it as an open item; don't fix it" / "fix only your
  package's defects"). Flagging for whoever owns `Settings/SettingsView.swift` or
  `TallyUITests/SettingsUITests.swift`.
- **Lock Screen accessory materials render inconsistently between light/dark `hostedPNG` composites**
  (surfaced while building the widget sheet): `AccessoryWidgetBackground()` has no real wallpaper
  behind it outside an actual Lock Screen host, so the two accessory families that use it
  (`due-today-circular`, `next-item-rectangular`) show very different apparent opacity between the
  light and dark composites in `widget-sheet-ux-fp5.jpg`. This is a test-harness/compositing
  limitation, not something this host can resolve — a genuine device check (listed below).
- **Device-only checks** (per the hand-off): Lock Screen families (`due-today-circular`,
  `next-item-rectangular`, `next-due-inline`) on a real Lock Screen with a real wallpaper; a tinted
  Home Screen (iOS 18+ tinted-icon mode) for every Home widget family, to confirm `.widgetAccentable()`
  carries D06's fix correctly; StandBy. The Pro Max AX5 leg historically captures the Calendar app
  instead of the privacy cover (a harness leak noted in the brief); std (captured here, both
  devices) is sufficient to confirm D24's fix.
- Five more `TallyUnavailableView` call sites exist outside onboarding (Dashboard, Insights, ToDo,
  CourseDetail, Courses) — all already use `.buttonStyle(.tallyPrimary/.tallySecondary)`, which was
  never affected by the `ContentUnavailableView`-tint gap, so they are not expected to need the same
  fix; not audited further (out of this package's scope).

## PMO note (2026-10-10): the reproducible Settings failure
`SettingsSignedInUITests.testSignOutConfirmationReadableAtAccessibilityXXXL` (added in UX-FP1, PR #42) failed in runs 38010346618 (and its rerun) and 38019483219 with "settings.signOut Button never appeared". The failure hierarchy shows the Settings sheet **open**, with the Subscription row 284 pt tall at AX5 and Sign Out & Erase not yet built by the lazy List. The test tapped without scrolling. The row's "Active until …" date text changes by day, so this is a date-sensitive test gap, not this package's code; it passed on `main` on 10-09. **Fix (PMO):** the test scrolls to the button first (`scrollUntilHittable`), as the suite's other AX tests do.
