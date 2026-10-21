#!/usr/bin/env python3
"""Print each shared TallyCore perf gate's Apple-silicon/Linux timing ratio (PERF-FIX-2 item 3;
perf1/report.md §4 opportunity 4). Report-only -- never a gate; the two lanes already gate
themselves independently (`core-perf`'s and `core-perf-apple`'s own `#expect`s in RegressionGates/
BoundedGradeGate/GoalSeekBoundedWorstCaseGate/GradeAvailabilityBenchmarks.swift).

    python3 scripts/ci/check_perf_lane_ratio.py <linux-perf.log> <apple-perf.log>

Each log is one of those two jobs' captured stdout: `make core-perf`'s (or `swift test -c
release`'s) own `PERF-BUDGET | <name> | median X.XXms ...` or `... CI=X.XXms x factor F =
projected Y.YYms ...` lines. For every benchmark name present in both logs, prints
`PERF-RATIO | <name> | Linux X.XXms | Apple Y.YYms | Apple/Linux Z.ZZx`, plus one line for any
name seen in only one log (a benchmark one lane skips or a new one the other hasn't picked up
yet).

Why a ratio, not just each lane's own ceiling: perf1/report.md found the same `dashboardBuild/
stress` benchmark reading ~4.2x slower on Apple silicon than on Linux, and `snapshotDecodeDevice/
stress` negative on both lanes but by very different margins -- a ratio that drifts between runs
is often a cheaper early warning of a real regression than waiting for either lane's own absolute
ceiling to fail, since it is less sensitive to one shared runner's own noise (both lanes move
together under real load; only a code change should move the ratio between them). This script
does not store history or flag drift itself -- it is the diagnostic a reviewer reads run over run,
the same way perf1/report.md's own S1.1 table did by hand from two job logs.

The two jobs run on separate runners (`core-perf`: Linux/Docker, every push/PR/dispatch;
`core-perf-apple`: macOS, main pushes and full dispatches only) and today do not share a workflow
step, so this takes each lane's already-downloaded log as a file -- `gh run view --log` against
each job's databaseId -- rather than reading live CI state itself. Wiring an automatic upload/
download/compare into `ci.yml` is outside this work package (the charter reserves workflow edits
for the PMO: docs/pmo/05-perf-crash-charter.md); this script is the ready-to-run report-only tool
the PMO can use by hand today, or wire into a follow-up job later.

`--self-test` checks the parsing and pairing logic against two small fixture logs.
"""
from __future__ import annotations

import re
import sys

LINE = re.compile(r"PERF-BUDGET \| (?P<name>[\w/\-]+) \|.*?(?:median|projected) (?P<value>\d+\.\d+)ms")


def parse(log: str) -> dict[str, float]:
    """The reported median/projected value (ms) for each benchmark name in one log. Last line
    wins if a name repeats (it does not in one real run; this only matters if a log is ever
    concatenated from more than one run)."""
    values: dict[str, float] = {}
    for match in LINE.finditer(log):
        values[match["name"]] = float(match["value"])
    return values


def report(linux: dict[str, float], apple: dict[str, float]) -> list[str]:
    lines: list[str] = []
    shared = sorted(set(linux) & set(apple))
    if not linux and not apple:
        lines.append("PERF-RATIO | no PERF-BUDGET line found in either log")
        return lines
    for name in shared:
        ratio = (apple[name] / linux[name]) if linux[name] else float("inf")
        lines.append(f"PERF-RATIO | {name} | Linux {linux[name]:.2f}ms | Apple {apple[name]:.2f}ms | "
                     f"Apple/Linux {ratio:.2f}x")
    for name in sorted(set(linux) - set(apple)):
        lines.append(f"PERF-RATIO | {name} | Linux only ({linux[name]:.2f}ms); no matching Apple-silicon line this run")
    for name in sorted(set(apple) - set(linux)):
        lines.append(f"PERF-RATIO | {name} | Apple only ({apple[name]:.2f}ms); no matching Linux line this run")
    return lines


def self_test() -> int:
    linux_log = (
        "PERF-BUDGET | dashboardBuild/stress | median 5.72ms | ceiling 13.00ms | headroom 7.28ms\n"
        "PERF-BUDGET | gradeEngineBoundedWorstCase/f5Shape | median 2.49ms | ceiling 50.00ms | headroom 47.51ms\n"
        "PERF-BUDGET | snapshotDecodeDevice/stress | CI=42.88ms x factor 2.0 = projected 85.75ms "
        "| gated ceiling 80.00ms (80% of 100.0ms) | headroom -5.75ms\n"
    )
    apple_log = (
        "PERF-BUDGET | dashboardBuild/stress | median 24.10ms | ceiling 56.00ms | headroom 31.90ms\n"
        "PERF-BUDGET | gradeEngineBoundedWorstCase/f5Shape | median 5.52ms | ceiling 50.00ms | headroom 44.48ms\n"
        "PERF-BUDGET | snapshotDecodeDevice/stress | CI=57.06ms x factor 2.0 = projected 114.12ms "
        "| gated ceiling 80.00ms (80% of 100.0ms) | headroom -34.12ms\n"
        "PERF-BUDGET | appleOnlyBench | median 1.00ms | ceiling 2.00ms | headroom 1.00ms\n"
    )
    linux = parse(linux_log)
    apple = parse(apple_log)
    assert linux["dashboardBuild/stress"] == 5.72, linux
    assert apple["snapshotDecodeDevice/stress"] == 114.12, apple
    assert "appleOnlyBench" not in linux, linux

    lines = report(linux, apple)
    joined = "\n".join(lines)
    assert "dashboardBuild/stress" in joined and "4.21x" in joined, joined  # 24.10 / 5.72
    assert "appleOnlyBench" in joined and "Apple only" in joined, joined
    assert len(lines) == 4, lines  # 3 shared names + 1 apple-only name

    empty = report({"onlyLinux": 1.0}, {})
    assert len(empty) == 1 and "Linux only" in empty[0], empty

    print("check_perf_lane_ratio self-test: 7 checks passed")
    return 0


def main(argv: list[str]) -> int:
    if argv[1:] == ["--self-test"]:
        return self_test()
    if len(argv) != 3:
        print(__doc__)
        return 2
    try:
        with open(argv[1], encoding="utf-8", errors="replace") as handle:
            linux = parse(handle.read())
        with open(argv[2], encoding="utf-8", errors="replace") as handle:
            apple = parse(handle.read())
    except OSError as error:
        print(f"PERF-RATIO | ERROR | cannot read input: {error}")
        return 2
    print("\n".join(report(linux, apple)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
