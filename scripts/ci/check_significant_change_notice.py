#!/usr/bin/env python3
"""EB-02(d) (engineering-backlog-us.md §2; docs/release/significant-change-checklist.md): "A change
to the policy's machine-readable POLICY-FLOWS block fails CI unless the release is marked as a
significant change or explicitly not one."

This script checks exactly that one mechanical trigger (test 1 of the checklist's four — the other
three, age-rating change, first-time monetization and "materially changes functionality or UX",
are either automatic in the app itself or a judgement call no script can make). It compares the
changed files in this branch against a short list of paths that stand in for "data categories
collected, stored or shared changed" or "first-time monetization":

  - `site/privacy/index.html` (the `POLICY-FLOWS` comment `check_policy_matches_app.py` reads);
  - `packages/TallyCore/Sources/TallyDomain/Subscription/SubscriptionConfig.swift` (the product
    list: a new product here is first-time monetization, Ala. HB161 §1(19)).

If either changed, `docs/release/significant-change-log.md` must carry a dated row for this
commit with an explicit `yes` or `no` in its "Significant change?" column — a missing row, or one
whose answer is blank or still the template's, fails. Neither file changing is always fine with no
row required (most PRs).

    python3 scripts/ci/check_significant_change_notice.py [--base REF] [--commit SHA] [ROOT]
    python3 scripts/ci/check_significant_change_notice.py --self-test

Exit 0: no significant-surface file changed, or one did and the ledger has a dated, decided row
for this commit. Exit 1: one changed and the ledger has no such row. Exit 2: an input (git, or the
ledger file) could not be read.
"""
from __future__ import annotations

import pathlib
import re
import subprocess
import sys

LEDGER = "docs/release/significant-change-log.md"
# Paths that stand in for checklist test 1 (data categories) and test 3 (first-time monetization).
# Test 2 (age rating) is automatic in the app (`AgeRatingChangeDetector`) and needs no ledger row;
# test 4 ("materially changes functionality or UX") is a judgement call this script cannot make —
# the checklist asks engineers to add a row for it even when neither path below changed.
SIGNIFICANT_SURFACE = (
    "site/privacy/index.html",
    "packages/TallyCore/Sources/TallyDomain/Subscription/SubscriptionConfig.swift",
)
# A markdown table row: | commit | date | yes/no | reason |. The commit cell may be a short or
# full SHA; a row matches a given commit if that commit starts with the cell's text (a short SHA
# in the ledger matching a full one on the command line) or vice versa.
LEDGER_ROW = re.compile(r"^\|\s*([0-9a-f]{7,40})\s*\|\s*([^|]+?)\s*\|\s*(yes|no)\s*\|\s*([^|]+?)\s*\|\s*$",
                        re.M | re.I)


class InputError(Exception):
    pass


def changed_significant_surface(changed_files: list[str]) -> list[str]:
    """Which of `SIGNIFICANT_SURFACE` appear in `changed_files` (repo-relative, forward slashes)."""
    changed = set(changed_files)
    return [path for path in SIGNIFICANT_SURFACE if path in changed]


def ledger_entry_for(ledger_text: str, commit: str) -> tuple[str, str] | None:
    """(date, decision) for the first ledger row matching `commit`, or `None` if none does. A
    template row (date "YYYY-MM-DD") never matches a real commit, since no real commit is the
    literal string `_(template...)_` this checks against the SHA pattern, not the date, so the
    template row simply never matches any `LEDGER_ROW` capture for the commit group — it is
    filtered out by `LEDGER_ROW` not matching its first cell at all (`_(template...)_` is not hex)."""
    for match in LEDGER_ROW.finditer(ledger_text):
        row_commit, date, decision, _reason = match.groups()
        if commit.startswith(row_commit) or row_commit.startswith(commit):
            return date, decision.lower()
    return None


def check(changed_files: list[str], ledger_text: str | None, commit: str) -> tuple[bool, str]:
    """(ok, detail). Pure: no git, no file reads — `main()` gathers those."""
    hits = changed_significant_surface(changed_files)
    if not hits:
        return True, "no significant-surface file changed; no ledger row required"
    if ledger_text is None:
        return False, f"{LEDGER} could not be read, but {', '.join(hits)} changed"
    entry = ledger_entry_for(ledger_text, commit)
    if entry is None:
        return False, f"{', '.join(hits)} changed, but {LEDGER} has no dated, decided row for {commit}"
    date, decision = entry
    return True, f"{', '.join(hits)} changed; {LEDGER} records {commit} ({date}): {decision}"


def _git_changed_files(root: pathlib.Path, base: str) -> list[str]:
    result = subprocess.run(["git", "diff", "--name-only", f"{base}...HEAD"], cwd=root,
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise InputError(f"git diff --name-only {base}...HEAD failed: {result.stderr.strip()}")
    return [line for line in result.stdout.splitlines() if line]


def _git_head(root: pathlib.Path) -> str:
    result = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, capture_output=True, text=True)
    if result.returncode != 0:
        raise InputError(f"git rev-parse HEAD failed: {result.stderr.strip()}")
    return result.stdout.strip()


def self_test() -> int:
    assert changed_significant_surface(["site/privacy/index.html", "README.md"]) == ["site/privacy/index.html"]
    assert changed_significant_surface(["README.md"]) == []
    ledger = ("# Significant-change decisions\n\n"
             "| Commit | Date | Significant change? | Reason |\n"
             "|---|---|---|---|\n"
             "| abc1234 | 2026-10-21 | no | Only a layout fix; no data, rating or monetization change. |\n"
             "| def5678 | 2026-11-01 | yes | Added a second purchasable product (Ala. §1(19) monetization). |\n")
    assert ledger_entry_for(ledger, "abc1234567890") == ("2026-10-21", "no")
    assert ledger_entry_for(ledger, "def5678") == ("2026-11-01", "yes")
    assert ledger_entry_for(ledger, "0000000") is None
    template = "| _(template — delete this row)_ | YYYY-MM-DD | yes / no | One sentence... |\n"
    assert ledger_entry_for(template, "abc1234") is None, "the template row must never match a real commit"

    ok, detail = check(["README.md"], None, "abc1234")
    assert ok, detail
    ok, detail = check(["site/privacy/index.html"], None, "abc1234")
    assert not ok, "a significant-surface change with no ledger at all must fail"
    ok, detail = check(["site/privacy/index.html"], ledger, "0000000")
    assert not ok, "a significant-surface change with no matching row must fail"
    ok, detail = check(["site/privacy/index.html"], ledger, "abc1234567890")
    assert ok, detail
    ok, detail = check(["packages/TallyCore/Sources/TallyDomain/Subscription/SubscriptionConfig.swift"],
                       ledger, "def5678")
    assert ok, detail
    print("check_significant_change_notice self-test: 10 checks passed")
    return 0


def main(argv: list[str]) -> int:
    args = argv[1:]
    if args == ["--self-test"]:
        return self_test()
    base, commit, root_arg = "origin/main", None, None
    i = 0
    while i < len(args):
        if args[i] == "--base" and i + 1 < len(args):
            base, i = args[i + 1], i + 2
        elif args[i] == "--commit" and i + 1 < len(args):
            commit, i = args[i + 1], i + 2
        else:
            root_arg, i = args[i], i + 1
    root = pathlib.Path(root_arg or ".").resolve()
    try:
        changed = _git_changed_files(root, base)
        head = commit or _git_head(root)
        ledger_path = root / LEDGER
        ledger_text = ledger_path.read_text(encoding="utf-8") if ledger_path.exists() else None
        ok, detail = check(changed, ledger_text, head)
    except InputError as error:
        print(f"SIGNIFICANT-CHANGE | ERROR | input | {error}")
        return 2
    print(f"SIGNIFICANT-CHANGE | {'PASS' if ok else 'FAIL'} | {head} | {detail}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
