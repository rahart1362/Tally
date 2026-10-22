# FEAT-7 — Handoff to Mac/iPad browser from an assignment (Idea 9)

Author: Feature Engineer (work package FEAT-7), Claude Sonnet 5. Branch `feat/handoff`, from
`origin/main` @ `16befa5`. Owner approval: 2026-10-21 ("the plan update approves low-to-medium-cost
enhancements"). This host has no Xcode; every iOS-hosted claim below is backed by the CI runs
listed, not by local execution.

**No new user-facing strings** (scope: "Zero new strings."): `check_localizable_literals.py` and
`check_string_catalogs.py` both PASS with unchanged counts (6 catalogs, 760 keys) — no catalog or
string file is touched by this change at all. **Copy for owner approval: none — 0 new keys.**

## Source of truth, re-verified on this branch (rule 8)

`pmo-audit/.build-audit/ideas1/report.md` §"Idea 9 — Handoff to Mac/iPad browser from an
assignment": "No `NSUserActivity`/Handoff code exists anywhere (grep confirmed). The web URL
Handoff would need is already computed for 'Open in Canvas' (`CanvasLink`/
`CanvasLinkOpener.swift`)." Re-grepped on this branch: confirmed, zero `NSUserActivity` hits
before this change. `CanvasLinkOpener.isSafe` (`packages/TallyAppleKit/Sources/TallyFeatures/
CourseDetail/CanvasLinkOpener.swift:25-33`) reuses `PageURLPolicy.validate`
(`packages/TallyCore/Sources/TallyCanvasAPI/HTTP/Pagination.swift:46`), the same host policy the
network layer applies before attaching a bearer token — matching the report exactly.

**Scope note (not a deviation):** two existing call sites build a validated Canvas URL today —
`CourseDetailView.swift:93-106` (the course's `htmlURL`) and `ToDoScreen.swift:125-139` (a swipe
action, per assignment). The ToDo screen shows many assignments at once with no single "current"
item, so it is not a fit for Handoff's one-record-at-a-time model; no single-assignment detail
screen exists in this codebase. Handoff is attached to `CourseDetailView`, the one pushed,
single-record screen, re-using the exact URL and `accountHost` its "Open in Canvas" toolbar
button already validates.

## What changed

| Change | File:line | Verified by |
| --- | --- | --- |
| `CanvasHandoffActivity` (new, pure `nonisolated enum`, the `CanvasLink` pattern): `activityType`, `webpageURL(for:accountHost:isSampleData:)`, `configure(_:webpageURL:)` | `packages/TallyAppleKit/Sources/TallyFeatures/CourseDetail/CanvasHandoffActivity.swift` (new) | `CanvasHandoffActivityTests` (6 cases) + mutation check below |
| `.userActivity(CanvasHandoffActivity.activityType, element: ...) { ... }` wired onto the screen's `body` | `CourseDetail/CourseDetailView.swift:51-61` | Same tests (pure function) + CI compile |

## Invalidation — mechanism, not an imperative call

`.userActivity(_:element:_:)` retires a previously published activity once its element goes
`nil`. No `.invalidate()` call was written; two existing paths cover the two required cases:
1. **Sample mode**: `webpageURL(...)` returns `nil` whenever `isSampleData`, unconditionally —
   the sample fixtures use a realistic-looking host (`canvas.northfield.example`) that would
   otherwise pass `isSafe`, so this guard is load-bearing, confirmed by the mutation check below.
2. **Sign-out**: `AppModel.signOut()`'s first step sets `route = .welcome`
   (`Shell/AppModel.swift:528-539`) — `CourseDetailView` only exists under `.signedIn`, so the
   view and its `.userActivity` modifier are torn down synchronously, before the async purge even
   starts.

## Mutation check (pmo-common-rules-v2 rule 5)

| Step | Evidence |
| --- | --- |
| sha256 recorded before mutating | `.build-feat7/pre-mutation.sha256` (local, not committed) |
| Mutation: dropped `!isSampleData` guard, commit `b3f9ef0` | — |
| `scope=only` run, mutated | [39641265278](https://github.com/rahart1362/Tally/actions/runs/39641265278) — **failure**: exactly `neverOfferedForSampleData` failed, 5/6 passed |
| Restore, byte-identical to `12b2c9e`, commit `40a98b5` | sha256 matched `.build-feat7/pre-mutation.sha256` exactly |
| `scope=only` run, restored | [39643645404](https://github.com/rahart1362/Tally/actions/runs/39643645404) — **success**: `totalTestCount=6, passedTests=6, failedTests=0` |

## Local verification

- `python3 scripts/ci/check_view_bodies.py .` → `view bodies: clean`.
- `python3 scripts/ci/check_localizable_literals.py .` → `PASS, 0 literals` (unchanged).
- `python3 scripts/ci/check_string_catalogs.py .` → `PASS, 6 catalogs, 760 keys, 0 problems`.
- `python3 scripts/ci/check_debug_only_test_symbols.py .` → `PASS, 0 problems`.
- `make lint` (podman, `.swiftlint-crash-safety.yml`) → **0 violations, 0 serious in 290 files**.
- Diff grepped directly for `try!`/`as!`/`fatalError`/`precondition(`: none.

## CI budget used

2 of 2 `scope=only` runs (both spent on the mutation check table above). `scope=a11y` and the
Audit tour were **not dispatched**: this change adds no visible control or screen — Handoff has
no UI surface — so neither the a11y gate nor "no tour needed unless a screen changes visibly"
applies.

## Quality bar (HANDOFF §4b / brief scope)

No new control, label or screen: nothing to check at AX5/xxxLarge, Light/Dark/Increase Contrast,
or with VoiceOver, because nothing new is drawn. The feature is a background `NSUserActivity`
only. "Synthetic sample data only; nothing new leaves the device" holds: `webpageURL` is set to
the same Canvas URL "Open in Canvas" already sends to `UIApplication.open`, gated identically by
`CanvasLinkOpener.isSafe` and the account's own host.

## Open items

- None blocking. The PR run (`ios-build`, `ios-asan`, `ios-tsan`, `ios-perf`, etc.) is the
  remaining full verification; its results are in the PR, not repeated here.
- Device-level confirmation that Handoff actually offers the continuation in Safari on a real
  Mac/iPad (requires physical hardware with the same iCloud account, Handoff enabled, and
  Bluetooth/Wi-Fi proximity) is **UNVERIFIED** — outside what CI's simulator can exercise. The
  unit tests pin the URL rule and the no-Handoff conditions, per the brief's explicit instruction
  ("Unit-test the URL and the invalidation"); no UI smoke test was added, since there is no new UI
  surface to smoke-test.
