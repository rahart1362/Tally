#!/usr/bin/env python3
"""Pick an available iOS 26+ iPhone simulator for CI (WP-E02).

architecture.md §3.6 requires the destination to be "picked by script from
`simctl list -j`, never a hard-coded name" — hard-coded device names break
whenever a runner image drops or renames a simulator. This reads
`simctl list devices available -j`, keeps only iOS runtimes at or above
`min_major` (default 26, Tally's deployment target) with at least one
available iPhone, and prints the newest such runtime's first iPhone as
`key=value` lines on stdout, ready for `>> "$GITHUB_OUTPUT"`. Used on both
the macOS 26 / Xcode 26.6 job (iOS 26.x simulators) and the Xcode 27
forward-compat job (iOS 27.x simulators), so the minimum is a parameter,
not a hard-coded "26".

`--oldest` picks the oldest qualifying runtime instead. The deployment-floor
step uses it to run the hosted tests on the lowest iOS 26.x the runner has,
because some runtime bugs affect only early 26.x releases (swiftlang/swift#88036,
isolated deinit, fixed in iOS 26.4; docs/pmo/reviews/perf-app-runtime.md §4.6).

`--smallest` picks the iPhone with the smallest screen in points on any qualifying
runtime, the newest runtime winning a tie (perf-app-runtime.md §7 step 3: Welcome's
CTAs must be hittable on the smallest available iPhone). `simctl` does not report
screen sizes, so the sizes come from the table below; an iPhone missing from it
ranks last, and every candidate is printed to stderr so the choice is visible in
the CI log.

Usage: pick_ios_simulator.py [--min-major N] [--oldest | --smallest] [path/to/simctl_output.json]
Reads `xcrun simctl list devices available -j` itself if no path is given.
"""
from __future__ import annotations

import json
import subprocess
import sys


def runtime_major(runtime_id: str) -> int | None:
    # "com.apple.CoreSimulator.SimRuntime.iOS-26-2" -> 26
    if "iOS-" not in runtime_id:
        return None
    tail = runtime_id.rsplit("iOS-", 1)[-1]
    head = tail.split("-", 1)[0]
    return int(head) if head.isdigit() else None


def runtime_sort_key(runtime_id: str) -> tuple[int, ...]:
    # "com.apple.CoreSimulator.SimRuntime.iOS-26-2" -> (26, 2)
    tail = runtime_id.rsplit("iOS-", 1)[-1]
    return tuple(int(part) for part in tail.split("-") if part.isdigit())


# Logical screen size in points (width x height, portrait) of iPhones that run iOS 26+.
SCREEN_POINTS = {
    "iPhone SE (3rd generation)": (375, 667),
    "iPhone SE (2nd generation)": (375, 667),
    "iPhone 11": (414, 896),
    "iPhone 11 Pro": (375, 812),
    "iPhone 11 Pro Max": (414, 896),
    "iPhone 12 mini": (375, 812),
    "iPhone 13 mini": (375, 812),
    "iPhone 12": (390, 844),
    "iPhone 13": (390, 844),
    "iPhone 14": (390, 844),
    "iPhone 16e": (390, 844),
    "iPhone 15": (393, 852),
    "iPhone 15 Pro": (393, 852),
    "iPhone 16": (393, 852),
    "iPhone 16 Pro": (402, 874),
    "iPhone 17": (402, 874),
    "iPhone 17 Pro": (402, 874),
    "iPhone Air": (420, 912),
    "iPhone 14 Plus": (428, 926),
    "iPhone 15 Plus": (430, 932),
    "iPhone 16 Plus": (430, 932),
    "iPhone 16 Pro Max": (440, 956),
    "iPhone 17 Pro Max": (440, 956),
}


def screen_area(name: str) -> float:
    size = SCREEN_POINTS.get(name)
    return float("inf") if size is None else float(size[0] * size[1])


def pick_smallest(data: dict, min_major: int) -> tuple[str, str, str]:
    """The smallest-screen iPhone on any qualifying runtime; ties go to the newest runtime."""
    candidates = []
    for runtime_id, devices in data.get("devices", {}).items():
        major = runtime_major(runtime_id)
        if major is None or major < min_major:
            continue
        for device in devices:
            if device.get("isAvailable") and "iPhone" in device.get("name", ""):
                negated_version = tuple(-part for part in runtime_sort_key(runtime_id))
                candidates.append((screen_area(device["name"]), negated_version, runtime_id, device))
    if not candidates:
        raise SystemExit(f"No available iOS {min_major}+ iPhone simulator found on this runner image.")
    candidates.sort(key=lambda c: (c[0], c[1]))
    for area, _, runtime_id, device in candidates:
        size = SCREEN_POINTS.get(device["name"], "unknown size")
        print(f"  candidate: {device['name']} {size} on {runtime_id}", file=sys.stderr)
    _, _, runtime_id, device = candidates[0]
    return runtime_id, device["udid"], device["name"]


def pick(data: dict, min_major: int, oldest: bool = False) -> tuple[str, str, str]:
    candidates = []
    for runtime_id, devices in data.get("devices", {}).items():
        major = runtime_major(runtime_id)
        if major is None or major < min_major:
            continue
        for device in devices:
            if device.get("isAvailable") and "iPhone" in device.get("name", ""):
                candidates.append((runtime_sort_key(runtime_id), runtime_id, device["udid"], device["name"]))

    if not candidates:
        raise SystemExit(f"No available iOS {min_major}+ iPhone simulator found on this runner image.")

    # Stable sort on the runtime version only, so each runtime keeps simctl's device order.
    candidates.sort(key=lambda c: c[0], reverse=not oldest)
    _, runtime_id, udid, name = candidates[0]
    return runtime_id, udid, name


def main() -> None:
    args = sys.argv[1:]
    min_major = 26
    if "--min-major" in args:
        i = args.index("--min-major")
        min_major = int(args[i + 1])
        del args[i : i + 2]
    oldest = "--oldest" in args
    if oldest:
        args.remove("--oldest")
    smallest = "--smallest" in args
    if smallest:
        args.remove("--smallest")

    if args:
        with open(args[0]) as f:
            data = json.load(f)
    else:
        out = subprocess.run(
            ["xcrun", "simctl", "list", "devices", "available", "-j"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        data = json.loads(out)

    if smallest:
        runtime_id, udid, name = pick_smallest(data, min_major)
    else:
        runtime_id, udid, name = pick(data, min_major, oldest)
    print(f"Selected {name} on {runtime_id} ({udid})", file=sys.stderr)
    print(f"udid={udid}")
    print(f"name={name}")
    print(f"runtime={runtime_id}")


if __name__ == "__main__":
    main()
