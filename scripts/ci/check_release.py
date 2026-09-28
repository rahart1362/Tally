#!/usr/bin/env python3
"""ASC-10: the release gate's compliance checks (app-store-compliance.md §3.3.1, GO-LIVE GL-06).

Every check has an ID, a level (ERROR fails the gate, WARN is reported) and the milestone it is
due by. The gate runs from M2 on; many checks can only pass later (an owner's Team ID, counsel's
sign-off, screens not built yet). A check due after the current milestone (`CURRENT_MILESTONE`)
that does not pass yet is PENDING: it is reported with its milestone and owner and does not fail
the gate. A check that is due now and fails is FAIL, and fails the gate. Nothing is dropped: every
check appears in the compliance report, and a pending check that starts passing says so.

    python3 scripts/ci/check_release.py --source [ROOT] --json OUT
        Linux. Info.plist settings in project.yml, entitlements, the icon, release strings, the
        disclaimer, go-live placeholders, store metadata, and the privacy manifests (ASC-03,
        scripts/ci/check_privacy_manifest.py).
    python3 scripts/ci/check_release.py --app APP --label NAME --json OUT [--root ROOT]
        macOS. A built Tally.app: identity and required Info.plist keys, the widget extension,
        both privacy manifests inside the bundles, and the required-reason API symbols the
        binaries actually import (nm -u, otool) against each bundle's manifest.
    python3 scripts/ci/check_release.py --flows RESULTS [RESULTS ...] --json OUT
        The critical XCUITest flows (§3.3.1), from `xcresulttool get test-results tests` JSON,
        each RESULTS given as CONFIGURATION=PATH (e.g. Release=release-tests.json).
    python3 scripts/ci/check_release.py --result ID pass|fail DETAIL --title TITLE [--due M] --json OUT
        One result a workflow step measured itself (for example the launch smoke test).
    python3 scripts/ci/check_release.py --pending ID MILESTONE OWNER DETAIL --title TITLE --json OUT
        A check that is not implemented yet and is due by MILESTONE (the M5 screenshot job).
    python3 scripts/ci/check_release.py --merge OUT IN [IN ...]
        Combines the jobs' reports into one compliance JSON, prints the table and decides.
    python3 scripts/ci/check_release.py --self-test

`--report-only` (with --app, --flows or --result) turns every check it writes into a WARN: reported,
never failing the gate. The Xcode 27 job uses it: that runner image is a preview (R1, R5).

Exit codes: 0 when nothing due now fails; 1 when something due now fails; 2 when an input cannot
be read (never a silent pass).
"""
from __future__ import annotations

import importlib.util
import json
import pathlib
import plistlib
import re
import struct
import subprocess
import sys
from dataclasses import asdict, dataclass

CURRENT_MILESTONE = "M2"
MILESTONES = ("M2", "M3", "M4", "M5")  # in order; a check due after CURRENT_MILESTONE can be pending


@dataclass
class Check:
    id: str
    title: str
    level: str  # "ERROR" or "WARN"
    due: str  # milestone
    ok: bool
    detail: str
    owner: str = ""
    status: str = ""  # PASS / FAIL / PENDING / WARN / N/A, filled by `settle`

    def settle(self) -> "Check":
        if self.status == "N/A":
            return self
        if self.ok:
            self.status = "PASS"
        elif MILESTONES.index(self.due) > MILESTONES.index(CURRENT_MILESTONE):
            self.status = "PENDING"
        else:
            self.status = "FAIL" if self.level == "ERROR" else "WARN"
        return self


class InputError(Exception):
    pass


def _sibling(name: str):
    path = pathlib.Path(__file__).resolve().with_name(f"{name}.py")
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise InputError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


# ------------------------------------------------------------------------------------------------
# Source checks (Linux)
# ------------------------------------------------------------------------------------------------

PROJECT_YML = "apps/TallyiOS/project.yml"
IDENTITY = "apps/TallyiOS/Config/Identity.xcconfig"
APP_ICON = "apps/TallyiOS/Tally/Assets.xcassets/AppIcon.appiconset/Icon-1024.png"
METADATA_DIR = "docs/release/metadata"
# App Store Connect limits (app-store-compliance.md §3.5): characters, except keywords (bytes).
METADATA_LIMITS = {"name.txt": 30, "subtitle.txt": 30, "keywords.txt": 100, "promotional_text.txt": 170,
                   "description.txt": 4000, "review_notes.txt": 4000}
ENTITLEMENTS_ALLOWED = {
    # app-store-compliance.md §3.4, plus the two the encryption and notification lanes added:
    # keychain-access-groups (ENC-03/ENC-05) and time-sensitive notifications (R14).
    "Tally": {"com.apple.security.application-groups", "keychain-access-groups",
              "com.apple.developer.usernotifications.time-sensitive", "com.apple.developer.associated-domains",
              "com.apple.developer.declared-age-range"},
    "TallyWidgets": {"com.apple.security.application-groups", "keychain-access-groups"},
}
# (API regex in shipping code, the Info.plist purpose key it needs). app-store-compliance.md R15.
PURPOSE_STRINGS = [
    (r"\bLAContext\b", "NSFaceIDUsageDescription"),
    (r"\brequestFullAccessToEvents\b", "NSCalendarsFullAccessUsageDescription"),
    (r"\brequestWriteOnlyAccessToEvents\b", "NSCalendarsWriteOnlyAccessUsageDescription"),
    (r"\brequestFullAccessToReminders\b", "NSRemindersFullAccessUsageDescription"),
    (r"\bCLLocationManager\b", "NSLocationWhenInUseUsageDescription"),
    (r"\bAVCaptureDevice\b", "NSCameraUsageDescription"),
    (r"\bPHPhotoLibrary\b", "NSPhotoLibraryUsageDescription"),
    (r"\bCNContactStore\b", "NSContactsUsageDescription"),
    (r"\bAVAudioRecorder\b", "NSMicrophoneUsageDescription"),
]
# app-store-compliance.md §3.3.1 "Release strings": no mock or placeholder content in shipping code.
RELEASE_STRINGS = [
    ("mock_", re.compile(r"mock_")), ("Mock", re.compile(r"\bMock\w*")), ("simulated", re.compile(r"simulated")),
    ("Lorem", re.compile(r"Lorem")), ("Alex", re.compile(r"\bAlex\b")), ("Int.random(", re.compile(r"\bInt\.random\(")),
    ("Button(action: {})", re.compile(r"Button\(action:\s*\{\s*\}\)")),
    ("Calculus III Midterm", re.compile(r"Calculus III Midterm")),
]
DISCLAIMER = re.compile(r"not affiliated with.{0,80}Instructure", re.S)
# Lines find-placeholders.sh lists on purpose, with the reason. Anything else in shipping code fails.
PLACEHOLDER_ALLOWLIST = {
    "packages/TallyAppleKit/Sources/TallyPlatform/KeychainCredentialStore.swift":
        "deletes the pre-rewrite build's mock credential item (its legacy Keychain service) on init",
}


def _yaml():
    try:
        import yaml
    except ImportError as error:
        raise InputError("PyYAML is required for --source (apt-get install python3-yaml)") from error
    return yaml


def _png_header(path: pathlib.Path) -> tuple[int, int, int, bool]:
    """(width, height, colour type, has a tRNS chunk) from a PNG's chunks."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise InputError(f"{path} is not a PNG")
    offset, header, transparency = 8, None, False
    while offset + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[offset:offset + 8])
        if kind == b"IHDR":
            width, height, _, colour = struct.unpack(">IIBB", data[offset + 8:offset + 18])
            header = (width, height, colour)
        elif kind == b"tRNS":
            transparency = True
        elif kind == b"IEND":
            break
        offset += 12 + length
    if header is None:
        raise InputError(f"{path} has no IHDR chunk")
    return header[0], header[1], header[2], transparency


def _placeholder_hits(root: pathlib.Path) -> list[tuple[str, str, str]]:
    """(category, path, line) for every line scripts/go-live/find-placeholders.sh lists."""
    result = subprocess.run(["bash", str(root / "scripts/go-live/find-placeholders.sh")], cwd=root,
                            capture_output=True, text=True)
    hits, category = [], None
    for line in result.stdout.splitlines():
        heading = re.match(r"^== (.+) \(\d+\)$", line)
        if heading:
            category = heading.group(1)
        elif category and re.match(r"^[^\s:]+:\d+:", line):
            path, number, _ = line.split(":", 2)
            hits.append((category, path, number))
    if result.returncode not in (0, 1) or (result.returncode == 1 and not hits):
        raise InputError(f"find-placeholders.sh exited {result.returncode} without a list: {result.stderr.strip()}")
    return hits


def source_checks(root: pathlib.Path) -> list[Check]:
    yaml = _yaml()
    privacy = _sibling("check_privacy_manifest")
    try:
        project = yaml.safe_load((root / PROJECT_YML).read_text(encoding="utf-8"))
        identity = (root / IDENTITY).read_text(encoding="utf-8")
    except OSError as error:
        raise InputError(str(error)) from error
    targets = project["targets"]
    app_info = targets["Tally"]["info"]["properties"]
    widget_info = targets["TallyWidgets"]["info"]["properties"]
    base = project.get("settings", {}).get("base", {})
    checks: list[Check] = []

    def add(id_, title, ok, detail, due="M2", level="ERROR", owner=""):
        checks.append(Check(id_, title, level, due, bool(ok), detail, owner))

    # Identity (ASC-01, R17).
    derived = re.search(r"^PRODUCT_BUNDLE_IDENTIFIER\s*=\s*\$\(TALLY_BUNDLE_ID_PREFIX\)\.tally\s*$", identity, re.M)
    prefix = re.search(r"^TALLY_BUNDLE_ID_PREFIX\s*=\s*([^\s/]+)", identity, re.M)
    widget_id = targets["TallyWidgets"].get("settings", {}).get("base", {}).get("PRODUCT_BUNDLE_IDENTIFIER")
    add("REL.plist.bundle-id", "Bundle IDs derive from one prefix; the widget's extends the app's",
        derived and prefix and "CFBundleIdentifier" not in app_info
        and widget_id == "$(TALLY_BUNDLE_ID_PREFIX).tally.widgets",
        f"prefix {prefix.group(1) if prefix else 'missing'}; app $(TALLY_BUNDLE_ID_PREFIX).tally; widget {widget_id}")
    versions = [(name, info.get("CFBundleShortVersionString"), info.get("CFBundleVersion"))
                for name, info in (("Tally", app_info), ("TallyWidgets", widget_info))]
    add("REL.plist.version-variables",
        "Version and build number come from $(MARKETING_VERSION)/$(CURRENT_PROJECT_VERSION), set per upload (R19)",
        all(v == "$(MARKETING_VERSION)" and b == "$(CURRENT_PROJECT_VERSION)" for _, v, b in versions),
        "; ".join(f"{n}: {v!r}/{b!r}" for n, v, b in versions), due="M5",
        owner="M5 TestFlight lane (a unique, increasing CFBundleVersion per upload)")
    add("REL.plist.encryption-exempt", "ITSAppUsesNonExemptEncryption is NO (Apple crypto only, R11)",
        app_info.get("ITSAppUsesNonExemptEncryption") is False,
        f"ITSAppUsesNonExemptEncryption = {app_info.get('ITSAppUsesNonExemptEncryption')!r}")
    modes = app_info.get("UIBackgroundModes", [])
    tally_sources = "\n".join(p.read_text(encoding="utf-8") for p in (root / "apps/TallyiOS/Tally").rglob("*.swift"))
    background = (root / "packages/TallyAppleKit/Sources/TallyPlatform/BackgroundRefresh.swift")
    background_text = background.read_text(encoding="utf-8") if background.exists() else ""
    add("REL.plist.background-modes",
        "UIBackgroundModes is at most fetch, used by one .backgroundTask(.appRefresh) with the permitted ID",
        set(modes) <= {"fetch"} and ("fetch" not in modes or (
            ".backgroundTask(.appRefresh(" in tally_sources
            and app_info.get("BGTaskSchedulerPermittedIdentifiers") == ["$(PRODUCT_BUNDLE_IDENTIFIER).refresh"]
            and '+ ".refresh"' in background_text)),
        f"UIBackgroundModes {modes}; BGTaskSchedulerPermittedIdentifiers "
        f"{app_info.get('BGTaskSchedulerPermittedIdentifiers')}")
    family = str(base.get("TARGETED_DEVICE_FAMILY", ""))
    orientations = app_info.get("UISupportedInterfaceOrientations", [])
    add("REL.plist.device-family", "iPhone only, portrait (ASC-F07); iPad would need all four orientations",
        family == "1" and orientations == ["UIInterfaceOrientationPortrait"],
        f"TARGETED_DEVICE_FAMILY {family!r}; orientations {orientations}")
    ats = [name for name, info in (("Tally", app_info), ("TallyWidgets", widget_info))
           if (info.get("NSAppTransportSecurity") or {}).get("NSAllowsArbitraryLoads")]
    add("REL.plist.ats", "No NSAllowsArbitraryLoads", not ats, f"arbitrary loads allowed in: {ats or 'none'}")
    schemes = app_info.get("LSApplicationQueriesSchemes", [])
    add("REL.plist.query-schemes", "LSApplicationQueriesSchemes has at most 25 entries (iOS 27 limit, R16)",
        len(schemes) <= 25, f"{len(schemes)} entries")

    # Purpose strings match the APIs the shipping code calls (R15), in both directions.
    app_bundle = privacy.Bundle("app", "Tally", "apps/TallyiOS/Tally/PrivacyInfo.xcprivacy")
    app_dirs, _, _ = privacy.shipping_source_dirs(root, app_bundle)
    widget_bundle = privacy.Bundle("widget", "TallyWidgets", "apps/TallyiOS/TallyWidgets/PrivacyInfo.xcprivacy")
    widget_dirs, _, _ = privacy.shipping_source_dirs(root, widget_bundle)
    shipping: dict[str, str] = {}
    for directory in app_dirs + widget_dirs:
        for swift in directory.rglob("*.swift"):
            shipping[swift.relative_to(root).as_posix()] = swift.read_text(encoding="utf-8")
    code = {path: privacy.mask(text) for path, text in shipping.items()}
    problems = []
    for pattern, key in PURPOSE_STRINGS:
        callers = [path for path, text in code.items() if re.search(pattern, text)]
        if callers and key not in app_info:
            problems.append(f"{key} missing, but {callers[0]} uses {pattern.strip(chr(92) + 'b')}")
        if key in app_info and not callers:
            problems.append(f"{key} is declared but nothing calls the API it describes")
    add("REL.plist.purpose-strings", "Each permission API has its purpose string, and no purpose string lacks a caller",
        not problems, "; ".join(problems) or "no permission API in shipping code, no purpose string declared")

    # Entitlements (§3.4 allow-list).
    for name in ("Tally", "TallyWidgets"):
        path = root / "apps/TallyiOS" / targets[name]["entitlements"]["path"]
        with path.open("rb") as handle:
            keys = set(plistlib.load(handle))
        extra = sorted(keys - ENTITLEMENTS_ALLOWED[name])
        add(f"REL.entitlements.{name}", f"{name} entitlements are on the allow-list", not extra,
            f"keys: {sorted(keys)}" + (f"; not allowed: {extra}" if extra else ""))

    # The App Store icon (ASC-F04, ITMS-90717).
    width, height, colour, transparency = _png_header(root / APP_ICON)
    add("REL.icon.opaque-1024", "The App Store icon is 1024x1024 with no alpha",
        (width, height) == (1024, 1024) and colour in (0, 2) and not transparency,
        f"{width}x{height}, PNG colour type {colour}{', tRNS' if transparency else ''}")

    # Release strings and the disclaimer (§3.3.1, R10 of the ASC review), outside #if DEBUG.
    hits = []
    for path, text in shipping.items():
        masked = privacy.mask(text, keep_strings=True)
        debug = privacy.debug_only_lines(masked)
        for label, pattern in RELEASE_STRINGS:
            for m in pattern.finditer(masked):
                line = masked.count("\n", 0, m.start()) + 1
                if line not in debug:
                    hits.append(f"{path}:{line} {label}")
    add("REL.strings.release-clean", "No mock, placeholder or fabricated content in shipping code",
        not hits, "; ".join(hits[:10]) or f"{len(shipping)} shipping Swift files scanned")
    disclaimer = [path for path, text in shipping.items() if DISCLAIMER.search(privacy.mask(text, keep_strings=True))]
    add("REL.disclaimer.non-affiliation", "The in-app non-affiliation disclaimer exists (R10)", disclaimer,
        f"found in {disclaimer}" if disclaimer else "no 'not affiliated with ... Instructure' text in shipping code")
    names = [info.get("CFBundleDisplayName", "") for info in (app_info, widget_info)]
    add("REL.plist.display-name", "No bundle's display name contains \"Canvas\" (R11, 4.1(c))",
        not any("canvas" in name.lower() for name in names), f"display names {names}")

    # Go-live placeholders (GL-02, GL-03): owner values and counsel are M5; shipping regressions are not.
    placeholder_hits = _placeholder_hits(root)
    shipping_paths = set(shipping)
    owner_values = [h for h in placeholder_hits if h[0].startswith("Tagged placeholder")]
    legal = [h for h in placeholder_hits if h[0].startswith("Legal draft")]
    rest = [h for h in placeholder_hits if h not in owner_values and h not in legal]
    in_shipping = [h for h in rest if h[1] in shipping_paths and h[1] not in PLACEHOLDER_ALLOWLIST]
    allowed = [h for h in rest if h[1] in PLACEHOLDER_ALLOWLIST]
    elsewhere = [h for h in rest if h[1] not in shipping_paths and h[1] not in PLACEHOLDER_ALLOWLIST]
    fmt = lambda hs: "; ".join(f"{p}:{n}" for _, p, n in hs[:8]) + (f" (+{len(hs) - 8})" if len(hs) > 8 else "")
    add("REL.go-live.owner-values", "No go-live placeholder values remain (Team ID, support e-mail, dates; GL-02)",
        not owner_values, fmt(owner_values) or "none", due="M5", owner="owner (GO-LIVE GL-02)")
    add("REL.go-live.legal", "The privacy policy has counsel's sign-off (GL-03)", not legal,
        fmt(legal) or "none", due="M5", owner="owner and counsel (GO-LIVE GL-03)")
    add("REL.go-live.shipping-identifiers",
        "Shipping code has no legacy or placeholder identifier outside the documented exceptions",
        not in_shipping, (fmt(in_shipping) or "none")
        + (f"; allowed: {', '.join(sorted({p for _, p, _ in allowed}))} ({PLACEHOLDER_ALLOWLIST[allowed[0][1]]})"
           if allowed else ""))
    add("REL.go-live.unlinked-legacy", "No legacy identifiers remain anywhere the scanner looks (GL-02)",
        not elsewhere, fmt(elsewhere) or "none", due="M5",
        owner="PMO: delete the unlinked pre-rewrite packages (packages/Tally{Security,Data,CanvasKit,...}) and "
              "update the legacy-cleanup test")

    # Store listing metadata (§3.5) and the published privacy policy (R4).
    metadata = root / METADATA_DIR
    missing = [name for name in METADATA_LIMITS if not (metadata / name).exists()]
    over = []
    for name, limit in METADATA_LIMITS.items():
        path = metadata / name
        if path.exists():
            text = path.read_text(encoding="utf-8").strip()
            size = len(text.encode("utf-8")) if name == "keywords.txt" else len(text)
            if size > limit:
                over.append(f"{name} {size} > {limit}")
    add("REL.metadata.store-listing", "Store metadata files exist and fit App Store Connect's limits",
        not missing and not over, f"missing: {missing}; over: {over}" if missing or over else "all within limits",
        due="M5", owner="M5 store listing (app-store-compliance.md §3.5)")

    # ASC-03, through the same script as the hygiene gate.
    privacy_checks, _ = privacy.run(root)
    for check in privacy_checks:
        checks.append(Check(f"REL.{check.id}", f"Privacy manifest: {check.id}", check.level, "M2", check.ok, check.detail))
    return checks


# ------------------------------------------------------------------------------------------------
# Built-app checks (macOS)
# ------------------------------------------------------------------------------------------------

# Symbols in `nm -u` (imports) and Objective-C selectors that mean a required-reason category.
BINARY_SYMBOLS = {
    "NSPrivacyAccessedAPICategoryUserDefaults": {"_OBJC_CLASS_$_NSUserDefaults"},
    "NSPrivacyAccessedAPICategorySystemBootTime": {"_mach_absolute_time"},
    "NSPrivacyAccessedAPICategoryFileTimestamp": {
        "_stat", "_lstat", "_fstat", "_fstatat", "_getattrlist", "_getattrlistbulk", "_fgetattrlist", "_getattrlistat",
        "_NSFileCreationDate", "_NSFileModificationDate", "_NSURLCreationDateKey", "_NSURLContentModificationDateKey"},
    "NSPrivacyAccessedAPICategoryDiskSpace": {
        "_statfs", "_statvfs", "_fstatfs", "_fstatvfs", "_NSFileSystemFreeSize", "_NSFileSystemSize",
        "_NSURLVolumeAvailableCapacityKey", "_NSURLVolumeAvailableCapacityForImportantUsageKey",
        "_NSURLVolumeAvailableCapacityForOpportunisticUsageKey", "_NSURLVolumeTotalCapacityKey"},
}
BINARY_SELECTORS = {
    "NSPrivacyAccessedAPICategorySystemBootTime": {"systemUptime"},
    "NSPrivacyAccessedAPICategoryActiveKeyboards": {"activeInputModes"},
}
MACHO_MAGICS = {b"\xfe\xed\xfa\xce", b"\xfe\xed\xfa\xcf", b"\xce\xfa\xed\xfe", b"\xcf\xfa\xed\xfe",
                b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"}


def _read_plist(path: pathlib.Path) -> dict:
    try:
        with path.open("rb") as handle:
            return plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException, ValueError) as error:
        raise InputError(f"cannot read {path}: {error}") from error


def _machos(bundle: pathlib.Path, skip: pathlib.Path | None = None) -> list[pathlib.Path]:
    found = []
    for path in sorted(bundle.rglob("*")):
        if skip and skip in path.parents:
            continue
        if path.is_file() and not path.is_symlink():
            with path.open("rb") as handle:
                if handle.read(4) in MACHO_MAGICS:
                    found.append(path)
    return found


def categories_in(imports: set[str], selectors: set[str]) -> dict[str, list[str]]:
    used: dict[str, list[str]] = {}
    for category, symbols in BINARY_SYMBOLS.items():
        hit = sorted(imports & symbols)
        if hit:
            used.setdefault(category, []).extend(hit)
    for category, names in BINARY_SELECTORS.items():
        hit = sorted(selectors & names)
        if hit:
            used.setdefault(category, []).extend(hit)
    return used


def _binary_uses(machos: list[pathlib.Path]) -> dict[str, list[str]]:
    imports: set[str] = set()
    selectors: set[str] = set()
    for macho in machos:
        nm = subprocess.run(["xcrun", "nm", "-u", str(macho)], capture_output=True, text=True)
        if nm.returncode == 0:
            imports.update(line.strip() for line in nm.stdout.splitlines() if line.strip())
        otool = subprocess.run(["xcrun", "otool", "-v", "-s", "__TEXT", "__objc_methname", str(macho)],
                               capture_output=True, text=True)
        if otool.returncode == 0:
            for line in otool.stdout.splitlines():
                parts = line.split(None, 1)
                if len(parts) == 2:
                    selectors.add(parts[1].strip())
    return categories_in(imports, selectors)


def app_checks(app: pathlib.Path, label: str, root: pathlib.Path) -> list[Check]:
    privacy = _sibling("check_privacy_manifest")
    identity = (root / IDENTITY).read_text(encoding="utf-8")
    prefix = re.search(r"^TALLY_BUNDLE_ID_PREFIX\s*=\s*([^\s/]+)", identity, re.M)
    if not prefix:
        raise InputError(f"no TALLY_BUNDLE_ID_PREFIX in {IDENTITY}")
    expected_id = f"{prefix.group(1)}.tally"
    info = _read_plist(app / "Info.plist")
    checks: list[Check] = []

    def add(id_, title, ok, detail, due="M2", level="ERROR", owner=""):
        checks.append(Check(f"REL.app.{label}.{id_}", f"[{label}] {title}", level, due, bool(ok), detail, owner))

    executable = info.get("CFBundleExecutable", "")
    add("identity", "Built bundle ID, package type, executable, display name, versions, iOS 26, iPhone only",
        info.get("CFBundleIdentifier") == expected_id and info.get("CFBundlePackageType") == "APPL"
        and executable and (app / executable).is_file() and info.get("CFBundleDisplayName")
        and info.get("CFBundleShortVersionString") and info.get("CFBundleVersion")
        and info.get("MinimumOSVersion") == "26.0" and info.get("UIDeviceFamily") == [1],
        ", ".join(f"{k}={info.get(k)!r}" for k in ("CFBundleIdentifier", "CFBundlePackageType", "CFBundleExecutable",
                                                     "CFBundleDisplayName", "CFBundleShortVersionString",
                                                     "CFBundleVersion", "MinimumOSVersion", "UIDeviceFamily")))
    add("encryption-exempt", "ITSAppUsesNonExemptEncryption is false in the built Info.plist",
        info.get("ITSAppUsesNonExemptEncryption") is False, f"{info.get('ITSAppUsesNonExemptEncryption')!r}")
    add("background", "fetch only, with the one permitted refresh task ID derived from the bundle ID",
        info.get("UIBackgroundModes") == ["fetch"]
        and info.get("BGTaskSchedulerPermittedIdentifiers") == [f"{expected_id}.refresh"],
        f"UIBackgroundModes {info.get('UIBackgroundModes')}, IDs {info.get('BGTaskSchedulerPermittedIdentifiers')}")
    icons = (info.get("CFBundleIcons") or {}).get("CFBundlePrimaryIcon") or {}
    add("icon", "The compiled icon set is referenced (actool built AppIcon)",
        icons.get("CFBundleIconName") == "AppIcon", f"CFBundlePrimaryIcon {icons}")

    appex = app / "PlugIns" / "TallyWidgets.appex"
    widget_info = _read_plist(appex / "Info.plist") if appex.is_dir() else {}
    add("widget", "The widget extension is embedded, with its own ID, the WidgetKit extension point and the glance keys",
        widget_info.get("CFBundleIdentifier", "").startswith(expected_id + ".")
        and (widget_info.get("NSExtension") or {}).get("NSExtensionPointIdentifier") == "com.apple.widgetkit-extension"
        and widget_info.get("TallyAppBundleID") == expected_id
        and widget_info.get("TallyAppGroupID") == info.get("TallyAppGroupID"),
        f"{appex.name}: CFBundleIdentifier={widget_info.get('CFBundleIdentifier')!r}, "
        f"TallyAppBundleID={widget_info.get('TallyAppBundleID')!r}, TallyAppGroupID={widget_info.get('TallyAppGroupID')!r}")

    for name, bundle, skip in (("app", app, appex), ("widget", appex, None)):
        manifest_path = bundle / "PrivacyInfo.xcprivacy"
        manifest = _read_plist(manifest_path) if manifest_path.exists() else {}
        uses_by_category = _binary_uses(_machos(bundle, skip)) if bundle.is_dir() else {}
        uses = [privacy.Use(category, ", ".join(symbols), f"{bundle.name} (binary)", 0, False)
                for category, symbols in uses_by_category.items()]
        for check in privacy.check_manifest(f"{label}.{name}", f"{bundle.name}/PrivacyInfo.xcprivacy",
                                            manifest, uses, policy_ok=True):
            checks.append(Check(f"REL.app.{check.id}", f"[{label}] built {name} manifest: {check.id}",
                                check.level, "M2", check.ok, check.detail))
    return checks


# ------------------------------------------------------------------------------------------------
# Critical flows (§3.3.1 "Critical flows as XCUITests")
# ------------------------------------------------------------------------------------------------

@dataclass(frozen=True)
class Flow:
    id: str
    title: str
    tests: tuple[str, ...]  # "Suite/testName" in TallyUITests
    configuration: str  # the configuration the tests must pass in now
    due: str
    owner: str


FLOWS = (
    Flow("REL.flow.01-first-login", "First login: OAuth sign-in, then the Dashboard", (), "", "M5",
         "M5: ASC-11's mock OAuth/Canvas server was deferred to M5 (plan 07 §1); M2-C1 builds the replay-backed first sync"),
    Flow("REL.flow.02-launch-with-cache", "Launch with a valid cache paints it before the network", (), "", "M2",
         "M2-C1 (plan 06 step 8, the M2 exit's UI test, plan 07 §3 item 1): not on this commit; map its test here "
         "when it merges"),
    Flow("REL.flow.03-launch-no-cache", "Launch with no cache shows Welcome",
         ("TallyLaunchUITests/testAppLaunchesAndRootViewExists",), "Release", "M2", ""),
    Flow("REL.flow.04-refresh-under-10s", "A refresh under 10 s updates in place", (), "", "M5",
         "M5: no UI test yet (HomeModelTests cover the live budget in-process)"),
    Flow("REL.flow.05-refresh-over-10s", "A refresh over 10 s shows the stale breadcrumb and last-refreshed time",
         ("SlowRefreshUITests/testSlowRefreshShowsTheBreadcrumbThenSelfHeals",), "Debug", "M2", ""),
    Flow("REL.flow.06-refresh-self-heals", "A refresh that lands after the budget self-heals the UI",
         ("SlowRefreshUITests/testSlowRefreshShowsTheBreadcrumbThenSelfHeals",
          "SlowRefreshUITests/testPullToRefreshStopsAtTheBudgetWhileTheRefreshRuns"), "Debug", "M2", ""),
    Flow("REL.flow.07-threshold-alert", "A threshold alert is scheduled", (), "", "M3", "M3-C notifications (E07)"),
    Flow("REL.flow.08-quiet-hours", "Quiet hours are respected", (), "", "M3", "M3-C notifications (E07)"),
    Flow("REL.flow.10-no-prompt-at-launch", "No system permission alert at first launch", (), "", "M3",
         "M3-C: in-context permission priming (UX-WP-12) with its UI test"),
    Flow("REL.flow.11-denied-permissions", "Denied notifications and calendar leave the app usable", (), "", "M3",
         "M3-C notifications and M3-A calendar"),
    Flow("REL.flow.12-privacy-policy-link", "The privacy policy link opens", (), "", "M3", "M3-A Settings"),
    Flow("REL.flow.13-sign-out-erase", "Sign out & erase leaves no Keychain item, cache, notification or widget data",
         (), "", "M3", "M2-C1 (plan 06 step 10) and M3-A Settings"),
    Flow("REL.flow.14-demo-mode", "Explore with Sample Data works end to end",
         ("SampleDataUITests/testWelcomeToSampleDataDashboard", "SampleDataUITests/testSampleEntryAndExitTwice",
          "SampleDataUITests/testSchoolNotEnabledToSampleData"), "Release", "M2", ""),
    Flow("REL.flow.welcome-ctas", "Welcome's CTAs are hittable at launch and at AX XXXL",
         ("WelcomeCTAUITests/testBothCTAsAreHittableRightAfterLaunch",
          "WelcomeCTAUITests/testBothCTAsAreHittableAtAccessibilityXXXL"), "Release", "M2", ""),
    Flow("REL.flow.school-search", "Find My School reaches search, and a failed search is reported",
         ("SchoolSearchUITests/testFindMySchoolNavigatesToSearchWithIdleHelperText",
          "SchoolSearchUITests/testTypingAQueryEventuallyReportsASearchFailure"), "Release", "M2", ""),
)


def test_results(document: object) -> dict[str, str]:
    """`Suite/test` -> result, from `xcresulttool get test-results tests` JSON. Tolerant of nesting:
    every node with nodeType "Test Case" counts, identified by its nodeIdentifier, or by its suite's
    name and its own."""
    results: dict[str, str] = {}

    def walk(node: object, suite: str) -> None:
        if isinstance(node, list):
            for item in node:
                walk(item, suite)
            return
        if not isinstance(node, dict):
            return
        kind = node.get("nodeType", "")
        name = str(node.get("name", ""))
        if kind == "Test Suite":
            suite = name
        if kind == "Test Case":
            identifier = str(node.get("nodeIdentifier") or f"{suite}/{name}")
            results[identifier.removesuffix("()")] = str(node.get("result", "?"))
        for value in node.values():
            if isinstance(value, (list, dict)):
                walk(value, suite)

    walk(document, "")
    return results


def flow_checks(results_by_configuration: dict[str, dict[str, str]]) -> list[Check]:
    checks = []
    for flow in FLOWS:
        if not flow.tests:
            checks.append(Check(flow.id, flow.title, "ERROR", flow.due, False, "no UI test covers this flow yet", flow.owner))
            continue
        results = results_by_configuration.get(flow.configuration)
        if results is None:
            checks.append(Check(flow.id, flow.title, "ERROR", flow.due, False,
                                f"no {flow.configuration} test results were given"))
            continue
        outcome = {test: _lookup(results, test) for test in flow.tests}
        ok = all(result == "Passed" for result in outcome.values())
        checks.append(Check(flow.id, f"{flow.title} ({flow.configuration})", "ERROR", flow.due, ok,
                            "; ".join(f"{test}: {result}" for test, result in outcome.items())))
        if flow.configuration == "Debug":
            checks.append(Check(f"{flow.id}.release-config", f"{flow.title} in a Release-optimized UI test build",
                                "ERROR", "M5", False,
                                "these tests use a DEBUG-only launch hook today; the UITest configuration "
                                "(Release optimizations plus TALLY_UI_TESTING, §3.3.1) is M5 work",
                                "M5 (ASC-10: the UITest build configuration)"))
    return checks


def _lookup(results: dict[str, str], test: str) -> str:
    for identifier, result in results.items():
        if identifier == test or identifier.endswith("/" + test):
            return result
    return "missing (did not run)"


# ------------------------------------------------------------------------------------------------
# Reports
# ------------------------------------------------------------------------------------------------

def write(checks: list[Check], out: str, source: str, report_only: bool = False) -> int:
    if report_only:
        for check in checks:
            check.level = "WARN"
            check.title = f"{check.title} [report-only]"
    settled = [c.settle() for c in checks]
    pathlib.Path(out).write_text(json.dumps({"source": source, "milestone": CURRENT_MILESTONE,
                                             "checks": [asdict(c) for c in settled]}, indent=2) + "\n",
                                 encoding="utf-8")
    print_table(settled)
    return 1 if any(c.status == "FAIL" for c in settled) else 0


def print_table(checks: list[Check]) -> None:
    order = {"FAIL": 0, "PENDING": 1, "WARN": 2, "PASS": 3, "N/A": 4}
    for check in sorted(checks, key=lambda c: (order.get(c.status, 5), c.id)):
        owner = f" | owner: {check.owner}" if check.owner and check.status != "PASS" else ""
        print(f"RELEASE | {check.status} | {check.due} | {check.id} | {check.title} | {check.detail}{owner}")
    counts = {status: sum(1 for c in checks if c.status == status) for status in order}
    print("RELEASE | summary | " + ", ".join(f"{status} {count}" for status, count in counts.items()))


def merge(out: str, inputs: list[str]) -> int:
    checks: list[Check] = []
    sources = []
    for path in inputs:
        try:
            document = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            print(f"RELEASE | ERROR | input | {path}: {error}")
            return 2
        sources.append(document.get("source", path))
        for item in document.get("checks", []):
            check = Check(**{k: item[k] for k in ("id", "title", "level", "due", "ok", "detail", "owner")})
            check.status = item.get("status", "") if item.get("status") == "N/A" else ""
            checks.append(check)
    ids = [c.id for c in checks]
    duplicates = sorted({i for i in ids if ids.count(i) > 1})
    if duplicates:
        print(f"RELEASE | ERROR | input | duplicate check IDs across reports: {duplicates}")
        return 2
    print(f"RELEASE | merged | {', '.join(sources)}")
    return write(checks, out, "merged: " + ", ".join(sources))


# ------------------------------------------------------------------------------------------------
# Self-test
# ------------------------------------------------------------------------------------------------

def self_test() -> int:
    assert Check("a", "t", "ERROR", "M2", True, "").settle().status == "PASS"
    assert Check("a", "t", "ERROR", "M2", False, "").settle().status == "FAIL"
    assert Check("a", "t", "WARN", "M2", False, "").settle().status == "WARN"
    assert Check("a", "t", "ERROR", "M5", False, "").settle().status == "PENDING", "a later milestone is pending"
    assert Check("a", "t", "ERROR", "M5", True, "").settle().status == "PASS", "a pending check that passes says so"
    tests = {"testNodes": [{"nodeType": "Test Plan", "name": "Tally", "children": [
        {"nodeType": "UI test bundle", "name": "TallyUITests", "children": [
            {"nodeType": "Test Suite", "name": "TallyLaunchUITests", "children": [
                {"nodeType": "Test Case", "name": "testAppLaunchesAndRootViewExists()",
                 "nodeIdentifier": "TallyLaunchUITests/testAppLaunchesAndRootViewExists()", "result": "Passed"}]},
            {"nodeType": "Test Suite", "name": "SampleDataUITests", "children": [
                {"nodeType": "Test Case", "name": "testWelcomeToSampleDataDashboard()", "result": "Failed"}]}]}]}]}
    results = test_results(tests)
    assert results == {"TallyLaunchUITests/testAppLaunchesAndRootViewExists": "Passed",
                       "SampleDataUITests/testWelcomeToSampleDataDashboard": "Failed"}, results
    by_id = {c.id: c.settle() for c in flow_checks({"Release": results, "Debug": {}})}
    assert by_id["REL.flow.03-launch-no-cache"].status == "PASS"
    assert by_id["REL.flow.14-demo-mode"].status == "FAIL", "a failed or missing mapped test fails its flow"
    assert "missing (did not run)" in by_id["REL.flow.14-demo-mode"].detail
    assert by_id["REL.flow.05-refresh-over-10s"].status == "FAIL", "a test that did not run never passes"
    assert by_id["REL.flow.05-refresh-over-10s.release-config"].status == "PENDING"
    assert by_id["REL.flow.07-threshold-alert"].status == "PENDING"
    assert by_id["REL.flow.01-first-login"].status == "PENDING"
    assert categories_in({"_OBJC_CLASS_$_NSUserDefaults", "_malloc"}, {"activeInputModes", "init"}) == {
        "NSPrivacyAccessedAPICategoryUserDefaults": ["_OBJC_CLASS_$_NSUserDefaults"],
        "NSPrivacyAccessedAPICategoryActiveKeyboards": ["activeInputModes"]}
    assert categories_in({"_malloc"}, {"init"}) == {}
    print("check_release self-test: 15 checks passed")
    return 0


def main(argv: list[str]) -> int:
    args = argv[1:]
    try:
        if args == ["--self-test"]:
            return self_test()
        if args[:1] == ["--merge"] and len(args) >= 3:
            return merge(args[1], args[2:])
        options = _options(args)
        out = options.get("--json")
        report_only = "--report-only" in options
        if not out:
            print(__doc__)
            return 2
        if "--source" in options:
            return write(source_checks(pathlib.Path(options["--source"] or ".").resolve()), out, "source")
        if "--app" in options:
            label = options.get("--label") or "app"
            root = pathlib.Path(options.get("--root") or ".").resolve()
            return write(app_checks(pathlib.Path(options["--app"]), label, root), out, f"app:{label}", report_only)
        if "--flows" in options:
            results = {}
            for item in options["--flows"].split():
                configuration, _, path = item.partition("=")
                results[configuration] = test_results(json.loads(pathlib.Path(path).read_text(encoding="utf-8")))
            label = options.get("--label")
            checks = flow_checks(results)
            if label:
                for check in checks:
                    check.id = f"{check.id}.{label}"
            return write(checks, out, f"flows{':' + label if label else ''}", report_only)
        if "--result" in options:
            id_, status, detail = options["--result"].split("\t", 2)
            if status not in ("pass", "fail"):
                raise InputError(f"--result status must be pass or fail, not {status!r}")
            check = Check(id_, options.get("--title") or id_, "ERROR", options.get("--due") or "M2", status == "pass", detail)
            return write([check], out, id_, report_only)
        if "--pending" in options:
            id_, due, owner, detail = options["--pending"].split("\t", 3)
            return write([Check(id_, options.get("--title") or id_, "ERROR", due, False, detail, owner)], out, id_)
    except (InputError, OSError, KeyError, json.JSONDecodeError) as error:
        print(f"RELEASE | ERROR | input | {error}")
        return 2
    print(__doc__)
    return 2


def _options(args: list[str]) -> dict[str, str]:
    """`--flag value…` pairs; multi-value flags (--flows, --result, --pending) take every value up to
    the next flag, joined by spaces (--flows) or tabs (--result, --pending)."""
    options: dict[str, str] = {}
    key = None
    values: list[str] = []
    for arg in args + ["--end"]:
        if arg.startswith("--"):
            if key:
                options[key] = ("\t" if key in ("--result", "--pending") else " ").join(values)
            key, values = arg, []
        else:
            values.append(arg)
    return options


if __name__ == "__main__":
    sys.exit(main(sys.argv))
