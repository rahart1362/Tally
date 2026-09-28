# Performance & Crash-Safety Team Charter (owner-requested, 2026-09-27)

**Owner's mandate:** "Ensure memory, storage, data rehydration/loading is as efficient as possible … directly ensure the core of this app will not crash or have any performance issues." The findings are integrated into the app-core team's **next** iteration, which is paused until the PMO sends the integration plan.

## Trigger
`m2/app-core`'s sample-data UI test has failed for 12+ CI runs. Bisect evidence:
- A trivial destination navigates fine.
- Rendering the real Dashboard hangs the app: the pushed screen never appears, and the next test cannot even launch the app.

PMO code review found two main-actor hotspots:
1. `SampleDataRootView`'s `.task { load() }` synchronously builds `SampleDataCanvasGateway`, which runs bundled fixture decode and rebase on the main actor.
2. `DashboardView.body` calls `DashboardBuilder.build(...)`, the full PriorityScore/AlertEngine pipeline, on the main actor and on every body evaluation.

`DashboardBuilder` lives in iOS-only TallyFeatures, so it cannot be tested or benchmarked on Linux.

## Budgets (source → value)
| Budget | Value | Source |
|---|---|---|
| Warm start to first painted frame | ≤ 300 ms on device | kit 01 §8, `TallyConfig.warmStartBudget` |
| Snapshot decode | ≤ 100 ms on the oldest supported device | architecture §3.2, `snapshotDecodeBudget` |
| Snapshot size | ≤ 5 MB | architecture §3.2, `snapshotSizeBudgetBytes` |
| Background refresh total | ≤ 25 s, including network | `backgroundBudget` |
| Live refresh before the stale breadcrumb | 10 s | `liveRefreshBudget` |
| Main thread | No synchronous main-actor work ≥ 50 ms anywhere in launch, load or render paths. Apple counts ≥ 250 ms unresponsiveness as a hang; we stay far below that. | PMO |
| Widget extension | Must never decode the full snapshot; reads the glance only (architecture §3.1). Respect the extension memory limit (UNVERIFIED value; verify). | architecture §3.1 |

CI proxies: Linux x86 **release** builds are faster than the oldest iPhone. Each perf gate must state its device-to-CI factor and its safety margin.

## Data scales to test
- The `flagship` persona: 5 courses.
- The `large` persona: 12 courses, 153 assignments.
- A synthetic **stress** account generated in-test: ≥ 20 courses × 250 assignments with submissions, drop rules, grading periods and a full year of planner items. It is not a fixture file.
- Scaling check: 10× the data must cost about 10× the time, never superlinear.

## Rules
- Follow `docs/pmo/03-implementation-brief.md`: evidence, not claims; mutation checks for every new gate or guard; commit each work package once verified; never touch another team's worktree or the PMO checkout (`/home/rahart1362/Documents/Tally`). Reading `/home/rahart1362/Documents/Tally-worktrees/m2-perf-review` (the pinned app-core code) is allowed; it is read-only.
- **Do not edit `.github/workflows/ci.yml`.** Provide `Makefile` targets. The PMO wires CI.
- Performance claims need before/after numbers from `-c release` runs, median of ≥ 5 iterations.
- Crash claims need a reproducing test.
