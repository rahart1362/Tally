# Tally — Specialist Team Charter (Assessment Phase)

PMO Lead coordinates. Each specialist produces **one report** at `docs/pmo/reviews/<role>.md`. Assessment phase is **read-only on source code** — do not modify anything outside your own report file (a UX prototype under `docs/pmo/ux/` is the one exception, UX lead only).

## Required reading (in order)
1. `docs/pmo/00-baseline-audit.md` — verified state of the repo. Do not re-derive it; build on it.
2. Every file in `Tally_Antigravity_Build_Kit_Scaffold/` (00–14, plus `assets/*.png` for UX).
3. The source files relevant to your lane under `packages/` and `apps/`.

## Ground rules
- **Never fabricate.** Every finding cites evidence: `path:line` for code, a URL for external facts. Today is 2026-09-26; your training data may be stale. Verify Apple / Instructure / Microsoft / Google requirements with WebSearch + WebFetch (load them via ToolSearch `select:WebSearch,WebFetch` if not already available). If you could not verify something, label it **UNVERIFIED**.
- Stay in your lane. If you spot something in another lane, add one line under "Cross-lane notes" — don't deep-dive.
- The product owner is **not wedded to the kit's architecture**. Recommend what is best for a commercial, App-Store-ready iOS app, and say what it replaces.
- The owner's non-negotiables stand unless you show they are infeasible — in which case present the conflict as a decision, with options and a recommendation.
- Commercial bar: bug-free on the App Store, passes App Review first time, and would survive TestFlight external beta.

## Report template (use these exact headings)
```
# <Role> Review — Tally
## 1. Executive summary          (≤6 bullets, most severe first)
## 2. Findings                    (table: ID | Severity [Blocker/Critical/Major/Minor] | Evidence | Impact)
## 3. Target design               (what we should build; concrete enough to implement from)
## 4. Decisions for the product owner   (each: question, options, recommendation, consequence of each)
## 5. Work packages               (table: WP-ID | Title | Depends on | Acceptance criteria | How verified [Linux swift container / macOS CI simulator / device-only])
## 6. Cross-lane notes
## 7. Sources                     (URL + what it established + VERIFIED/UNVERIFIED)
```
Work packages should be small enough for an atomic, reviewable diff (target <300 lines each) and must name how they will be verified given: Linux dev host with Podman (Swift-on-Linux container can compile/test code that avoids UIKit/SwiftUI/Apple-only frameworks) + GitHub Actions macOS runners (public repo) for Xcode builds, iOS Simulator tests and XCUITest screenshots.

When done, reply to the PMO with: the report path, your top 3 findings, and the decisions you need from the owner. Keep that reply under 250 words — the report holds the detail.
