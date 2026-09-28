#!/usr/bin/env python3
"""Fail when a SwiftUI `body` computes instead of rendering (perf-app-runtime.md §3 item 4).

Inside every `var body: some View { ... }` (and `func body(content:)` of a ViewModifier) under
packages/TallyAppleKit/Sources/TallyFeatures, these are banned: `Date()`, `Date.now`,
`Calendar.current`, `TimeZone.current`, `.sorted(`, `.sorted {`, `.filter(`, `.filter {` and
`.build(`. The current time comes from a projection or a `TimelineView` context; sorting,
filtering and projection happen off the main actor, in `HomeProjector`.

An exception needs a line in scripts/ci/view-body-allowlist.txt: `<path>:<pattern>  # reason`.

    python3 scripts/ci/check_view_bodies.py [ROOT]

Exit 0 when clean, 1 when a banned pattern is found (each printed as path:line: pattern).
`--self-test` checks the scanner on inline samples (strings and comments are skipped).
"""
from __future__ import annotations

import pathlib
import re
import sys

BANNED = [
    ("Date()", re.compile(r"\bDate\(\)")),
    ("Date.now", re.compile(r"\bDate\.now\b")),
    ("Calendar.current", re.compile(r"\bCalendar\.current\b")),
    ("TimeZone.current", re.compile(r"\bTimeZone\.current\b")),
    (".sorted", re.compile(r"\.sorted\s*[({]")),
    (".filter", re.compile(r"\.filter\s*[({]")),
    (".build(", re.compile(r"\.build\(")),
]
BODY_START = re.compile(r"\b(var\s+body\s*:\s*some\s+View|func\s+body\s*\(\s*content\s*:[^)]*\)\s*->\s*some\s+View)\s*\{")
FEATURES = "packages/TallyAppleKit/Sources/TallyFeatures"
ALLOWLIST = "scripts/ci/view-body-allowlist.txt"


def code_mask(text: str) -> str:
    """`text` with string literals and comments replaced by spaces (newlines kept), so brace
    matching and pattern search only ever see code."""
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            out[i:j] = " " * (j - i)
            i = j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out[i:j] = [c if c == "\n" else " " for c in text[i:j]]
            i = j
        elif text.startswith('"""', i):
            j = text.find('"""', i + 3)
            j = n if j < 0 else j + 3
            out[i:j] = [c if c == "\n" else " " for c in text[i:j]]
            i = j
        elif text[i] == '"':
            # A single-line string: mask its text, but keep `\( ... )` interpolations as code.
            out[i] = " "
            j, depth = i + 1, 0
            while j < n and text[j] != "\n":
                if depth == 0:
                    if text[j] == "\\" and j + 1 < n and text[j + 1] == "(":
                        out[j] = out[j + 1] = " "
                        depth, j = 1, j + 2
                        continue
                    if text[j] == "\\":
                        out[j] = " "
                        if j + 1 < n:
                            out[j + 1] = " "
                        j += 2
                        continue
                    if text[j] == '"':
                        out[j] = " "
                        break
                    out[j] = " "
                else:
                    if text[j] == "(":
                        depth += 1
                    elif text[j] == ")":
                        depth -= 1
                        if depth == 0:
                            out[j] = " "
                j += 1
            i = j + 1
        else:
            i += 1
    return "".join(out)


def body_ranges(masked: str) -> list[tuple[int, int]]:
    ranges = []
    for match in BODY_START.finditer(masked):
        depth, i = 1, match.end()
        while i < len(masked) and depth:
            if masked[i] == "{":
                depth += 1
            elif masked[i] == "}":
                depth -= 1
            i += 1
        ranges.append((match.end(), i))
    return ranges


def scan(path: str, text: str) -> list[tuple[str, int, str]]:
    masked = code_mask(text)
    hits = []
    for start, end in body_ranges(masked):
        segment = masked[start:end]
        for name, pattern in BANNED:
            for m in pattern.finditer(segment):
                line = masked.count("\n", 0, start + m.start()) + 1
                hits.append((path, line, name))
    return hits


def load_allowlist(root: pathlib.Path) -> set[tuple[str, str]]:
    allowed = set()
    file = root / ALLOWLIST
    if file.exists():
        for raw in file.read_text().splitlines():
            entry = raw.split("#", 1)[0].strip()
            if entry:
                path, _, name = entry.rpartition(":")
                allowed.add((path, name))
    return allowed


def self_test() -> int:
    sample = '''
    struct A: View {
        var body: some View {
            Text("Date() in a string is fine") // .sorted( in a comment is fine
            List(items.sorted { $0 < $1 }) { Text($0) }
        }
        func helper() -> [Int] { items.filter { $0 > 0 } }
    }
    struct B: ViewModifier {
        func body(content: Content) -> some View {
            content.overlay { Text("\\(Date())") }
        }
    }
    '''
    hits = scan("x.swift", sample)
    names = sorted(name for _, _, name in hits)
    assert names == [".sorted", "Date()"], hits  # the helper's filter is outside any body
    assert scan("y.swift", 'var body: some View { Text("a") }') == []
    print("check_view_bodies self-test: 3 checks passed")
    return 0


def main(argv: list[str]) -> int:
    if argv[1:] == ["--self-test"]:
        return self_test()
    root = pathlib.Path(argv[1] if len(argv) > 1 else ".")
    allowed = load_allowlist(root)
    hits = []
    for file in sorted((root / FEATURES).rglob("*.swift")):
        rel = str(file.relative_to(root))
        hits += [h for h in scan(rel, file.read_text()) if (h[0], h[2]) not in allowed]
    for path, line, name in hits:
        print(f"{path}:{line}: `{name}` inside a view body (perf-app-runtime.md §3 item 4)")
    if hits:
        print(f"::error::{len(hits)} banned computation(s) inside view bodies")
        return 1
    print("view bodies: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
