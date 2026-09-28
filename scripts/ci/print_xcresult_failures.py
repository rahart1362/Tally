#!/usr/bin/env python3
"""Print an xcresult test summary with every failure's text in full.

xcodebuild's console output keeps only the first line of a multi-line failure.
For a UI test, the lines it drops are the accessibility hierarchy, which is
the evidence needed to diagnose it (docs/pmo/reviews/perf-app-runtime.md §6).
This script prints each failure whole, so the CI log alone is enough.

    xcrun xcresulttool get test-results summary --path Tally.xcresult \
        --compact --format json > summary.json
    python3 scripts/ci/print_xcresult_failures.py summary.json

The keys were checked against real output from CI run 36353526769: result,
totalTestCount, passedTests, failedTests, skippedTests, expectedFailures, and
testFailures[] with testIdentifierString, targetName and failureText.

This is a report step, so it always exits 0; the test step owns pass/fail.
If the JSON is missing or has an unexpected shape, the script prints the raw
text instead of hiding it.
"""
import json
import sys


def main(path: str) -> int:
    try:
        with open(path, encoding="utf-8") as handle:
            raw = handle.read()
    except OSError as error:
        print(f"No xcresult summary to print ({error}).")
        return 0
    try:
        summary = json.loads(raw)
        failures = summary.get("testFailures", [])
    except (json.JSONDecodeError, AttributeError):
        print("xcresult summary is not the expected JSON; raw text follows.")
        print(raw)
        return 0

    counts = ", ".join(
        f"{key}={summary.get(key)}"
        for key in ("result", "totalTestCount", "passedTests", "failedTests",
                    "skippedTests", "expectedFailures")
    )
    print(f"xcresult: {counts}")
    for number, failure in enumerate(failures, start=1):
        name = failure.get("testIdentifierString") or failure.get("testName", "?")
        print(f"\n===== Failure {number}/{len(failures)}: "
              f"{failure.get('targetName', '?')} / {name}")
        print(failure.get("failureText", "(no failure text)"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "/dev/stdin"))
