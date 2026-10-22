# Significant-change decisions (EB-02(a)/(d))

One line per release that `scripts/ci/check_significant_change_notice.py` requires (its own
header documents exactly when): any release whose diff touches the `site/privacy/index.html`
`POLICY-FLOWS` block or `SubscriptionConfig.swift`'s product list needs an entry here, `yes` or
`no`, before its PR can pass the significant-change check. See
`docs/release/significant-change-checklist.md` for the full test.

| Commit | Date | Significant change? | Reason |
|---|---|---|---|
| _(template — delete this row)_ | YYYY-MM-DD | yes / no | One sentence citing which of checklist tests 1–4 applies. |
