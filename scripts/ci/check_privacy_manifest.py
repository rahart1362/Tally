#!/usr/bin/env python3
"""ASC-03: cross-check each shipping bundle's privacy manifest against the code linked into it.

app-store-compliance.md R2 and §3.3.1: since 2024-05-01 App Store Connect rejects an upload whose
code uses a "required reason" API that the bundle's `PrivacyInfo.xcprivacy` does not declare. Each
bundle needs its own manifest: the app (`apps/TallyiOS/Tally`) and the widget extension
(`apps/TallyiOS/TallyWidgets`).

What it does, for each bundle:
1. Works out which Swift modules are linked into the bundle: the bundle target's own sources, plus
   the transitive closure of the package products it depends on in `apps/TallyiOS/project.yml`,
   read from each package's `Package.swift`. So a new dependency is scanned the day it is added.
   Test targets and `TallyTestSupport` are never shipping code and are not scanned.
2. Scans those sources for Apple's required-reason API symbols (the five categories below), with
   comments and string literals masked out. Code inside `#if DEBUG` is reported but not required
   to be declared: it is not in the Release binary that App Store Connect checks.
3. Checks the bundle's manifest:
   - every category the bundle's shipping code uses is declared, with at least one reason code;
   - every declared reason code is one Apple approves for that category, and none is reserved for
     third-party SDKs;
   - `NSPrivacyTracking` is false and `NSPrivacyTrackingDomains` is empty;
   - `NSPrivacyCollectedDataTypes` matches the privacy policy: the policy
     (`site/privacy/index.html`) says nothing is collected, so the list must be empty. If the
     policy stops saying so, this check fails until the two are updated together.
   A declared category that no shipping code uses is a warning (accurate, not required).

Reason codes and API lists: Apple, "NSPrivacyAccessedAPIType" and "Describing use of required
reason API" (developer.apple.com, Bundle Resources), read 2026-09-28 from the pages' JSON.

    python3 scripts/ci/check_privacy_manifest.py [ROOT] [--json OUT]
    python3 scripts/ci/check_privacy_manifest.py --self-test

Exit 0 when every check passes (warnings allowed), 1 when a check fails, 2 when an input cannot be
read or parsed (a missing input never passes silently). `--json OUT` also writes every check and
every API use found, for the release gate's compliance report (ASC-10).
"""
from __future__ import annotations

import json
import pathlib
import plistlib
import re
import sys
from dataclasses import dataclass, field

# ------------------------------------------------------------------------------------------------
# Apple's required-reason API categories: the approved reason codes and the API symbols.
# ------------------------------------------------------------------------------------------------

FILE_TIMESTAMP = "NSPrivacyAccessedAPICategoryFileTimestamp"
SYSTEM_BOOT_TIME = "NSPrivacyAccessedAPICategorySystemBootTime"
DISK_SPACE = "NSPrivacyAccessedAPICategoryDiskSpace"
ACTIVE_KEYBOARDS = "NSPrivacyAccessedAPICategoryActiveKeyboards"
USER_DEFAULTS = "NSPrivacyAccessedAPICategoryUserDefaults"

APPROVED_REASONS = {
    FILE_TIMESTAMP: {"DDA9.1", "C617.1", "3B52.1", "0A2A.1"},
    SYSTEM_BOOT_TIME: {"35F9.1", "8FFB.1", "3D61.1"},
    DISK_SPACE: {"85F4.1", "E174.1", "7D9E.1", "B728.1"},
    ACTIVE_KEYBOARDS: {"3EC4.1", "54BD.1"},
    USER_DEFAULTS: {"CA92.1", "1C8F.1", "C56D.1", "AC6B.1"},
}
# "This reason may only be declared by third-party SDKs." An app or extension may not use these.
SDK_ONLY_REASONS = {"0A2A.1", "C56D.1"}


def _symbols(*names: str) -> list[tuple[str, re.Pattern[str]]]:
    return [(name, re.compile(pattern)) for name, pattern in names]  # type: ignore[misc]


# Swift spellings of each listed API. A property name such as `creationDate` is matched only as a
# member access (`.creationDate`), which is how `FileAttributeKey` and `URLResourceValues` spell it.
API_SYMBOLS: dict[str, list[tuple[str, re.Pattern[str]]]] = {
    FILE_TIMESTAMP: [
        ("creationDate", re.compile(r"\.creationDate\b")),
        ("modificationDate", re.compile(r"\.modificationDate\b")),
        ("fileModificationDate", re.compile(r"\bfileModificationDate\b")),
        ("contentModificationDate(Key)", re.compile(r"\bcontentModificationDate(Key)?\b")),
        ("creationDateKey", re.compile(r"\bcreationDateKey\b")),
        ("NSFileCreationDate/NSFileModificationDate", re.compile(r"\bNSFile(Creation|Modification)Date\b")),
        ("NSURLCreationDateKey/NSURLContentModificationDateKey",
         re.compile(r"\bNSURL(Creation|ContentModification)DateKey\b")),
        ("getattrlist family", re.compile(r"\bf?getattrlist(bulk|at)?\s*\(")),
        ("stat family", re.compile(r"(?<![\w.])(f?stat|fstatat|lstat)\s*\(")),
    ],
    SYSTEM_BOOT_TIME: [
        ("systemUptime", re.compile(r"\bsystemUptime\b")),
        ("mach_absolute_time", re.compile(r"\bmach_absolute_time\b")),
    ],
    DISK_SPACE: [
        ("volume capacity keys", re.compile(
            r"\bvolume(AvailableCapacity(ForImportantUsage|ForOpportunisticUsage)?|TotalCapacity)Key\b")),
        ("NSURLVolume capacity keys", re.compile(r"\bNSURLVolume(AvailableCapacity\w*|TotalCapacity)Key\b")),
        ("systemFreeSize/systemSize", re.compile(r"\.system(Free)?Size\b")),
        ("NSFileSystemFreeSize/NSFileSystemSize", re.compile(r"\bNSFileSystem(Free)?Size\b")),
        ("statfs/statvfs family", re.compile(r"(?<![\w.])f?statv?fs\s*\(")),
        ("attributesOfFileSystem", re.compile(r"\battributesOfFileSystem\s*\(")),
    ],
    ACTIVE_KEYBOARDS: [
        ("activeInputModes", re.compile(r"\bactiveInputModes\b")),
    ],
    USER_DEFAULTS: [
        ("UserDefaults", re.compile(r"\b(NS)?UserDefaults\b")),
        ("@AppStorage", re.compile(r"@AppStorage\b")),
    ],
}

# ------------------------------------------------------------------------------------------------
# The bundles that ship, their manifests, and where their dependencies are declared.
# ------------------------------------------------------------------------------------------------

PROJECT_YML = "apps/TallyiOS/project.yml"
PRIVACY_POLICY = "site/privacy/index.html"
# The policy's own words for "nothing is collected" (Apple's sense: nothing leaves the device to the
# developer or a partner). Both must still be there for an empty `NSPrivacyCollectedDataTypes`.
POLICY_NO_COLLECTION_CLAIMS = (
    "It is not sent to us or to anyone else",
    "No ads, no analytics, no tracking",
)
EXPECTED_COLLECTED_DATA_TYPES: list = []
# Never shipping code, even though SwiftPM keeps it under Sources/ (plan 06 A1).
EXCLUDED_MODULES = {"TallyTestSupport"}


@dataclass(frozen=True)
class Bundle:
    name: str
    target: str  # the XcodeGen target in project.yml
    manifest: str


BUNDLES = (
    Bundle("app", "Tally", "apps/TallyiOS/Tally/PrivacyInfo.xcprivacy"),
    Bundle("widget", "TallyWidgets", "apps/TallyiOS/TallyWidgets/PrivacyInfo.xcprivacy"),
)


class InputError(Exception):
    """An input could not be read or understood: exit 2, never a silent pass."""


# ------------------------------------------------------------------------------------------------
# Source masking and #if DEBUG regions
# ------------------------------------------------------------------------------------------------

def mask(text: str, keep_strings: bool = False) -> str:
    """`text` with comments (and, unless `keep_strings`, string literals) replaced by spaces.
    Newlines are kept, so offsets and line numbers still match the original."""
    out = list(text)
    i, n = 0, len(text)

    def blank(start: int, end: int) -> None:
        for k in range(start, end):
            if out[k] != "\n":
                out[k] = " "

    while i < n:
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            blank(i, j)
            i = j
        elif text.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:  # Swift block comments nest
                if text.startswith("/*", j):
                    depth, j = depth + 1, j + 2
                elif text.startswith("*/", j):
                    depth, j = depth - 1, j + 2
                else:
                    j += 1
            blank(i, j)
            i = j
        elif text.startswith('"""', i):
            j = text.find('"""', i + 3)
            j = n if j < 0 else j + 3
            if not keep_strings:
                blank(i, j)
            i = j
        elif text[i] == '"':
            j = i + 1
            while j < n and text[j] not in '"\n':
                j += 2 if text[j] == "\\" else 1
            j = min(j + 1, n)
            if not keep_strings:
                blank(i, j)
            i = j
        else:
            i += 1
    return "".join(out)


_DIRECTIVE = re.compile(r"^\s*#(if|elseif|else|endif)\b(.*)$")


def debug_only_lines(masked: str) -> set[int]:
    """1-based line numbers compiled only into DEBUG builds: the first branch of `#if DEBUG` (or of
    a condition that requires DEBUG with `&&`), and the `#else` branch of `#if !DEBUG`. Any other
    condition (`canImport`, `os`, or `DEBUG || X`) may be in a Release build, so it counts."""
    result: set[int] = set()
    stack: list[list] = []  # [kind, branch]; kind in {"debug", "release", "other"}
    for number, line in enumerate(masked.split("\n"), start=1):
        m = _DIRECTIVE.match(line)
        if m:
            word, condition = m.group(1), m.group(2).strip()
            if word == "if":
                stack.append([_condition_kind(condition), 0])
            elif word in ("elseif", "else") and stack:
                stack[-1][1] += 1
            elif word == "endif" and stack:
                stack.pop()
            continue
        for kind, branch in stack:
            if (kind == "debug" and branch == 0) or (kind == "release" and branch > 0):
                result.add(number)
                break
    return result


def _condition_kind(condition: str) -> str:
    compact = condition.replace(" ", "")
    if compact == "DEBUG" or re.fullmatch(r"DEBUG&&.+|.+&&DEBUG", compact) and "||" not in compact:
        return "debug"
    if compact == "!DEBUG":
        return "release"
    return "other"


# ------------------------------------------------------------------------------------------------
# project.yml (the few fields this needs) and Package.swift
# ------------------------------------------------------------------------------------------------

@dataclass
class XcodeTarget:
    name: str
    sources: list[str] = field(default_factory=list)
    # ("package", package, product) or ("target", name)
    dependencies: list[tuple[str, ...]] = field(default_factory=list)


def parse_project(text: str) -> tuple[dict[str, str], dict[str, XcodeTarget]]:
    """`packages:` (name -> path) and `targets:` (sources and dependencies) from an XcodeGen spec.
    A small reader for the block style this repo uses, not a general YAML parser: its self-test
    compares it with PyYAML when PyYAML is installed."""
    packages: dict[str, str] = {}
    targets: dict[str, XcodeTarget] = {}
    section = None
    current: XcodeTarget | None = None
    current_package = None
    list_name = None  # "sources" or "dependencies" inside a target
    pending: dict[str, str] | None = None

    def flush() -> None:
        nonlocal pending
        if pending is None or current is None:
            pending = None
            return
        if list_name == "sources" and "path" in pending:
            current.sources.append(pending["path"])
        elif list_name == "dependencies":
            if "package" in pending:
                current.dependencies.append(("package", pending["package"], pending.get("product", pending["package"])))
            elif "target" in pending:
                current.dependencies.append(("target", pending["target"]))
        pending = None

    for raw in text.split("\n"):
        line = re.sub(r"(^|\s)#.*$", "", raw).rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(" "))
        body = line.strip()
        if indent == 0:
            flush()
            section = body[:-1] if body.endswith(":") else None
            current, current_package, list_name = None, None, None
            continue
        if section == "packages":
            if indent == 2 and body.endswith(":"):
                current_package = body[:-1]
            elif indent == 4 and current_package and body.startswith("path:"):
                packages[current_package] = _scalar(body.split(":", 1)[1])
        elif section == "targets":
            if indent == 2 and body.endswith(":"):
                flush()
                current = targets.setdefault(body[:-1], XcodeTarget(body[:-1]))
                list_name = None
            elif current is not None and indent == 4:
                flush()
                key = body.split(":", 1)[0]
                list_name = key if key in ("sources", "dependencies") and body.endswith(":") else None
            elif current is not None and list_name and indent >= 6:
                item = body
                if item.startswith("- "):
                    flush()
                    pending = {}
                    item = item[2:].strip()
                if pending is None:
                    continue
                if ":" in item:
                    key, value = item.split(":", 1)
                    pending[key.strip()] = _scalar(value)
                else:
                    pending["path"] = _scalar(item)  # `- Tally` shorthand for a source path
    flush()
    return packages, targets


def _scalar(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


@dataclass
class SwiftPackage:
    root: pathlib.Path
    products: dict[str, list[str]] = field(default_factory=dict)
    # target name -> (source dir, [("local", name) | ("product", name, package)], is_test)
    targets: dict[str, tuple[pathlib.Path, list[tuple[str, ...]], bool]] = field(default_factory=dict)
    local_packages: dict[str, pathlib.Path] = field(default_factory=dict)  # identity -> root


def _balanced(text: str, start: int, open_char: str, close_char: str) -> int:
    """Index just past the bracket that closes the one at `start`."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] == open_char:
            depth += 1
        elif text[i] == close_char:
            depth -= 1
            if depth == 0:
                return i + 1
    raise InputError(f"unbalanced {open_char}{close_char} in Package.swift")


def _split_top_level(text: str) -> list[str]:
    parts, depth, start = [], 0, 0
    for i, ch in enumerate(text):
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        elif ch == "," and depth == 0:
            parts.append(text[start:i])
            start = i + 1
    parts.append(text[start:])
    return [p.strip() for p in parts if p.strip()]


def parse_package(root: pathlib.Path) -> SwiftPackage:
    path = root / "Package.swift"
    try:
        text = mask(path.read_text(encoding="utf-8"), keep_strings=True)
    except OSError as error:
        raise InputError(f"cannot read {path}: {error}") from error
    package = SwiftPackage(root=root)
    for m in re.finditer(r"\.package\(\s*path:\s*\"([^\"]+)\"", text):
        dep_root = (root / m.group(1)).resolve()
        package.local_packages[dep_root.name] = dep_root
    for m in re.finditer(r"\.library\(\s*name:\s*\"([^\"]+)\"[^)]*?targets:\s*\[([^\]]*)\]", text, re.S):
        package.products[m.group(1)] = re.findall(r"\"([^\"]+)\"", m.group(2))
    for m in re.finditer(r"\.(target|testTarget|executableTarget)\(", text):
        start = m.end() - 1
        block = text[start:_balanced(text, start, "(", ")")]
        name_match = re.search(r"name:\s*\"([^\"]+)\"", block)
        if not name_match:
            raise InputError(f"a .{m.group(1)} without a name in {path}")
        name = name_match.group(1)
        path_match = re.search(r"\bpath:\s*\"([^\"]+)\"", block)
        source = root / (path_match.group(1) if path_match else f"Sources/{name}")
        deps: list[tuple[str, ...]] = []
        dep_match = re.search(r"dependencies:\s*\[", block)
        if dep_match:
            open_at = dep_match.end() - 1
            inner = block[open_at + 1:_balanced(block, open_at, "[", "]") - 1]
            for entry in _split_top_level(inner):
                if "condition:" in entry and ".iOS" not in entry:
                    continue  # e.g. swift-crypto, Linux only: CryptoKit on iOS
                product = re.match(r"\.product\(\s*name:\s*\"([^\"]+)\"\s*,\s*package:\s*\"([^\"]+)\"", entry)
                target = re.match(r"\.(target|byName)\(\s*name:\s*\"([^\"]+)\"", entry)
                plain = re.fullmatch(r"\"([^\"]+)\"", entry)
                if product:
                    deps.append(("product", product.group(1), product.group(2)))
                elif target:
                    deps.append(("local", target.group(2)))
                elif plain:
                    deps.append(("local", plain.group(1)))
                else:
                    raise InputError(f"unrecognised dependency `{entry}` of {name} in {path}")
        package.targets[name] = (source, deps, m.group(1) == "testTarget")
    return package


def shipping_source_dirs(root: pathlib.Path, bundle: Bundle) -> tuple[list[pathlib.Path], list[str], list[str]]:
    """The directories whose Swift files are linked into `bundle`, the module names, and notes
    (external dependencies that are not scanned)."""
    project_path = root / PROJECT_YML
    try:
        packages_by_name, targets = parse_project(project_path.read_text(encoding="utf-8"))
    except OSError as error:
        raise InputError(f"cannot read {project_path}: {error}") from error
    if bundle.target not in targets:
        raise InputError(f"target {bundle.target} is not in {PROJECT_YML}")
    xcode_target = targets[bundle.target]
    if not xcode_target.sources:
        raise InputError(f"target {bundle.target} lists no sources in {PROJECT_YML}")
    app_dir = project_path.parent
    dirs = [(app_dir / source).resolve() for source in xcode_target.sources]
    modules = [bundle.target]
    notes: list[str] = []
    loaded: dict[pathlib.Path, SwiftPackage] = {}

    def package_at(package_root: pathlib.Path) -> SwiftPackage:
        package_root = package_root.resolve()
        if package_root not in loaded:
            loaded[package_root] = parse_package(package_root)
        return loaded[package_root]

    seen: set[tuple[pathlib.Path, str]] = set()
    queue: list[tuple[SwiftPackage, str]] = []

    def add_product(package: SwiftPackage, product: str) -> None:
        if product not in package.products:
            raise InputError(f"product {product} is not in {package.root / 'Package.swift'}")
        for target_name in package.products[product]:
            queue.append((package, target_name))

    for dependency in xcode_target.dependencies:
        if dependency[0] == "package":
            package_name, product = dependency[1], dependency[2]
            if package_name not in packages_by_name:
                raise InputError(f"{bundle.target} depends on unknown package {package_name}")
            add_product(package_at(app_dir / packages_by_name[package_name]), product)
        # ("target", X): another Xcode target (the embedded widget) is its own bundle; not scanned.
    while queue:
        package, target_name = queue.pop()
        key = (package.root, target_name)
        if key in seen:
            continue
        seen.add(key)
        if target_name not in package.targets:
            if target_name in package.products:  # a local "Name" can be one of the package's products
                add_product(package, target_name)
                continue
            raise InputError(f"target {target_name} is not in {package.root / 'Package.swift'}")
        source, deps, is_test = package.targets[target_name]
        if is_test or target_name in EXCLUDED_MODULES:
            continue
        dirs.append(source.resolve())
        modules.append(target_name)
        for dep in deps:
            if dep[0] == "local":
                queue.append((package, dep[1]))
            else:
                _, product, package_identity = dep
                if package_identity in package.local_packages:
                    add_product(package_at(package.local_packages[package_identity]), product)
                else:
                    notes.append(f"{target_name} -> {package_identity}.{product}: external package, not scanned")
    return dirs, sorted(set(modules)), sorted(set(notes))


# ------------------------------------------------------------------------------------------------
# Scanning and checking
# ------------------------------------------------------------------------------------------------

@dataclass(frozen=True)
class Use:
    category: str
    symbol: str
    path: str
    line: int
    debug_only: bool


def scan_text(path: str, text: str) -> list[Use]:
    masked = mask(text)
    debug = debug_only_lines(masked)
    uses = []
    for category, symbols in API_SYMBOLS.items():
        for name, pattern in symbols:
            for m in pattern.finditer(masked):
                line = masked.count("\n", 0, m.start()) + 1
                uses.append(Use(category, name, path, line, line in debug))
    return sorted(uses, key=lambda u: (u.path, u.line, u.category))


@dataclass
class Check:
    id: str
    level: str  # "ERROR" or "WARN"
    ok: bool
    detail: str


def read_manifest(path: pathlib.Path) -> dict:
    try:
        with path.open("rb") as handle:
            data = plistlib.load(handle)
    except FileNotFoundError:
        return {}
    except (OSError, plistlib.InvalidFileException, ValueError) as error:
        raise InputError(f"cannot parse {path}: {error}") from error
    if not isinstance(data, dict):
        raise InputError(f"{path} is not a property-list dictionary")
    return data


def check_manifest(bundle_name: str, manifest_path: str, manifest: dict, uses: list[Use],
                   policy_ok: bool) -> list[Check]:
    prefix = f"ASC-03.{bundle_name}"
    checks = [Check(f"{prefix}.manifest-present", "ERROR", bool(manifest),
                    f"{manifest_path} {'parses' if manifest else 'is missing'}")]
    if not manifest:
        return checks
    tracking = manifest.get("NSPrivacyTracking")
    checks.append(Check(f"{prefix}.tracking-false", "ERROR", tracking is False,
                        f"NSPrivacyTracking is {tracking!r}; must be false"))
    domains = manifest.get("NSPrivacyTrackingDomains")
    checks.append(Check(f"{prefix}.tracking-domains-empty", "ERROR", domains == [],
                        f"NSPrivacyTrackingDomains is {domains!r}; must be an empty array"))
    collected = manifest.get("NSPrivacyCollectedDataTypes")
    checks.append(Check(
        f"{prefix}.collected-data-matches-policy", "ERROR",
        policy_ok and collected == EXPECTED_COLLECTED_DATA_TYPES,
        f"NSPrivacyCollectedDataTypes is {collected!r}; the privacy policy ({PRIVACY_POLICY}) says "
        f"nothing is collected, so it must be []" + ("" if policy_ok else
        " (and the policy no longer states that: update the policy and this check together)")))

    declared: dict[str, list[str]] = {}
    entries = manifest.get("NSPrivacyAccessedAPITypes")
    shape_ok = isinstance(entries, list)
    problems: list[str] = [] if shape_ok else [f"NSPrivacyAccessedAPITypes is {entries!r}, not an array"]
    for entry in entries if shape_ok else []:
        category = entry.get("NSPrivacyAccessedAPIType") if isinstance(entry, dict) else None
        reasons = entry.get("NSPrivacyAccessedAPITypeReasons") if isinstance(entry, dict) else None
        if category not in APPROVED_REASONS:
            problems.append(f"unknown API category {category!r}")
            continue
        if category in declared:
            problems.append(f"{category} is declared twice")
        if not isinstance(reasons, list) or not reasons:
            problems.append(f"{category} has no reason codes")
            continue
        for code in reasons:
            if code not in APPROVED_REASONS[category]:
                problems.append(f"{code!r} is not an approved reason for {category} "
                                f"(approved: {', '.join(sorted(APPROVED_REASONS[category]))})")
            elif code in SDK_ONLY_REASONS:
                problems.append(f"{code} may only be declared by third-party SDKs, not by an app or extension")
        declared[category] = list(reasons)
    checks.append(Check(f"{prefix}.reasons-approved", "ERROR", not problems,
                        "; ".join(problems) if problems else
                        f"declared: {json.dumps(declared, sort_keys=True) if declared else 'none'}"))

    shipping = [u for u in uses if not u.debug_only]
    for category in APPROVED_REASONS:
        used = [u for u in shipping if u.category == category]
        short = category.removeprefix("NSPrivacyAccessedAPICategory")
        if used:
            where = ", ".join(f"{u.path}:{u.line} ({u.symbol})" for u in used[:5])
            more = f" and {len(used) - 5} more" if len(used) > 5 else ""
            ok = bool(declared.get(category))
            checks.append(Check(f"{prefix}.api.{short}", "ERROR", ok,
                                f"used at {where}{more}; " + ("declared" if ok else
                                f"NOT declared in {manifest_path}: add {category} with an approved reason")))
        elif category in declared:
            checks.append(Check(f"{prefix}.api.{short}", "WARN", False,
                                f"declared in {manifest_path} but no shipping code in this bundle uses it"))
    return checks


def run(root: pathlib.Path) -> tuple[list[Check], dict]:
    report: dict = {"tool": "check_privacy_manifest", "bundles": {}}
    try:
        policy_text = (root / PRIVACY_POLICY).read_text(encoding="utf-8")
    except OSError as error:
        raise InputError(f"cannot read {PRIVACY_POLICY}: {error}") from error
    missing_claims = [claim for claim in POLICY_NO_COLLECTION_CLAIMS if claim not in policy_text]
    checks = [Check("ASC-03.policy.no-collection", "ERROR", not missing_claims,
                    f"{PRIVACY_POLICY} states no data is collected" if not missing_claims else
                    f"{PRIVACY_POLICY} no longer contains: {missing_claims}")]
    for bundle in BUNDLES:
        dirs, modules, notes = shipping_source_dirs(root, bundle)
        uses: list[Use] = []
        files = 0
        for directory in dirs:
            if not directory.is_dir():
                raise InputError(f"source directory {directory} of {bundle.name} does not exist")
            for swift in sorted(directory.rglob("*.swift")):
                files += 1
                relative = swift.relative_to(root).as_posix()
                uses.extend(scan_text(relative, swift.read_text(encoding="utf-8")))
        manifest = read_manifest(root / bundle.manifest)
        checks.extend(check_manifest(bundle.name, bundle.manifest, manifest, uses, not missing_claims))
        report["bundles"][bundle.name] = {
            "manifest": bundle.manifest,
            "modules": modules,
            "swift_files_scanned": files,
            "notes": notes,
            "uses": [u.__dict__ for u in uses],
        }
    report["checks"] = [c.__dict__ for c in checks]
    return checks, report


def print_report(checks: list[Check], report: dict) -> None:
    for name, bundle in report["bundles"].items():
        print(f"{name}: {bundle['swift_files_scanned']} Swift files in {len(bundle['modules'])} modules "
              f"({', '.join(bundle['modules'])})")
        for note in bundle["notes"]:
            print(f"  note: {note}")
        for use in bundle["uses"]:
            if use["debug_only"]:
                print(f"  debug-only (not in Release, not required): {use['path']}:{use['line']} "
                      f"{use['symbol']} [{use['category'].removeprefix('NSPrivacyAccessedAPICategory')}]")
    for check in checks:
        status = "PASS" if check.ok else ("FAIL" if check.level == "ERROR" else "WARN")
        print(f"PRIVACY | {status} | {check.id} | {check.detail}")


# ------------------------------------------------------------------------------------------------
# Self-test
# ------------------------------------------------------------------------------------------------

def self_test() -> int:
    sample = '''
    import Foundation
    // UserDefaults in a comment is fine
    let key = "UserDefaults in a string is fine"
    /* nested /* UserDefaults */ still a comment */
    func a() { let d = UserDefaults.standard }
    #if DEBUG
    func b() { _ = ProcessInfo.processInfo.systemUptime }
    #else
    func c() { _ = mach_absolute_time() }
    #endif
    #if canImport(Darwin)
    func d() { _ = try? url.resourceValues(forKeys: [.contentModificationDateKey]) }
    #endif
    #if !DEBUG
    func e() {}
    #else
    func f() { _ = UIInputViewController().textDocumentProxy; _ = UITextInputMode.activeInputModes }
    #endif
    let attributes = try fm.attributesOfItem(atPath: p)[.modificationDate]
    let notAStat = mystat(x); let s = stat(path, &buffer)
    '''
    uses = scan_text("x.swift", sample)
    got = sorted((u.symbol, u.debug_only) for u in uses)
    want = sorted([
        ("UserDefaults", False),            # a(): the comment, the string and the nested comment do not count
        ("systemUptime", True),             # b(): #if DEBUG
        ("mach_absolute_time", False),      # c(): #else of #if DEBUG ships
        ("contentModificationDate(Key)", False),  # d(): canImport ships
        ("activeInputModes", True),         # f(): #else of #if !DEBUG
        ("modificationDate", False),
        ("stat family", False),             # stat( but not mystat(
    ])
    assert got == want, f"scan: {got} != {want}"
    assert _condition_kind("DEBUG && os(iOS)") == "debug"
    assert _condition_kind("DEBUG || TALLY_UI_TESTING") == "other"

    manifest = {"NSPrivacyTracking": False, "NSPrivacyTrackingDomains": [], "NSPrivacyCollectedDataTypes": [],
                "NSPrivacyAccessedAPITypes": [{"NSPrivacyAccessedAPIType": USER_DEFAULTS,
                                               "NSPrivacyAccessedAPITypeReasons": ["CA92.1"]}]}
    ud = [Use(USER_DEFAULTS, "UserDefaults", "x.swift", 1, False)]
    boot_debug = [Use(SYSTEM_BOOT_TIME, "systemUptime", "x.swift", 2, True)]

    def failed(checks: list[Check]) -> list[str]:
        return [c.id for c in checks if not c.ok and c.level == "ERROR"]

    assert failed(check_manifest("t", "m", manifest, ud + boot_debug, True)) == [], "declared use must pass"
    assert failed(check_manifest("t", "m", dict(manifest, NSPrivacyAccessedAPITypes=[]), ud, True)) == \
        ["ASC-03.t.api.UserDefaults"], "an undeclared use must fail"
    bad_code = dict(manifest, NSPrivacyAccessedAPITypes=[{"NSPrivacyAccessedAPIType": USER_DEFAULTS,
                                                         "NSPrivacyAccessedAPITypeReasons": ["C617.1"]}])
    assert failed(check_manifest("t", "m", bad_code, ud, True)) == ["ASC-03.t.reasons-approved"]
    sdk_code = dict(manifest, NSPrivacyAccessedAPITypes=[{"NSPrivacyAccessedAPIType": USER_DEFAULTS,
                                                         "NSPrivacyAccessedAPITypeReasons": ["C56D.1"]}])
    assert failed(check_manifest("t", "m", sdk_code, ud, True)) == ["ASC-03.t.reasons-approved"]
    assert failed(check_manifest("t", "m", dict(manifest, NSPrivacyTracking=True), ud, True)) == \
        ["ASC-03.t.tracking-false"]
    assert failed(check_manifest("t", "m", dict(manifest, NSPrivacyTrackingDomains=["x.example"]), ud, True)) == \
        ["ASC-03.t.tracking-domains-empty"]
    assert failed(check_manifest("t", "m", dict(manifest, NSPrivacyCollectedDataTypes=[{}]), ud, True)) == \
        ["ASC-03.t.collected-data-matches-policy"]
    assert failed(check_manifest("t", "m", manifest, ud, False)) == ["ASC-03.t.collected-data-matches-policy"]
    assert failed(check_manifest("t", "m", {}, ud, True)) == ["ASC-03.t.manifest-present"]
    warn = [c for c in check_manifest("t", "m", manifest, [], True) if not c.ok]
    assert [c.level for c in warn] == ["WARN"], "declared but unused is only a warning"

    project = '''
name: X
packages:
  Core:
    path: ../../packages/Core
targets:
  App:
    type: application
    sources:
      - path: App
    dependencies:
      - package: Core
        product: CoreLib # a comment
      - target: Ext
        embed: true
  Ext:
    sources:
      - Ext
    dependencies:
      - package: Core
schemes:
  App:
    build:
      targets:
        App: [run, test]
'''
    packages, targets = parse_project(project)
    assert packages == {"Core": "../../packages/Core"}, packages
    assert targets["App"].sources == ["App"], targets["App"]
    assert targets["App"].dependencies == [("package", "Core", "CoreLib"), ("target", "Ext")], targets["App"]
    assert targets["Ext"].sources == ["Ext"] and targets["Ext"].dependencies == [("package", "Core", "Core")]
    try:
        import yaml  # optional: cross-check the small reader against a real YAML parser
    except ImportError:
        yaml = None
    if yaml is not None:
        repo_project = pathlib.Path(__file__).resolve().parents[2] / PROJECT_YML
        if repo_project.exists():
            text = repo_project.read_text(encoding="utf-8")
            ours_packages, ours = parse_project(text)
            theirs = yaml.safe_load(text)
            assert ours_packages == {k: v["path"] for k, v in theirs["packages"].items()}
            for name, spec in theirs["targets"].items():
                want_sources = [s["path"] if isinstance(s, dict) else s for s in spec.get("sources", [])]
                want_deps = [("package", d["package"], d.get("product", d["package"])) if "package" in d
                             else ("target", d["target"]) for d in spec.get("dependencies", [])
                             if "package" in d or "target" in d]
                assert ours[name].sources == want_sources, (name, ours[name].sources, want_sources)
                assert ours[name].dependencies == want_deps, (name, ours[name].dependencies, want_deps)

    print("check_privacy_manifest self-test: 17 checks passed"
          + ("; the project.yml reader matches PyYAML on this repo's project.yml" if yaml else
             "; PyYAML not installed, so the project.yml reader was not cross-checked"))
    return 0


def main(argv: list[str]) -> int:
    args = argv[1:]
    if args == ["--self-test"]:
        return self_test()
    json_out = None
    if "--json" in args:
        index = args.index("--json")
        if index + 1 >= len(args):
            print(__doc__)
            return 2
        json_out = args[index + 1]
        del args[index:index + 2]
    if len(args) > 1:
        print(__doc__)
        return 2
    root = pathlib.Path(args[0] if args else ".").resolve()
    try:
        checks, report = run(root)
    except InputError as error:
        print(f"PRIVACY | ERROR | input | {error}")
        return 2
    print_report(checks, report)
    if json_out:
        pathlib.Path(json_out).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    failed = [c for c in checks if not c.ok and c.level == "ERROR"]
    print(f"PRIVACY | {'FAIL' if failed else 'PASS'} | summary | {len(checks)} checks, {len(failed)} failed, "
          f"{sum(1 for c in checks if not c.ok and c.level == 'WARN')} warnings")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
