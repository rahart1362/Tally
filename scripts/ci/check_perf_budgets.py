#!/usr/bin/env python3
"""Compare XCTest performance metrics with perf/budgets.json (perf-app-runtime.md §5.2 and §6).

    xcrun xcresulttool get test-results metrics --path Tally-perf.xcresult --compact > metrics.json
    python3 scripts/ci/check_perf_budgets.py perf/budgets.json metrics.json [--log perf.log]

Each budget names a test (a substring of the xcresult test identifier), a metric (matched against
a metric's identifier or display name) and the largest allowed median, in the metric's own unit.
It prints one line per budget and per unbudgeted metric, then exits:

- 0 when every budget has measurements and every median is within its budget;
- 1 when a median is over budget, or a budgeted metric has no measurements at all (a missing
  metric never passes silently), or (with `--log`, the xcodebuild log) a budgeted test failed;
- 2 when either file is unreadable.

The metrics JSON schema is UNVERIFIED (perf-app-runtime.md §5.2: "write the script against the
first real output"). So the reader does not depend on exact nesting: it walks the document for
objects that carry a numeric `measurements` array and attributes each one to the nearest
enclosing object that has a `testIdentifier`. When nothing is found it prints the raw document.

With `--log`, a failed XCTest case in the log fails its budget even when its median is within it
(its measurements may be partial), and a failed test with no budget is reported without gating: the
budgets are the gate (M2 exit, owner decision on O10), so a diagnostic perf test's failure no longer
hides them (m2-lifecycle-report O11).
`--self-test` checks the matching and median logic against a small document in the documented
shape; CI's hygiene job runs it.
"""
from __future__ import annotations

import json
import re
import statistics
import sys
from dataclasses import dataclass


@dataclass(frozen=True)
class Measurement:
    test: str
    metric_id: str
    metric_name: str
    unit: str
    values: tuple[float, ...]

    @property
    def median(self) -> float:
        return statistics.median(self.values)


def collect(node: object, test: str = "?") -> list[Measurement]:
    """Every metric object under `node`, tagged with its nearest enclosing test identifier."""
    found: list[Measurement] = []
    if isinstance(node, dict):
        test = str(node.get("testIdentifier") or node.get("testIdentifierString") or test)
        values = node.get("measurements")
        if isinstance(values, list) and values and all(isinstance(v, (int, float)) for v in values):
            found.append(Measurement(
                test=test,
                metric_id=str(node.get("identifier", "")),
                metric_name=str(node.get("displayName", "")),
                unit=str(node.get("unitOfMeasurement", "")),
                values=tuple(float(v) for v in values),
            ))
        for value in node.values():
            found.extend(collect(value, test))
    elif isinstance(node, list):
        for item in node:
            found.extend(collect(item, test))
    return found


def metric_names(budget: dict) -> list[str]:
    names = budget["metric"]
    return [names] if isinstance(names, str) else list(names)


def matches(budget: dict, measurement: Measurement) -> bool:
    if budget["test"] not in measurement.test:
        return False
    return any(name in (measurement.metric_id, measurement.metric_name) for name in metric_names(budget))


def failed_tests(log: str) -> set[str]:
    """`Class/method` for every XCTest case an xcodebuild log reports as failed."""
    return {f"{cls}/{method}" for cls, method in re.findall(r"Test Case '-\[(?:\w+\.)?(\w+) (\w+)\]' failed", log)}


def check(budgets: list[dict], measurements: list[Measurement],
          failed: set[str] = frozenset()) -> tuple[list[str], bool]:
    lines: list[str] = []
    ok = True
    used: set[int] = set()
    gated: set[str] = set()
    for budget in budgets:
        failures = sorted(f for f in failed if budget["test"] in f)
        gated.update(failures)
        if failures:
            ok = False
            lines.append(f"PERF-BUDGET | FAIL | {budget['name']} | its test failed ({', '.join(failures)}); "
                         f"the failure is in the log above")
        hits = [(i, m) for i, m in enumerate(measurements) if matches(budget, m)]
        if not hits:
            ok = False
            lines.append(f"PERF-BUDGET | MISSING | {budget['name']} | no measurements for "
                         f"{budget['test']} / {metric_names(budget)[0]}")
            continue
        for index, m in hits:
            used.add(index)
            within = m.median <= float(budget["median_max"])
            ok = ok and within
            lines.append(f"PERF-BUDGET | {'PASS' if within else 'FAIL'} | {budget['name']} | "
                         f"median {m.median:.4f} {m.unit} <= {budget['median_max']} {budget['unit']} | "
                         f"n={len(m.values)} | {m.test}")
    for index, m in enumerate(measurements):
        if index not in used:
            lines.append(f"PERF-REPORT | {m.test} | {m.metric_name or m.metric_id} | "
                         f"median {m.median:.4f} {m.unit} | n={len(m.values)}")
    for test in sorted(failed - gated):
        lines.append(f"PERF-REPORT | {test} | failed; it has no budget, so it does not gate")
    return lines, ok


def self_test() -> int:
    document = [{
        "testIdentifier": "SampleLoadPerformanceTests/testSampleEntryToFullProjection()",
        "testRuns": [{"metrics": [
            {"displayName": "Clock Monotonic Time", "identifier": "com.apple.dt.XCTMetric_Clock.time.monotonic",
             "unitOfMeasurement": "s", "measurements": [0.12, 0.10, 0.30, 0.11, 0.13]},
            {"displayName": "Memory Physical", "identifier": "com.apple.dt.XCTMetric_Memory.physical",
             "unitOfMeasurement": "kB", "measurements": [1024, 2048, 1536]},
        ]}],
    }]
    budget = {"name": "entry", "test": "SampleLoadPerformanceTests/testSampleEntryToFullProjection",
              "metric": ["com.apple.dt.XCTMetric_Clock.time.monotonic"], "median_max": 0.150, "unit": "s"}
    found = collect(document)
    assert len(found) == 2, found
    assert found[0].median == 0.12, found[0]  # the 0.30 outlier does not move the median
    assert found[0].test.startswith("SampleLoadPerformanceTests/"), found[0]

    lines, ok = check([budget], found)
    assert ok, lines
    assert any(line.startswith("PERF-REPORT") and "Memory Physical" in line for line in lines), lines

    _, ok = check([dict(budget, median_max=0.11)], found)
    assert not ok, "an over-budget median must fail"
    _, ok = check([dict(budget, test="NoSuchTest")], found)
    assert not ok, "a budget with no measurements must fail, never pass silently"
    _, ok = check([dict(budget, metric="Clock Monotonic Time")], found)
    assert ok, "a display name must match as well as an identifier"

    log = ("Test Case '-[TallyAppTests.SampleLoadPerformanceTests testSampleEntryToFullProjection]' failed (1.0 seconds).\n"
           "Test Case '-[TallyUITests.TallyPerfUITests testUnobservedWarmLaunchGlancePaint]' failed (309.4 seconds).\n"
           "Test Case '-[TallyUITests.TallyPerfUITests testWarmLaunchGlancePaint]' passed (70.7 seconds).\n")
    failed = failed_tests(log)
    assert failed == {"SampleLoadPerformanceTests/testSampleEntryToFullProjection",
                      "TallyPerfUITests/testUnobservedWarmLaunchGlancePaint"}, failed
    lines, ok = check([budget], found, failed)
    assert not ok, "a budgeted test that failed must fail its budget even within the median"
    lines, ok = check([budget], found, {"TallyPerfUITests/testUnobservedWarmLaunchGlancePaint"})
    assert ok, "a failed test with no budget must not gate"
    assert any("testUnobservedWarmLaunchGlancePaint | failed" in line for line in lines), lines
    print("check_perf_budgets self-test: 8 checks passed")
    return 0


def main(argv: list[str]) -> int:
    if argv[1:] == ["--self-test"]:
        return self_test()
    log_path = None
    if len(argv) == 5 and argv[3] == "--log":
        log_path = argv[4]
    elif len(argv) != 3:
        print(__doc__)
        return 2
    try:
        with open(argv[1], encoding="utf-8") as handle:
            budgets = json.load(handle)["budgets"]
        with open(argv[2], encoding="utf-8") as handle:
            raw = handle.read()
        document = json.loads(raw)
        failed: set[str] = set()
        if log_path:
            with open(log_path, encoding="utf-8", errors="replace") as handle:
                failed = failed_tests(handle.read())
    except (OSError, KeyError, json.JSONDecodeError) as error:
        print(f"PERF-BUDGET | ERROR | cannot read input: {error}")
        return 2

    measurements = collect(document)
    if not measurements:
        print("PERF-BUDGET | ERROR | no metric measurements found; raw metrics JSON follows")
        print(raw)
    lines, ok = check(budgets, measurements, failed)
    print("\n".join(lines))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
