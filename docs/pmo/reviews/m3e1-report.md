# M3-E1 — Family Core report (FAM-08, FAM-14 data side)

Author: Family Core Engineer (work package M3-E1), Claude Sonnet 5. Branch `family/m3e1`.

**Status: hand-off.** FAM-08 (the parent notification planner and content builder) and FAM-14's
data side (a synthetic two-student observer, decoded through the production decoders, plus a
fetch harness that yields both students' `CanvasSnapshot`s) are built, tested and verified
locally. No UI: these are TallyCore types and TallyTestSupport fixtures for the family screens
(M3-E2, later) to stand on.

## 1. A correction before anything else (binding rule 8)

The brief's header states FAM-03 to 05 — "the endpoints, observer snapshots and sealed storage" —
are already built. Reading the actual code says otherwise for the "observer snapshots" part:

- `packages/TallyCore/Sources/TallyDomain/Model/CanvasSnapshot.swift:28-41` has no `subject` or
  observee field. No file anywhere composes one observer's data into several per-subject
  `CanvasSnapshot`s (the literal FAM-04).
- What **is** built and proven is the fixture/mapper layer only: `ObservedUserMapper`
  (`TallyCanvasAPI/Family/ObservedUserDTO.swift`), `ObserverAssignmentGroupMapper`
  (`TallyCanvasAPI/DTO/ObserverAssignmentGroupDTO.swift`), and the finding, already recorded in
  that file's own doc comment and proven by `TallyCanvasAPITests/ObserverMappingTests.swift`,
  that the plain `CourseMapper` already handles an observer's `/courses` response unchanged.
  Sealed per-subject storage (FAM-05, `purge(subject:)`, the `(accountKey, subjectKey, audience)`
  keyring scope from §6.3) does not exist either — nothing under `TallyStore` mentions a subject.

This is not a criticism of FAM-02/03/06/07, which genuinely are built and which this work package
reused directly and unmodified (`Subject`, `LinkedUsersUseCase`, `NewObserverDetector`,
`ObservedUserMapper`, `ObserverAssignmentGroupMapper`, `CourseMapper`). It means FAM-14's "a
provider that yields the 2 subject snapshots" could not be built on top of a multi-subject
gateway, because there isn't one. §3 explains the design that works around that honestly, within
this work package's own files.

## 2. FAM-08 — parent notification planner + content builder (R10a)

**New TallyCore types**, beside (not inside) `TallyDomain/Reminders`:

| File | What it is |
|---|---|
| `TallyDomain/Family/FamilyNotificationTypes.swift` | `PendingFamilyReminder` (per-subject, `threadIdentifier = subjectKey`), `FamilyNotificationKind`, `FamilyNotificationID.make` (`tally.<accountKey>.<subjectKey>.<kind>.<canvasID>.<ruleID>.<offset>`, §6.5), `FamilySubjectNotificationSettings` (F7(a) defaults: week-ahead + missing-still-open on, the rest off) |
| `TallyDomain/Family/FamilyNotificationMessage.swift` | The words-to-be. R10a, structurally: every case's payload is a student-name reference, a Canvas name, a date, a count or a flag — never a `Double`, never a dedicated grade-shaped `String` |
| `TallyDomain/Family/FamilyNotificationContentBuilder.swift` | Pure builders, one per kind, applying "Hide student names" structurally |
| `TallyDomain/Family/FamilySubjectBudget.swift` | §6.4's "weighted by due-item count, with a floor of 4 per subject" cap split (largest-remainder method, deterministic) |
| `TallyDomain/Family/FamilyNotificationPlanner.swift` | Schedules week-ahead, missing-still-open, the (off-by-default) 24h/1h due reminders, and event-fired grade-posted/below-goal, per subject, inside the shared budget |

**Shared-additive touches:**
- `TallyCore/Sources/TallyDomain/Config/TallyConfig.swift`: one new section,
  `familyNotificationFloorPerSubject = 4`, appended after FAM-06's existing "Family linking"
  section (same file, same pattern, nothing else changed).
- `TallyStrings/L10n+Family.swift` (new file — `L10n.swift` itself untouched) and
  `TallyStrings/Render/FamilyNotificationText.swift` (new file, mirrors `NotificationText.swift`).
- `Localizable.xcstrings`: 12 new `family.notification.*` keys, inserted as raw text at the
  correct alphabetical position so the diff is exactly those 12 entries (see §5).

**The privacy invariant, proved two ways** (`FamilyNotificationMessageTests.swift`):
1. **Structurally**, with the same `Mirror`-based leaf walker the student-side
   `NotificationMessageTests` already established for this exact property: every
   `FamilyNotificationMessage` case's payload, recursively, is only ever `String`/`Date`/`Int`/
   `Bool` — never a `Double`.
2. **Over every fixture/persona** (the FAM-08 acceptance line verbatim): for every assignment in
   every course in `flagship`, `flagship-previous`, `finals`, `grading-periods`, `empty`, `large`
   (via `GradeFixtures.courses(persona:)`) and in the new `sample-family` persona (via
   `SampleFamilyHarness`), every message the content builder can produce — names shown and
   hidden — is walked for its text leaves, and none ever equals that course's own current/final
   score, percentage or letter grade.

Both are Linux-checkable; rendering the English sentence itself needs `TallyStrings`, an
Xcode-built target this host cannot compile — exactly the student-side precedent's own scoping
(its doc comment: "What the Linux build proves is structural").

## 3. FAM-14 — sample-data family mode (data side)

**Fixtures** (`fixtures/canvas/personas/sample-family/`, `"synthetic": true`): one observer ("Dana
Sample"), two students ("Rowan Sample" / "Skyler Sample"), one host
(`canvas.sample-family.example` — one account, many subjects, R8a), disjoint courses per student.
Registered in `fixtures/canvas/manifest.json` as a new, single-host persona (additive: one new
key, nothing else in the file touched).

**Design note (ties to §1):** each student's courses come from Canvas's own per-observee
endpoint, `GET /api/v1/users/:observee_id/courses` (family-linking.md §2.5, VERIFIED docs/OSS) —
not the bulk, merged `/courses?include[]=observed_users` shape the `parent-observer` persona
uses. That bulk shape returns both students' courses in one array with no per-course subject id
on the decoded `Course` type to split them back apart (§1) — the per-observee endpoint sidesteps
that by having Canvas itself pre-scope each call, so each student's response decodes with the
**unmodified, already-shipped** `CourseMapper`. Assignment groups stay course-scoped exactly as
`parent-observer` already established, through the **unmodified** `ObserverAssignmentGroupMapper`.

**`TallyTestSupport/SampleFamilyHarness.swift`** (new file): fetches the observees list through
`LinkedUsersUseCase` (FAM-06), each student's courses through `CourseMapper`, each course's
assignment groups through `ObserverAssignmentGroupMapper` — all three calls are the production
decoders, none modified — and hand-assembles one `CanvasSnapshot` per student. Returns
`[SubjectSnapshot]` (`Subject` + display name + `CanvasSnapshot`).

**Proof:** `FamilyNotificationMessageTests.sampleFamilySnapshotsNeverLeakAScoreOrGrade` calls the
harness, asserts exactly 2 subjects come back with non-empty courses/assignments, and runs the
same privacy sweep as §2 over their real decoded data.

## 4. Tests and local verification

| Check | Result |
|---|---|
| `make core-build` | Clean, 0 warnings (ran twice, after FAM-08 and again after FAM-14) |
| `make core-test` | **349 tests / 43 suites** (`TallyDomainTests`) + **195 tests / 26 suites** (`TallyCanvasAPITests`) pass. 4 pre-existing `GradeParityTests` "known issues", unrelated to this work (present before my changes too) |
| `make core-tsan` | `TallyCanvasAPITests`: exit 0 (plain `make core-tsan`'s own output). `TallyDomainTests`: exit 0, 349/43, same 4 known issues — re-run directly with `--filter TallyDomainTests` since the Makefile target's captured output only showed the other suite |
| `make lint` | **0 violations, 0 serious**, 227 files, including all 7 new shipping Swift files |
| `python3 scripts/ci/check_string_catalogs.py` | `PASS | 4 catalogs, 286 keys, shipping ['en'] | 0 problems` |
| `python3 scripts/ci/check_localizable_literals.py` | `PASS | 161 Swift files, 210 literals in 20 files, baseline 210 in 20 files` (unchanged) |

New test files: `TallyCore/Tests/TallyDomainTests/FamilyNotificationMessageTests.swift`,
`TallyCore/Tests/TallyDomainTests/FamilyNotificationPlannerTests.swift`.

Two real bugs the tests caught on first run (both fixed, not weakened away — see the journal for
the exact assertions and reasoning): the budget test's wrong assumption about which subject the
largest-remainder method favours, and a planner `>` vs. `>=` off-by-one that silently dropped
every event-fired (grade-posted/below-goal) reminder. Both now pass with the correct behaviour,
not a loosened test.

## 5. Mutation checks

1. **Privacy filter** — added a `Double` to `FamilyNotificationMessage.gradePosted`, threaded a
   dummy score through the content builder. `make core-test`: `noCaseCarriesAScoreOrGradePayload`
   failed (4 issues, exactly the expected assertions). Reverted; `sha256` of all three touched
   files matches the pre-mutation record exactly.
2. **Fixture decode** — renamed `sample-family/observees.json`'s first `"id"` key. `make
   core-test`: `sampleFamilySnapshotsNeverLeakAScoreOrGrade` failed with `.network(.contract)`
   (the decode-failure path). Reverted; `sha256` matches exactly.
3. **Repeated-subject crash guard** (added after a PMO crash-safety review of this PR; see §5a) —
   removed the new de-duplication call and reverted one `Dictionary(_:uniquingKeysWith:)` back to
   `Dictionary(uniqueKeysWithValues:)`. Running the new test directly **crashed the process**
   (exit 1, full backtrace): `Swift/NativeDictionary.swift:823: Fatal error: Duplicate values for
   key: 'a'` — the same signature `crash-safety-2.md` §8 documents for the six earlier sites.
   Reverted; `sha256` matches exactly.

Full `make core-test` after all restores: clean, same counts as §4.

## 5a. PMO crash-safety review (post-open, before the first PR run completed)

While `36942145121` was still queued, a PMO review found `FamilySubjectBudget.swift` building
three dictionaries with `Dictionary(uniqueKeysWithValues:)` (traps on a duplicate key) and
`FamilyNotificationPlanner.swift`'s `weights` built from the caller's `subjects` with no
de-duplication — the same student appearing twice in an observee list would crash the app.
**Verified independently before acting** (treating the finding as a hypothesis, per rule 8, not
as a command): all three call sites and the missing de-duplication were confirmed by reading the
files directly; `docs/pmo/reviews/crash-safety-2.md` §8 documents the identical historical
pattern (six sites, same trap, all already removed from shipping code, same fix); PR #24 (real,
open, authored by the repo owner) adds the `no_unique_keys_with_values` SwiftLint rule exactly as
described.

**Fix** (`FamilyNotificationPlanner.swift`, `FamilySubjectBudget.swift`): `plan` now
de-duplicates `subjects` by `subjectID` (keeping the first) before building `weights` or
planning; `allocate` does the same for its own `weights`, so the public API is safe to call
directly too; all three `uniqueKeysWithValues` sites now use
`uniquingKeysWith: { first, _ in first }`. New tests:
`aRepeatedSubjectDoesNotTrapAndMatchesTheDeduplicatedSplit` and
`aRepeatedSubjectIsPlannedOnceAndNeverTraps`. Verified exactly as §4/§5 (`make core-build`,
`make core-test` — 359/44 + 195/26 — `make core-tsan`, `make lint`, all clean); mutation check in
§5 item 3. Committed and pushed once, superseding the still-queued run as anticipated.

## 6. CI

- **`-f scope=unit` run (before the PR, to de-risk the Xcode-only `TallyStrings` change before
  spending the PR's one full run on it): [36939035354](https://github.com/rahart1362/Tally/actions/runs/36939035354), all ran jobs green:**

  | Job | Result |
  |---|---|
  | TallyCore sanitizers (TSan + ASan/LSan, Linux) | ✓ 10m20s |
  | Crash-safety lint (SwiftLint 0.59.1, pinned) | ✓ 20s |
  | TallyCore perf gates (Linux, release, non-blocking) | ✓ 4m10s |
  | iOS build + test (Xcode 26.6) | ✓ 16m35s |
  | TallyCore tests (Linux, Swift 6.4) | ✓ 2m30s |
  | Hygiene gates | ✓ 12s |

  The 6 jobs `scope=unit` doesn't run (ios-perf, ios-asan ×2, ios-tsan, Xcode 27 forward-compat,
  Apple-silicon perf) correctly show skipped (0s) — those are `scope=full`/PR-only. One
  pre-existing, non-blocking annotation ("Go-live placeholders remain") is expected before
  go-live (`docs/GO-LIVE.md` GL-02) and unrelated to this change.
  - This confirms, independently of this host's own `make core-tsan`/`make lint` runs, that
    `TallyStrings/L10n+Family.swift` and `TallyStrings/Render/FamilyNotificationText.swift`
    compile correctly under real Xcode, and that the hand-edited `Localizable.xcstrings` is
    well-formed to Xcode's own String Catalog compiler, not just to
    `check_string_catalogs.py`.
  - CI budget used: 1 of 3 permitted iteration runs; 0 of 1 mutation runs (both of this work
    package's mutation checks were TallyCore-only and run locally, per rule 4).
- **PR run:** <!-- filled in after `gh pr create`; see the hand-off reply for the final numbers -->

## 7. Files touched

**Mine (new):**
- `packages/TallyCore/Sources/TallyDomain/Family/{FamilyNotificationTypes,FamilyNotificationMessage,FamilyNotificationContentBuilder,FamilySubjectBudget,FamilyNotificationPlanner}.swift`
- `packages/TallyCore/Sources/TallyTestSupport/SampleFamilyHarness.swift`
- `packages/TallyCore/Tests/TallyDomainTests/{FamilyNotificationMessageTests,FamilyNotificationPlannerTests}.swift`
- `fixtures/canvas/personas/sample-family/**`
- `packages/TallyAppleKit/Sources/TallyStrings/L10n+Family.swift`
- `packages/TallyAppleKit/Sources/TallyStrings/Render/FamilyNotificationText.swift`
- `build/logs/journal/2026-10-01-m3e1.md`, this report

**Shared, additive only (small, described above, nothing else in each file changed):**
- `packages/TallyCore/Sources/TallyDomain/Config/TallyConfig.swift` (+4 lines)
- `packages/TallyAppleKit/Sources/TallyStrings/Resources/Localizable.xcstrings` (+12 keys)
- `fixtures/canvas/manifest.json` (+1 persona entry)

**Not touched:** `TallyDomain/Reminders/*` (not in my file list — a new, parallel type family was
built instead, per the brief's own "beside the existing reminder planner's design"); anything
under `TallyCanvasAPI/DTO` or `TallyCanvasAPI/Client` (the FAM-04 gap in §1 is real, but fixing it
would mean editing files this brief does not list for me); `TallySampleFixtures`/
`TallyFeatures/SampleData/*` (M3-E2's files, see §8); `.github/workflows/ci.yml` (the hygiene
job already runs both string/literal scripts; nothing needed adding).

## 8. Open items

1. **FAM-04 is not built** (§1). Whoever eventually owns it should start from "nothing exists",
   not from the brief's "already built" summary.
2. **Wiring `sample-family` into the shipping "Explore with Sample Data" feature is M3-E2's job.**
   `SampleFamilyHarness` lives in `TallyTestSupport` (a test-only target) by design — correct for
   proving the fixtures and decoders, not shippable as-is. M3-E2 will need a small production-side
   equivalent (or to call the same fixtures/mappers from `TallySampleFixtures`/
   `TallyFeatures/SampleData/SampleDataGateway.swift`, neither of which is in this brief's file
   list). The data and the decode path are proven and ready for that.
3. **`ios-build`/`ios-asan`/`ios-tsan`/`ios-perf` are UNVERIFIED by me** — this host has no Xcode.
   The PR's own run is where `TallyStrings`/`Localizable.xcstrings` actually compile for the
   first time. Any failure there in my files is mine to fix; see §6 for the run's result.
4. The 24h/1h "due reminder" kind and the event-fired "grade posted"/"below goal" kinds are off by
   default (F7(a)) and have no real upstream signal-computation yet (newly-graded-course and
   below-goal-course detection is, like `ReminderCandidate.isExam`, left to whoever calls the
   planner — see `FamilySubjectPlanInput`'s doc comment). Not a gap in this work package: FAM-08's
   brief is the planner and content builder, not the refresh-time diffing that would feed them.
