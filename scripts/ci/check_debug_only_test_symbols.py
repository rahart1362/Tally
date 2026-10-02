#!/usr/bin/env python3
"""Test code may use DEBUG-only test support only inside `#if DEBUG` (PMO, 2026-10-01).

`ios-perf` builds the test targets in Release, and it is the only job that does: `quick` and
`unit` runs never build them that way. A test that uses a type declared only under `#if DEBUG`
(such as `AccountHarness`, in `AccountLifecycleTestSupport.swift`) compiles in every iteration run
and then fails the PR run's Release build. That happened in PR #23, run 36922905739
(`GradeControlsViewTests.swift:364: cannot find 'AccountHarness' in scope`). This check finds the
same mistake in seconds on Linux.

How it works:
- Collect the top-level names declared only inside `#if DEBUG` regions of the test targets'
  sources (types, functions, constants).
- Report every use of one of those names outside a `#if DEBUG` region, ignoring comments and
  strings.

Usage: `check_debug_only_test_symbols.py [--self-test] [ROOT]`
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

TEST_DIRS = ("apps/TallyiOS/TallyAppTests", "apps/TallyiOS/TallyUITests")
DECL = re.compile(r"^(?:(?:@\w+(?:\([^)]*\))?|public|internal|private|fileprivate|final|nonisolated|static)\s+)*"
                  r"(?:struct|class|enum|actor|protocol|typealias|func|let|var)\s+([A-Za-z_]\w*)")


def code_only(lines: list[str]) -> list[str]:
    """Each line with comments and string literals blanked: `//`, `/* */` and `\"\"\"` blocks included."""
    out, in_block, in_multiline = [], False, False
    for line in lines:
        code, i = [], 0
        while i < len(line):
            if in_multiline:
                end = line.find('"""', i)
                if end < 0:
                    i = len(line)
                else:
                    in_multiline, i = False, end + 3
            elif in_block:
                end = line.find("*/", i)
                if end < 0:
                    i = len(line)
                else:
                    in_block, i = False, end + 2
            elif line.startswith('"""', i):
                in_multiline, i = True, i + 3
            elif line.startswith("/*", i):
                in_block, i = True, i + 2
            elif line.startswith("//", i):
                i = len(line)
            elif line[i] == '"':
                m = re.match(r'"(?:[^"\\]|\\.)*"', line[i:])
                i += len(m.group(0)) if m else len(line)
            else:
                code.append(line[i])
                i += 1
        out.append("".join(code))
    return out


def debug_flags(lines: list[str]) -> list[bool]:
    """For each line, whether it sits inside the `#if` branch of a condition naming DEBUG."""
    stack: list[bool] = []  # per open #if: is this branch DEBUG-only?
    flags = []
    for raw in lines:
        s = raw.strip()
        if s.startswith("#if"):
            stack.append(bool(re.match(r"#if\s+DEBUG\b", s)))
            flags.append(any(stack))
            continue
        if s.startswith("#elseif") or s.startswith("#else"):
            if stack:
                stack[-1] = False
            flags.append(any(stack))
            continue
        if s.startswith("#endif"):
            flags.append(any(stack))
            if stack:
                stack.pop()
            continue
        flags.append(any(stack))
    return flags


def scan(files: dict[str, str]) -> list[str]:
    debug_only: dict[str, str] = {}
    everywhere: set[str] = set()
    parsed = {}
    for name, text in files.items():
        raw = text.splitlines()
        flags = debug_flags(raw)
        lines = code_only(raw)
        parsed[name] = (lines, flags)
        for line, in_debug in zip(lines, flags):
            if line[:1].isspace():  # top level only
                continue
            m = DECL.match(line)
            if not m:
                continue
            (debug_only.setdefault(m.group(1), name) if in_debug else everywhere.add(m.group(1)))
    names = {n: f for n, f in debug_only.items() if n not in everywhere and len(n) > 3}
    if not names:
        return []
    pattern = re.compile(r"\b(" + "|".join(map(re.escape, sorted(names))) + r")\b")
    problems = []
    for name, (lines, flags) in parsed.items():
        for number, (line, in_debug) in enumerate(zip(lines, flags), start=1):
            if in_debug:
                continue
            for m in pattern.finditer(line):
                problems.append(f"{name}:{number}: '{m.group(1)}' is declared only under #if DEBUG "
                                f"({names[m.group(1)]}); wrap this use in #if DEBUG")
    return problems


def self_test() -> int:
    support = "#if DEBUG\nstruct AccountHarness {}\nfunc makeRig() {}\n#endif\n"
    good = ("#if DEBUG\nlet h = AccountHarness()\n#endif\n// AccountHarness in a comment\nlet s = \"AccountHarness\"\n"
            "let m = \"\"\"\n  see AccountHarness.make\n  \"\"\"\n/* AccountHarness */\n")
    bad = "import XCTest\nfunc test() { let h = AccountHarness(); makeRig() }\n"
    elsewhere = "struct Shared {}\n"
    cases = [
        ({"S.swift": support, "G.swift": good, "E.swift": elsewhere}, 0),
        ({"S.swift": support, "B.swift": bad}, 2),
        ({"S.swift": "#if DEBUG\nstruct Shared {}\n#else\nstruct Other {}\n#endif\n", "E.swift": elsewhere,
          "U.swift": "let x = Shared(); let y = Other()\n"}, 0),
    ]
    for files, expected in cases:
        got = len(scan(files))
        if got != expected:
            print(f"SELF-TEST FAIL: expected {expected} problems, got {got}: {scan(files)}")
            return 1
    print("SELF-TEST PASS (3 cases)")
    return 0


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()
    root = Path(next((a for a in argv[1:] if not a.startswith("-")), "."))
    problems, count = [], 0
    for d in TEST_DIRS:  # one module per directory: a target sees only its own DEBUG-only names
        files = {str(p.relative_to(root)): p.read_text(encoding="utf-8") for p in sorted((root / d).rglob("*.swift"))}
        count += len(files)
        problems += scan(files)
    for p in problems:
        print(p)
    print(f"DEBUG-ONLY TEST SYMBOLS | {'FAIL' if problems else 'PASS'} | {count} test files, {len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
