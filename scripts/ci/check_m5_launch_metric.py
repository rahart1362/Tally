#!/usr/bin/env python3
"""REL.m5.launch-metric: compare the warm-launch median against a stored baseline and report a
regression over the owner's threshold (docs/pmo/reviews/perf-app-runtime.md §5.2; perf1/report.md
§3; pmo-perffix1-prompt.md item 1).

`XCTApplicationLaunchMetric` (`TallyPerfUITests.swift:128-136`, `testWarmApplicationLaunch`)
produces 0 parseable measurements on this toolchain (perf1/report.md §3: the test name never
appears in any `PERF-BUDGET`/`PERF-REPORT` line of run 39178437255's full `ios-perf` job log).
This check reads `Launch.GlancePaint` instead (`TallyPerfUITests/testWarmLaunchGlancePaint`'s
`XCTOSSignpostMetric`), which already parses correctly and already gates `ios-perf`'s own
CI-simulator budget (`perf/budgets.json`): the report's suggested substitute, since it covers the
same warm-launch path end to end.

    python3 scripts/ci/check_m5_launch_metric.py perf/m5_launch_baseline.json METRICS_JSON --json OUT

`METRICS_JSON` is `xcrun xcresulttool get test-results metrics --compact` output -- the same file
`check_perf_budgets.py` reads (`ios-perf`'s `$IOS_OUT/perf-metrics.json`).

This writes exactly one `check_release.py`-shaped `Check`, `REL.m5.launch-metric`, with `due`
left at `M5` and `level` forced to `WARN`, so it is reported with the real median and regression
percentage, and the check's own `status` is `PASS` when inside budget or `PENDING` otherwise --
never `FAIL` -- regardless of what CI run calls this script (pmo-perffix1-prompt.md item 1: "it
must not FAIL the MVP gate until the owner promotes it"). `write()`'s own return value is passed
through unchanged (always 0 here, by the same forcing), so a caller never needs to swallow a
non-zero exit to keep this report-only.

Exit codes: 0 whenever the inputs are readable (a regression is a failing *check*, reported in
its `detail`, never a failing *process*); 2 when an input cannot be read.
`--self-test` checks the matching, ratio and PENDING-not-FAIL logic.
"""
from __future__ import annotations

import importlib.util
import json
import pathlib
import statistics
import sys


def _sibling(name: str):
    path = pathlib.Path(__file__).resolve().with_name(f"{name}.py")
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def evaluate(baseline: dict, document: object) -> tuple[bool, str]:
    """(within_budget, detail). `within_budget` is False both when a regression is found and when
    no measurement exists at all -- a missing metric never passes silently, the same rule
    `check_perf_budgets.py` uses."""
    perf_budgets = _sibling("check_perf_budgets")
    measurements = perf_budgets.collect(document)
    test = baseline["test"]
    names = baseline["metric"]
    names = [names] if isinstance(names, str) else list(names)
    hits = [m for m in measurements if test in m.test and any(n in (m.metric_id, m.metric_name) for n in names)]
    unit = baseline.get("unit", "s")
    if not hits:
        return False, f"no measurements for {test} / {names[0]} in the given metrics JSON"
    median = statistics.median(statistics.median(m.values) for m in hits)
    baseline_median = float(baseline["baseline_median"])
    max_ratio = float(baseline["regression_max_ratio"])
    if baseline_median <= 0:
        return False, f"baseline_median must be positive, got {baseline_median}"
    ratio = median / baseline_median
    regression_pct = (ratio - 1) * 100
    allowed_pct = (max_ratio - 1) * 100
    ok = ratio <= max_ratio
    detail = (f"median {median:.4f}{unit} vs baseline {baseline_median:.4f}{unit} "
              f"({regression_pct:+.1f}%; report-only budget <= {allowed_pct:.0f}% over baseline)")
    return ok, detail


def main(argv: list[str]) -> int:
    if argv[1:] == ["--self-test"]:
        return self_test()
    if len(argv) != 5 or argv[3] != "--json":
        print(__doc__)
        return 2
    baseline_path, metrics_path, out = argv[1], argv[2], argv[4]
    try:
        baseline = json.loads(pathlib.Path(baseline_path).read_text(encoding="utf-8"))
        document = json.loads(pathlib.Path(metrics_path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"M5-LAUNCH | ERROR | cannot read input: {error}")
        return 2
    ok, detail = evaluate(baseline, document)
    print(f"M5-LAUNCH | {'PASS' if ok else 'PENDING'} | REL.m5.launch-metric | {detail}")
    check_release = _sibling("check_release")
    check = check_release.Check("REL.m5.launch-metric", "Launch time within 20% of the stored baseline (M5)",
                                "WARN", "M5", ok, detail,
                                owner="M5 (owner promotes once 5 green non-blocking runs and the D-P3 device "
                                      "calibration both land)")
    return check_release.write([check], out, "m5-launch", report_only=True)


def self_test() -> int:
    baseline = {"test": "TallyPerfUITests/testWarmLaunchGlancePaint",
                "metric": ["com.apple.dt.XCTMetric_OSSignpost-Launch.GlancePaint.duration", "Duration (Launch.GlancePaint)"],
                "unit": "s", "baseline_median": 1.30, "regression_max_ratio": 1.2}

    def document(values):
        return [{"testIdentifier": "TallyPerfUITests/testWarmLaunchGlancePaint()", "testRuns": [{"metrics": [
            {"displayName": "Duration (Launch.GlancePaint)",
             "identifier": "com.apple.dt.XCTMetric_OSSignpost-Launch.GlancePaint.duration",
             "unitOfMeasurement": "s", "measurements": values}]}]}]

    ok, detail = evaluate(baseline, document([1.30, 1.31, 1.29, 1.32, 1.28]))
    assert ok and "+0" in detail, detail
    ok, detail = evaluate(baseline, document([1.60, 1.61, 1.59, 1.62, 1.58]))
    assert not ok, "a >20% regression must be reported as not-ok"
    assert "+2" in detail, detail
    ok, detail = evaluate(baseline, [])
    assert not ok, "no measurements must never pass silently"
    assert "no measurements" in detail, detail

    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        out = str(pathlib.Path(tmp) / "m5-launch.json")
        check_release = _sibling("check_release")
        check = check_release.Check("REL.m5.launch-metric", "t", "WARN", "M5", False, "forced regression for the test")
        exit_code = check_release.write([check], out, "m5-launch", report_only=True)
        assert exit_code == 0, "a regression must never make write() return a failing exit code"
        written = json.loads(pathlib.Path(out).read_text(encoding="utf-8"))
        status = written["checks"][0]["status"]
        assert status in ("PENDING", "WARN"), f"a regression must never settle to FAIL, got {status}"

        passing = check_release.Check("REL.m5.launch-metric", "t", "WARN", "M5", True, "within budget")
        check_release.write([passing], out, "m5-launch", report_only=True)
        written = json.loads(pathlib.Path(out).read_text(encoding="utf-8"))
        assert written["checks"][0]["status"] == "PASS", written["checks"][0]

    print("check_m5_launch_metric self-test: 6 checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
