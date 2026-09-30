#!/usr/bin/env python3
"""Plan 08 §3.8 (L10N-01): no new hard-coded user-facing text; existing text burns down.

Every string a user reads goes through `TallyStrings` (`L10n.*`, backed by its String Catalog),
so each one can be translated. This scans the shipping Swift sources for string literals that
look like user-facing English and compares the count per file with a committed ratchet baseline
(`scripts/ci/l10n-baseline.json`): a file above its baseline, or a new file with any finding,
fails. The existing literals are debt that L10N-03a/03b burn down to zero, after which the
baseline file is deleted and the gate becomes "zero findings".

What counts as a finding (comments are ignored; each literal counts once):
  ui-api  A literal containing a letter passed straight to a SwiftUI text API: Text(, Label(,
          Button(, Section(, Toggle(, Picker(, LabeledContent(, ContentUnavailableView(,
          TextField(, SecureField(, Link(, Menu(, NavigationLink(, Stepper(, DatePicker(,
          ProgressView(, Gauge(, .navigationTitle(, .accessibilityLabel(, .accessibilityHint(,
          .accessibilityValue(, .help(, .badge(, .alert(, .confirmationDialog(,
          .configurationDisplayName(, .description( (widgets), ScreenSectionHeader(title:.
  text    Any other literal that reads as words: after removing interpolations and format
          specifiers it contains whitespace and a word of two or more letters ("Due soon",
          "Was due \\(day)", " percent"). Identifiers, keys, URLs and single tokens do not.

Allowed (not findings): `Text(verbatim:)`, `systemImage:`/`systemName:`/`image:` and other
identifier arguments, `.accessibilityIdentifier(`, logging and signposts (`logger.*(`,
`Logger(`, `os_log(`, `*Signpost*`), `fatalError`/`precondition`/`assert*`, `Notification.Name(`,
`URL(string:`, `#Preview` blocks, code compiled only under `#if DEBUG`, the `TallyStrings`
target itself (the one allowed source), tests and test support. A literal can be exempted with
`// l10n-exempt: <reason>` on its line or the line above; the reason is required.

    python3 scripts/ci/check_localizable_literals.py [ROOT]            check against the baseline
    python3 scripts/ci/check_localizable_literals.py --list [ROOT]     print every finding
    python3 scripts/ci/check_localizable_literals.py --update [ROOT]   rewrite the baseline
    python3 scripts/ci/check_localizable_literals.py --self-test

Exit 0 when no file is above its baseline, 1 when one is, 2 when an input is missing or
unreadable (never a silent pass).
"""
from __future__ import annotations

import json
import pathlib
import re
import sys
from dataclasses import dataclass

BASELINE = "scripts/ci/l10n-baseline.json"
# The shipping Swift sources that can hold user-facing text. TallyDomain builds English sentences
# today (notifications, Next-up reasons, attention rows); L10N-02 moves them out.
SCAN_ROOTS = (
    "packages/TallyAppleKit/Sources",
    "apps/TallyiOS/Tally",
    "apps/TallyiOS/TallyWidgets",
    "packages/TallyCore/Sources/TallyDomain",
)
# The one allowed source of UI strings.
EXCLUDED_DIRS = ("packages/TallyAppleKit/Sources/TallyStrings",)

UI_CALLEES = {
    "Text", "Label", "Button", "Section", "Toggle", "Picker", "LabeledContent", "ContentUnavailableView",
    "TextField", "SecureField", "Link", "Menu", "NavigationLink", "Stepper", "DatePicker", "ProgressView",
    "Gauge",
}
UI_MODIFIERS = {
    "navigationTitle", "accessibilityLabel", "accessibilityHint", "accessibilityValue", "help", "badge",
    "alert", "confirmationDialog", "configurationDisplayName", "description",
}
# (callee, label): a labelled argument that is user-facing text.
UI_LABELLED = {("ScreenSectionHeader", "title")}
# Argument labels whose literal is an identifier, a resource name or a translator comment, never
# shown as text.
IDENTIFIER_LABELS = {
    "verbatim", "systemImage", "systemName", "image", "imageName", "named", "id", "identifier",
    "forKey", "key", "bundle", "table", "tableName", "subsystem", "category", "kind", "comment",
    "path", "component", "debugDescription",
}
# A keyed catalog lookup, `LocalizedStringResource("key", defaultValue: "…")` or
# `String(localized: "key", defaultValue: "…")`: its English fallback is catalog text, not a
# hard-coded literal. check_string_catalogs.py checks that the key is in the catalog of the same
# bundle (TallyStrings, or the widget's own catalog), so this is no way around TallyStrings.
CATALOG_LOOKUPS = {"LocalizedStringResource", "String"}
# Calls whose literal arguments are never shown to a user: a callee name, or any component of a
# dotted callee chain, matching this.
EXEMPT_CALLEE = re.compile(
    r"^(accessibilityIdentifier|fatalError|precondition|preconditionFailure|assert|assertionFailure|"
    r"os_log|NSLog|print|debugPrint|Logger|OSSignposter|NSPredicate|Selector|UUID|appendingPathComponent)$"
    r"|(?i:^logger$|^log$|signpost)"
)
EXEMPT_QUALIFIED = re.compile(r"(^|\.)(Notification\.Name|URL|Image|UIImage|Color|UIColor|Font)$")
EXEMPTION = re.compile(r"//\s*l10n-exempt\b(:?)\s*(.*)$")
FORMAT_SPECIFIER = re.compile(r"%(?:\d+\$)?[-+ #0']*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|q|L|z|t|j)?[@a-zA-Z%]")
WORD = re.compile(r"[A-Za-z][A-Za-z'’]+")
INTERPOLATION = "\x00"


@dataclass
class Literal:
    start: int  # offset of the opening delimiter (the first # of a raw string)
    end: int  # offset just past the closing delimiter
    text: str  # the literal's static text; each interpolation is one INTERPOLATION character
    line: int


@dataclass
class Finding:
    path: str
    line: int
    rule: str
    text: str

    def render(self) -> str:
        shown = self.text.replace(INTERPOLATION, "\\(…)").replace("\n", "\\n")
        return f"{self.path}:{self.line}: {self.rule}: \"{shown[:80]}\""


# ------------------------------------------------------------------------------------------------
# Lexing: string literals (with interpolations, raw and multiline forms) and comments
# ------------------------------------------------------------------------------------------------

def lex(text: str) -> tuple[list[Literal], str]:
    """The top-level string literals of `text`, and a copy of `text` with every comment and every
    literal (interpolations included) blanked to spaces, newlines kept, for structural scans."""
    literals: list[Literal] = []
    skeleton = list(text)
    i, n = 0, len(text)

    def blank(start: int, end: int) -> None:
        for k in range(start, end):
            if skeleton[k] != "\n":
                skeleton[k] = " "

    while i < n:
        comment_end = _comment_end(text, i)
        if comment_end is not None:
            blank(i, comment_end)
            i = comment_end
            continue
        opened = _string_open(text, i)
        if opened is not None:
            end, static = _string_body(text, *opened)
            literals.append(Literal(i, end, static, text.count("\n", 0, i) + 1))
            blank(i, end)
            i = end
            continue
        i += 1
    return literals, "".join(skeleton)


def _comment_end(text: str, i: int) -> int | None:
    if text.startswith("//", i):
        j = text.find("\n", i)
        return len(text) if j < 0 else j
    if text.startswith("/*", i):
        depth, j = 1, i + 2
        while j < len(text) and depth:  # Swift block comments nest
            if text.startswith("/*", j):
                depth, j = depth + 1, j + 2
            elif text.startswith("*/", j):
                depth, j = depth - 1, j + 2
            else:
                j += 1
        return j
    return None


def _string_open(text: str, i: int) -> tuple[int, int, bool] | None:
    """(offset of the body, raw-delimiter count, multiline) when a string literal starts at `i`."""
    hashes = 0
    while i + hashes < len(text) and text[i + hashes] == "#":
        hashes += 1
    j = i + hashes
    if j >= len(text) or text[j] != '"':
        return None
    if hashes and i > 0 and (text[i - 1].isalnum() or text[i - 1] == "_"):
        return None
    if text.startswith('"""', j):
        return j + 3, hashes, True
    return j + 1, hashes, False


def _string_body(text: str, start: int, hashes: int, multiline: bool) -> tuple[int, str]:
    """(offset just past the literal, its static text) for a body starting at `start`."""
    close = ('"""' if multiline else '"') + "#" * hashes
    escape = "\\" + "#" * hashes
    static: list[str] = []
    i, n = start, len(text)
    while i < n:
        if text.startswith(close, i):
            return i + len(close), "".join(static)
        if not multiline and text[i] == "\n":
            return i, "".join(static)  # unterminated: stop at the line end
        if text.startswith(escape, i):
            k = i + len(escape)
            if k < n and text[k] == "(":
                i = _interpolation_end(text, k)
                static.append(INTERPOLATION)
                continue
            unicode = re.match(r"u\{([0-9A-Fa-f]{1,8})\}", text[k:k + 11])
            if unicode:
                static.append(chr(int(unicode.group(1), 16)))
                i = k + unicode.end()
                continue
            static.append(text[k] if k < n else "")
            i = k + 1
            continue
        static.append(text[i])
        i += 1
    return n, "".join(static)


def _interpolation_end(text: str, open_paren: int) -> int:
    depth, i, n = 0, open_paren, len(text)
    while i < n:
        comment_end = _comment_end(text, i)
        if comment_end is not None:
            i = comment_end
            continue
        opened = _string_open(text, i)
        if opened is not None:
            i, _ = _string_body(text, *opened)
            continue
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return n


# ------------------------------------------------------------------------------------------------
# Regions that never ship or are never shown: #if DEBUG, #Preview
# ------------------------------------------------------------------------------------------------

_DIRECTIVE = re.compile(r"^\s*#(if|elseif|else|endif)\b(.*)$")
# Compilation conditions the shipping Release build never sets: DEBUG, and the UI-test hooks that
# only `make ios-perf`'s Release *test* build sets (ci.yml checks the shipping build has none).
NON_SHIPPING_FLAGS = {"DEBUG", "TALLY_TEST_HOOKS"}


def _non_shipping(condition: str) -> bool:
    """`condition` (spaces removed) holds only in builds that never ship."""
    if condition in NON_SHIPPING_FLAGS:
        return True
    if "||" in condition:
        return all(part in NON_SHIPPING_FLAGS for part in condition.split("||"))
    return bool(re.fullmatch(r"DEBUG&&.+|.+&&DEBUG", condition))


def excluded_lines(skeleton: str) -> set[int]:
    """1-based lines compiled only into DEBUG builds, and the lines of `#Preview` blocks."""
    result: set[int] = set()
    stack: list[list] = []  # [kind, branch]
    for number, line in enumerate(skeleton.split("\n"), start=1):
        m = _DIRECTIVE.match(line)
        if m:
            word, condition = m.group(1), m.group(2).replace(" ", "")
            if word == "if":
                kind = "debug" if _non_shipping(condition) else "release" if condition == "!DEBUG" else "other"
                stack.append([kind, 0])
            elif word in ("elseif", "else") and stack:
                stack[-1][1] += 1
            elif word == "endif" and stack:
                stack.pop()
            continue
        if any((kind == "debug" and branch == 0) or (kind == "release" and branch > 0) for kind, branch in stack):
            result.add(number)
    for m in re.finditer(r"#Preview\b", skeleton):
        brace = skeleton.find("{", m.end())
        if brace < 0:
            continue
        end = _matching(skeleton, brace, "{", "}")
        first = skeleton.count("\n", 0, m.start()) + 1
        last = skeleton.count("\n", 0, end) + 1
        result.update(range(first, last + 1))
    return result


def _matching(text: str, start: int, open_char: str, close_char: str) -> int:
    depth = 0
    for i in range(start, len(text)):
        if text[i] == open_char:
            depth += 1
        elif text[i] == close_char:
            depth -= 1
            if depth == 0:
                return i
    return len(text)


# ------------------------------------------------------------------------------------------------
# Classifying a literal by where it sits
# ------------------------------------------------------------------------------------------------

@dataclass
class Context:
    callee: str  # e.g. "Text", ".navigationTitle", "Self.logger.info"; "" outside any call
    label: str  # the argument label, "" if none


def context_of(skeleton: str, position: int) -> list[Context]:
    """The enclosing calls of the literal at `position`, innermost first (up to three levels)."""
    contexts: list[Context] = []
    pos = position
    for _ in range(3):
        depth, i, argument_start = 0, pos - 1, None
        while i >= 0:
            ch = skeleton[i]
            if ch in ")]}":
                depth += 1
            elif ch in "([{":
                if depth == 0:
                    break
                depth -= 1
            elif ch == "," and depth == 0 and argument_start is None:
                argument_start = i + 1
            i -= 1
        if i < 0 or skeleton[i] == "{":
            break
        argument = skeleton[(argument_start if argument_start is not None else i + 1):position]
        label_match = re.match(r"\s*([A-Za-z_]\w*)\s*:", argument)
        label = label_match.group(1) if label_match else ""
        if skeleton[i] == "(":
            callee_match = re.search(r"((?:[A-Za-z_#.][\w.]*)?[A-Za-z_]\w*)\s*(<[^()]*>)?\s*$", skeleton[:i])
            callee = callee_match.group(1) if callee_match else ""
            if callee_match and skeleton[:callee_match.start()].rstrip().endswith("."):
                callee = "." + callee
        else:
            callee = "["
        contexts.append(Context(callee, label))
        pos = i
        position = i
    return contexts


def _callee_name(callee: str) -> str:
    return callee.rsplit(".", 1)[-1]


def is_exempt_context(contexts: list[Context]) -> bool:
    for ctx in contexts:
        parts = [p for p in ctx.callee.split(".") if p]
        if any(EXEMPT_CALLEE.search(p) for p in parts) or EXEMPT_QUALIFIED.search(ctx.callee.lstrip(".")):
            return True
    if contexts and contexts[0].label in IDENTIFIER_LABELS:
        return True
    if contexts and contexts[0].label == "defaultValue" and _callee_name(contexts[0].callee) in CATALOG_LOOKUPS:
        return True
    return False


def is_ui_argument(contexts: list[Context]) -> bool:
    if not contexts:
        return False
    ctx = contexts[0]
    name = _callee_name(ctx.callee)
    if (name, ctx.label) in UI_LABELLED:
        return True
    if "." in ctx.callee:
        # `.navigationTitle(`, `view.help(`, or a qualified `SwiftUI.Text(`.
        parts = [p for p in ctx.callee.split(".") if p]
        return name in UI_MODIFIERS or (name in UI_CALLEES and parts[-2:-1] == ["SwiftUI"])
    return name in UI_CALLEES


def reads_as_words(static: str) -> bool:
    plain = FORMAT_SPECIFIER.sub(" ", static.replace(INTERPOLATION, " "))
    if "://" in plain:
        return False
    return bool(re.search(r"\s", static.replace(INTERPOLATION, ""))) and bool(WORD.search(plain))


def scan_file(path: str, text: str) -> tuple[list[Finding], list[str]]:
    """The findings in one file, and problems with its exemption comments."""
    literals, skeleton = lex(text)
    excluded = excluded_lines(skeleton)
    lines = text.split("\n")
    findings: list[Finding] = []
    problems: list[str] = []
    for literal in literals:
        if literal.line in excluded:
            continue
        exempt = False
        for number in (literal.line, literal.line - 1):
            if not 1 <= number <= len(lines):
                continue
            line = lines[number - 1]
            if number != literal.line and not line.lstrip().startswith("//"):
                continue  # the line above counts only when it is a comment line of its own
            m = EXEMPTION.search(line)
            if m:
                if m.group(1) and m.group(2).strip():
                    exempt = True
                else:
                    problem = f"{path}:{number}: `// l10n-exempt` needs a reason: `// l10n-exempt: <reason>`"
                    if problem not in problems:
                        problems.append(problem)
        if exempt:
            continue
        if not re.search(r"[A-Za-z]", literal.text):
            continue
        contexts = context_of(skeleton, literal.start)
        if is_exempt_context(contexts):
            continue
        if is_ui_argument(contexts):
            findings.append(Finding(path, literal.line, "ui-api", literal.text))
        elif reads_as_words(literal.text):
            findings.append(Finding(path, literal.line, "text", literal.text))
    return findings, problems


# ------------------------------------------------------------------------------------------------
# The repository, the baseline and the ratchet
# ------------------------------------------------------------------------------------------------

class InputError(Exception):
    """An input could not be read: exit 2, never a silent pass."""


def is_scanned(relative: str) -> bool:
    if any(relative == d or relative.startswith(d + "/") for d in EXCLUDED_DIRS):
        return False
    parts = relative.split("/")
    return not any(p.startswith(".build") or "Tests" in p or p == "TallyTestSupport" for p in parts)


def collect(root: pathlib.Path) -> dict[str, str]:
    files: dict[str, str] = {}
    for directory in SCAN_ROOTS:
        base = root / directory
        if not base.is_dir():
            raise InputError(f"{directory} does not exist under {root}")
        for swift in sorted(base.rglob("*.swift")):
            relative = swift.relative_to(root).as_posix()
            if is_scanned(relative):
                try:
                    files[relative] = swift.read_text(encoding="utf-8")
                except (OSError, UnicodeDecodeError) as error:
                    raise InputError(f"cannot read {relative}: {error}") from error
    if not files:
        raise InputError("no Swift sources found")
    return files


def scan(files: dict[str, str]) -> tuple[dict[str, list[Finding]], list[str]]:
    by_file: dict[str, list[Finding]] = {}
    problems: list[str] = []
    for path, text in sorted(files.items()):
        findings, file_problems = scan_file(path, text)
        if findings:
            by_file[path] = findings
        problems += file_problems
    return by_file, problems


def load_baseline(path: pathlib.Path) -> dict[str, int]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise InputError(f"cannot read the baseline {path}: {error}") from error
    counts = data.get("files") if isinstance(data, dict) else None
    if not isinstance(counts, dict) or not all(isinstance(v, int) and v >= 0 for v in counts.values()):
        raise InputError(f"{path}: expected {{\"files\": {{path: count}}}}")
    return counts


def baseline_json(by_file: dict[str, list[Finding]]) -> str:
    data = {
        "comment": "Plan 08 L10N-01 ratchet: hard-coded user-facing literals per file "
                   "(scripts/ci/check_localizable_literals.py). A file may not go above its count and a new "
                   "file must have none; L10N-03a/03b burn these down to zero, then this file is deleted. "
                   "Regenerate with --update after removing literals.",
        "files": {path: len(findings) for path, findings in sorted(by_file.items())},
    }
    return json.dumps(data, indent=2, sort_keys=True) + "\n"


def compare(by_file: dict[str, list[Finding]], baseline: dict[str, int]) -> tuple[list[str], list[str]]:
    """(failures, notices). A file above its baseline (or new, with findings) fails; a file below
    it, or a baseline entry for a file with none, is a notice that the baseline can be lowered."""
    failures: list[str] = []
    notices: list[str] = []
    for path, findings in sorted(by_file.items()):
        allowed = baseline.get(path, 0)
        if len(findings) > allowed:
            what = "a new file" if path not in baseline else f"baseline {allowed}"
            failures.append(f"{path}: {len(findings)} hard-coded literals ({what}); use L10n (TallyStrings), "
                            f"or `// l10n-exempt: <reason>` for text that is never shown:")
            failures += [f"    {finding.render()}" for finding in findings]
        elif len(findings) < allowed:
            notices.append(f"{path}: {len(findings)} literals, baseline {allowed}: lower it (--update)")
    for path, allowed in sorted(baseline.items()):
        if path not in by_file and allowed:
            notices.append(f"{path}: 0 literals, baseline {allowed}: lower it (--update)")
    return failures, notices


def run(root: pathlib.Path, mode: str) -> int:
    try:
        files = collect(root)
        by_file, problems = scan(files)
        if mode == "update":
            (root / BASELINE).write_text(baseline_json(by_file), encoding="utf-8")
            print(f"L10N | baseline written | {BASELINE} | {sum(map(len, by_file.values()))} literals "
                  f"in {len(by_file)} files")
            return 0
        if mode == "list":
            for findings in by_file.values():
                for finding in findings:
                    print(f"L10N | {finding.render()}")
            print(f"L10N | {sum(map(len, by_file.values()))} literals in {len(by_file)} of {len(files)} files")
            return 0
        baseline = load_baseline(root / BASELINE)
    except InputError as error:
        print(f"L10N | ERROR | input | {error}")
        return 2
    failures, notices = compare(by_file, baseline)
    failures = [f"exemption: {p}" for p in problems] + failures
    for line in failures:
        print(f"L10N | FAIL | {line}" if not line.startswith("    ") else f"L10N |      {line}")
    for notice in notices:
        print(f"L10N | notice | {notice}")
    total = sum(map(len, by_file.values()))
    print(f"L10N | {'FAIL' if failures else 'PASS'} | {len(files)} Swift files, {total} literals in {len(by_file)} files, "
          f"baseline {sum(baseline.values())} in {len(baseline)} files")
    return 1 if failures else 0


# ------------------------------------------------------------------------------------------------
# Self-test
# ------------------------------------------------------------------------------------------------

def self_test() -> int:
    checks = 0

    def expect(condition: bool, message: str) -> None:
        nonlocal checks
        checks += 1
        assert condition, message

    def found(source: str) -> list[tuple[str, str]]:
        findings, _ = scan_file("a.swift", source)
        return [(f.rule, f.text.replace(INTERPOLATION, "{}")) for f in findings]

    # The lexer: interpolations with nested strings, raw and multiline strings, comments.
    literals, skeleton = lex('let a = "x\\(f("y", "z") ? "p" : "q")w" // "c"\nlet b = #"r"\\(no)"#\n')
    expect([lit.text for lit in literals] == ["x" + INTERPOLATION + "w", 'r"\\(no)'], [lit.text for lit in literals])
    expect('"' not in skeleton and "c" not in skeleton.split("//")[-1], skeleton)
    literals, _ = lex('let m = """\n  Two words \\(x)\n  """\nlet r = #"a \\#(b) c"#\n/* "not" /* "nested" */ */')
    expect([lit.text for lit in literals] == ["\n  Two words " + INTERPOLATION + "\n  ", "a " + INTERPOLATION + " c"],
           [lit.text for lit in literals])

    # ui-api: letters passed to a text API, including single words and interpolations.
    expect(found('Text("New literal")') == [("ui-api", "New literal")], found('Text("New literal")'))
    expect(found('.navigationTitle("Dashboard")') == [("ui-api", "Dashboard")], "modifier")
    expect(found('Button("Done") { dismiss() }') == [("ui-api", "Done")], "button")
    expect(found('Text("Good \\(greeting), \\(name)")') == [("ui-api", "Good {}, {}")], "interpolated")
    expect(found('Label("Refresh", systemImage: "arrow.clockwise")') == [("ui-api", "Refresh")], "label")
    expect(found('ScreenSectionHeader(title: "Due soon")') == [("ui-api", "Due soon")], "section header")
    expect(found('Text(isOn ? "On" : "Off")') == [("ui-api", "On"), ("ui-api", "Off")], "ternary")
    expect(found('.configurationDisplayName("Next Up")') == [("ui-api", "Next Up")], "widget name")
    # text: other literals that read as words, in any context.
    expect(found('let reason = "Due soon"') == [("text", "Due soon")], "assignment")
    expect(found('return "Was due \\(day)"') == [("text", "Was due {}")], "fragment")
    expect(found('spoken += " minus"') == [("text", " minus")], "leading space")
    expect(found('let s = "\\(count) change\\(count == 1 ? "" : "s") since \\(time)"') ==
           [("text", "{} change{} since {}")], "nested strings count once")
    # Not findings.
    for clean in ('Text(verbatim: course.name)', 'Text(verbatim: "Tally")', 'Image(systemName: "house")',
                  'Label { Text(title) } icon: { Image(systemName: "clock") }',
                  '.accessibilityIdentifier("dashboard hero")', 'logger.info("refresh failed \\(error)")',
                  'Self.logger.error("could not open the store")', 'Logger(subsystem: "dev.tally", category: "ui")',
                  'precondition(x > 0, "x must be positive")', 'fatalError("never happens here")',
                  'let url = URL(string: "https://example.test/a b")', 'let key = "dashboard.hero.average"',
                  'let id = "refresh-\\(account)"', 'Text("00.0%")', 'Text("—")', 'let f = "%@ %@"',
                  'Text(L10n.Dashboard.averageOfCourses(n))', '// Text("in a comment")',
                  'LaunchSignpost.begin("glance paint")', 'let n = Notification.Name("tally did refresh")',
                  'Text("Two words") // l10n-exempt: a test fixture title, never shown',
                  'LocalizedStringResource("widget.name", defaultValue: "Next Up", comment: "The widget name")',
                  'String(localized: "a.key", defaultValue: "Two words", bundle: #bundle, comment: "Some words")',
                  'Text("Hello", comment: "A greeting shown on launch")'.replace('Text("Hello", ', 'Text(key, ')):
        expect(found(clean) == [], f"{clean!r}: {found(clean)}")
    expect(found('// l10n-exempt: shown only in a debug overlay\nlet s = "Debug only words"') == [], "line above")
    expect(found('let a = "x" // l10n-exempt: an identifier\nlet s = "Two words"') == [("text", "Two words")],
           "a code line's exemption covers that line only")
    expect(found('LocalizedStringResource("Refresh Tally")') == [("text", "Refresh Tally")], "English as the key")
    expect(found('view.accessibilityLabel("Close sheet")') == [("ui-api", "Close sheet")], "chained modifier")
    expect(found('SwiftUI.Text("Qualified")') == [("ui-api", "Qualified")], "qualified")
    expect(found('#if DEBUG\nText("Debug menu")\n#else\nText("Shipped")\n#endif') == [("ui-api", "Shipped")], "debug")
    expect(found('#Preview {\n    Text("Preview words")\n}\nText("After")') == [("ui-api", "After")], "preview")
    expect(found('#if DEBUG || TALLY_TEST_HOOKS\nlet school = "Northfield State"\n#endif') == [], "test hooks")
    expect(found('#if DEBUG || os(iOS)\nlet s = "Ships maybe"\n#endif') == [("text", "Ships maybe")], "maybe shipped")
    expect(found('let s = "Simulation \\u{2014} not real"') == [("text", "Simulation \u2014 not real")], "unicode escape")
    for clean in ('url.appendingPathComponent("Application Support", isDirectory: true)',
                  'throw DecodingError.dataCorruptedError(in: c, debugDescription: "not an integer")'):
        expect(found(clean) == [], f"{clean!r}: {found(clean)}")
    _, problems = scan_file("a.swift", 'Text("Words") // l10n-exempt')
    expect(len(problems) == 1 and "needs a reason" in problems[0], problems)
    expect(found('Text("Words") // l10n-exempt') == [("ui-api", "Words")], "a bare exemption does not exempt")

    # The ratchet: increases and new files fail; decreases and stale entries are notices.
    def findings(path: str, n: int) -> list[Finding]:
        return [Finding(path, k + 1, "ui-api", "x") for k in range(n)]
    failures, notices = compare({"a.swift": findings("a.swift", 2)}, {"a.swift": 2})
    expect(failures == [] and notices == [], "at the baseline")
    failures, _ = compare({"a.swift": findings("a.swift", 3)}, {"a.swift": 2})
    expect(len(failures) == 4 and "baseline 2" in failures[0], failures)
    failures, _ = compare({"new.swift": findings("new.swift", 1)}, {})
    expect(len(failures) == 2 and "a new file" in failures[0], failures)
    failures, notices = compare({"a.swift": findings("a.swift", 1)}, {"a.swift": 2, "gone.swift": 3})
    expect(failures == [] and len(notices) == 2, (failures, notices))
    expect(json.loads(baseline_json({"b.swift": findings("b.swift", 2)}))["files"] == {"b.swift": 2}, "baseline json")

    # The PMO mutation: one new `Text("New literal")` in a file at its baseline fails.
    source = 'struct V: View {\n    var body: some View {\n        Text("Hello there")\n    }\n}\n'
    at_baseline = scan({"V.swift": source})[0]
    mutated = scan({"V.swift": source.replace('Text("Hello there")', 'Text("Hello there")\n        Text("New literal")')})[0]
    failures, _ = compare(mutated, {path: len(f) for path, f in at_baseline.items()})
    expect(any('"New literal"' in line for line in failures), failures)
    # Scope: tests, test support and TallyStrings are never scanned.
    expect(not is_scanned("packages/TallyAppleKit/Sources/TallyStrings/L10n.swift"), "TallyStrings")
    expect(not is_scanned("apps/TallyiOS/TallyAppTests/X.swift"), "tests")
    expect(is_scanned("packages/TallyAppleKit/Sources/TallyFeatures/Dashboard/DashboardView.swift"), "features")
    print(f"check_localizable_literals self-test: {checks} checks passed")
    return 0


def main(argv: list[str]) -> int:
    args = argv[1:]
    if args == ["--self-test"]:
        return self_test()
    mode = "check"
    if args[:1] in (["--list"], ["--update"]):
        mode, args = args[0][2:], args[1:]
    if len(args) > 1 or (args and args[0].startswith("--")):
        print(__doc__)
        return 2
    return run(pathlib.Path(args[0] if args else ".").resolve(), mode)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
