# Accessibility audit waivers

Owner: MVP-2 (Accessibility Engineer). Source of truth for `REL.a11y.audit`
(`.github/workflows/release-gate.yml`, `scripts/ci/check_release.py`) and the suite's own registry,
`A11yWaivers.waived` in `apps/TallyiOS/TallyUITests/AccessibilityAuditUITests.swift`. The two must
stay in sync: every row here is one `Key(elementIdentifier:auditType:)` entry there, and every entry
there has a row here. **No blanket filters** — a waiver matches one element identifier plus one
audit type exactly, never a whole audit type or a whole screen.

A waiver is appropriate only for a genuine false positive (a system-owned control Apple's own audit
flags on every app, or the documented "combined element vs its children" pattern) or an accepted,
reviewed system behaviour. A real accessibility defect gets fixed, not waived (see MVP-2's
report, `docs/pmo/reviews/mvp2-report.md`, for the fixes).

## Waiver table

| Screen | Element identifier | Audit type | Why it's a false positive / accepted behaviour | Evidence |
| :--- | :--- | :--- | :--- | :--- |
| _(none yet — `AccessibilityAuditUITests.swift`'s `A11yWaivers.waived` is empty)_ | | | | |

This table is empty by design until the first CI run of `AccessibilityAuditUITests` /
`-DarkUITests` / `-ContrastUITests` reports real issues (release-gate.yml's "Accessibility audit"
step, `ios-gate` job). Waiving ahead of evidence would be fabrication (CLAUDE.md's own invariant:
"never fabricate" — the same rule the PMO brief applies here). Rows land here, with the CI run ID
and the issue's `compactDescription` as evidence, only after that run.

## Open item: the existing `FamilyUITests` switcher filter

`FamilyUITests.testSwitcherPassesTheAccessibilityAudit` and
`testSwitcherAtAX5ShowsInitialsAndPassesTheAudit` (`apps/TallyiOS/TallyUITests/FamilyUITests.swift`)
each call:

```swift
try app.performAccessibilityAudit { issue in
    !Self.isFamilyElement(issue.element)
}
```

`isFamilyElement` matches identifiers that start with `family.`. Read literally, this waives every
issue whose element is **not** `family.`-prefixed — i.e. it is a scope restriction by element
*prefix*, not a waiver of a specific (element, audit type) pair. The method's own doc comment states
the intent: "only issues on the family's own elements count (the screens behind it have their own
suites)" — the switcher is a sheet over the Dashboard or Settings, and elements from the screen
behind it can still appear in the snapshot the audit walks; those screens already have their own
accessibility coverage (this suite's `testDashboard`/`testSettings`, going forward), so re-reporting
their issues here would be noise, not a missed defect.

That reasoning is plausible but **unverified**: this task could not run Xcode to see which specific
issues, if any, the filter is actually suppressing (this host has no Xcode; `FamilyUITests` was not
in this work package's CI budget — MVP-2's own flaky-test fix and new suite already used the
budget this round). Per the brief: narrow it, or justify it here. Justifying a predicate this broad
without the underlying issue list would itself be the kind of unverified claim rule 5
(`pmo-common-rules-v2.md`) forbids, so this is recorded as an **open item**, not waived:

- **Next step:** dispatch `AccessibilityAuditUITests` (or `FamilyUITests` alone) once with the
  filter changed to log every suppressed issue (`type`, element identifier, `compactDescription`)
  before deciding true/false, the same JSON-attachment pattern this suite's own `runA11yAudit` uses.
  Read the attachment, then either: replace the prefix filter with exact `(elementIdentifier,
  auditType)` entries in `A11yWaivers.waived` (and add them to the table above, with that run's ID
  as evidence), or confirm there is nothing to suppress and remove the filter outright.
- Not done in this PR: it touches a file outside this work package's new additions, and changing a
  currently-green test's behaviour without first observing what it is actually passing on would be
  guessing, not fixing.
