# Significant-change decisions (EB-02(a)/(d))

One line per release that `scripts/ci/check_significant_change_notice.py` requires (its own
header documents exactly when): any release whose diff touches the `site/privacy/index.html`
`POLICY-FLOWS` block or `SubscriptionConfig.swift`'s product list needs an entry here, `yes` or
`no`, before its PR can pass the significant-change check. See
`docs/release/significant-change-checklist.md` for the full test.

| Commit | Date | Significant change? | Reason |
|---|---|---|---|
| _(template — delete this row)_ | YYYY-MM-DD | yes / no | One sentence citing which of checklist tests 1–4 applies. |

**NOTE (DOCS-5, 2026-10-25):** the privacy-page edits in PR #87, PR #90 and CLAIMS-1 (the Instructure disclaimer wording, the Terms/Privacy links, the calendar/Handoff/age-request/Erase additions, and the Family and school-search corrections) will need a **"no"** decision row here — checklist test 1 applies (wording only, no new data category) — but not yet: rows in this log are per release tag, by the checker's own design (`scripts/ci/check_significant_change_notice.py`), not per PR. Add the row at the first release tag that includes these commits.
