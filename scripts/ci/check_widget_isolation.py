#!/usr/bin/env python3
"""Plan 06 step 11: the widget reads the glance only, and links no TallyFeatures.

perf-app-runtime.md §2.4 W3: the widget must "never decode the snapshot, use the network,
construct a RefreshCoordinator or read credentials", and "must not link TallyFeatures, which
bundles 563 KB of CanvasFixtures plus screens". Two gates:

    python3 scripts/ci/check_widget_isolation.py --sources [ROOT]
        Linux (hygiene). (1) The widget target's module closure (project.yml plus each
        Package.swift, read by check_privacy_manifest.py) contains none of the forbidden modules
        and does contain TallyGlance and TallyStore. (2) The widget's own sources and TallyGlance's,
        with comments and strings masked, use none of the forbidden APIs below.

    python3 scripts/ci/check_widget_isolation.py --link-map MAP --bundle APPEX [--bundle APPEX ...]
        macOS (ios-build, after the Release device build with LD_GENERATE_MAP_FILE=YES). (1) The
        Release widget's link map has no line naming a forbidden module, and does name TallyGlance
        and TallyStore (so it is the real map). (2) No Mach-O file in any given .appex (the Release
        one, and the Debug one with its debug dylib) loads a forbidden framework (`otool -L`), and
        no embedded file's path names one.

    python3 scripts/ci/check_widget_isolation.py --self-test

Exit 0 when clean, 1 on a violation, 2 when an input is missing or unreadable (never a silent pass).
"""
from __future__ import annotations

import importlib.util
import pathlib
import re
import subprocess
import sys

# TallyFeatures (screens, sample fixtures) and TallyPlatform (which links it), the modules that can
# fetch, refresh or hold credentials (TallySync, TallyCanvasAPI, and TallyIntents, which links
# TallySync), and sample or test code. An interactive widget intent (M3-D) needs an intents target
# that does not link TallySync, or a PMO ruling to change this list. TallyStrings (plan 08 L10N-01:
# the shared String Catalog, L10n and the formatters; it depends on Foundation and, since L10N-02,
# on TallyDomain for the values its renderers phrase) is allowed.
FORBIDDEN_MODULES = (
    "TallyFeatures", "TallyPlatform", "TallySync", "TallyCanvasAPI", "TallyIntents",
    "TallyReplay", "TallySampleFixtures", "TallyTestSupport",
)
REQUIRED_MODULES = ("TallyGlance", "TallyStore")
WIDGET_TARGET = "TallyWidgets"
SOURCE_DIRS = ("apps/TallyiOS/TallyWidgets", "packages/TallyAppleKit/Sources/TallyGlance")

FORBIDDEN_CODE = [
    ("imports a forbidden module",
     re.compile(r"^\s*(@testable\s+)?import\s+(" + "|".join(FORBIDDEN_MODULES) + r")\b", re.M)),
    ("decodes the snapshot", re.compile(r"\bloadSnapshot\s*\(")),
    ("writes or deletes store files",
     re.compile(r"\.commit\s*\(|\bsweepOrphanedTempFiles\b|\bSealedFileAccess\b|\bProtectedFile\b|\bVaultPurger\b")),
    ("may create keys or own files", re.compile(r"\bmayCreateKeys\s*:\s*true\b|\bisOwner\s*:\s*true\b")),
    ("refreshes, fetches or holds credentials",
     re.compile(r"\b(RefreshCoordinator|CanvasClient|CanvasGateway|TokenCoordinator|CanvasCredential|CredentialStore"
                r"|KeychainCredentialStore|KeychainVaultKeyStore)\b")),
    ("uses the network", re.compile(r"\b(URLSession|URLRequest|NWConnection|NWPathMonitor)\b")),
    ("writes the Keychain or reads a password item",
     re.compile(r"\bSecItem(Add|Update|Delete)\b|\bkSecClassInternetPassword\b")),
    ("writes files", re.compile(r"\.write\s*\(\s*to\s*:|\b(removeItem|createDirectory|moveItem|copyItem)\s*\(")),
]


def _privacy_module():
    """check_privacy_manifest.py, for its project.yml/Package.swift reader and its source masker."""
    path = pathlib.Path(__file__).resolve().with_name("check_privacy_manifest.py")
    spec = importlib.util.spec_from_file_location("check_privacy_manifest", path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules["check_privacy_manifest"] = module  # dataclasses resolve their module by name
    spec.loader.exec_module(module)
    return module


def scan_sources(files: dict[str, str], mask) -> list[str]:
    problems = []
    for path, text in sorted(files.items()):
        masked = mask(text)
        for reason, pattern in FORBIDDEN_CODE:
            for m in pattern.finditer(masked):
                line = masked.count("\n", 0, m.start()) + 1
                problems.append(f"{path}:{line}: {reason}: `{m.group(0).strip()}`")
    return problems


def check_modules(modules: list[str]) -> list[str]:
    problems = [f"the widget links {name}" for name in FORBIDDEN_MODULES if name in modules]
    problems += [f"the widget does not link {name} (the glance reader)" for name in REQUIRED_MODULES if name not in modules]
    return problems


def run_sources(root: pathlib.Path) -> int:
    privacy = _privacy_module()
    bundle = privacy.Bundle("widget", WIDGET_TARGET, "apps/TallyiOS/TallyWidgets/PrivacyInfo.xcprivacy")
    try:
        _, modules, _ = privacy.shipping_source_dirs(root, bundle)
    except privacy.InputError as error:
        print(f"WIDGET | ERROR | input | {error}")
        return 2
    print(f"WIDGET | modules | {', '.join(modules)}")
    files = {}
    for directory in SOURCE_DIRS:
        base = root / directory
        if not base.is_dir():
            print(f"WIDGET | ERROR | input | {directory} does not exist")
            return 2
        for swift in sorted(base.rglob("*.swift")):
            files[swift.relative_to(root).as_posix()] = swift.read_text(encoding="utf-8")
    if not files:
        print("WIDGET | ERROR | input | no Swift sources found for the widget")
        return 2
    problems = check_modules(modules) + scan_sources(files, privacy.mask)
    for problem in problems:
        print(f"WIDGET | FAIL | {problem}")
    print(f"WIDGET | {'FAIL' if problems else 'PASS'} | sources | {len(files)} Swift files, "
          f"{len(modules)} modules, {len(problems)} problems")
    return 1 if problems else 0


MACHO_MAGICS = {b"\xfe\xed\xfa\xce", b"\xfe\xed\xfa\xcf", b"\xce\xfa\xed\xfe", b"\xcf\xfa\xed\xfe",
                b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"}


def _magic(path: pathlib.Path) -> bytes:
    with path.open("rb") as handle:
        return handle.read(4)


def link_map_counts(text: str) -> dict[str, int]:
    lines = text.split("\n")
    return {name: sum(1 for line in lines if name in line) for name in FORBIDDEN_MODULES + REQUIRED_MODULES}


def check_link_map(counts: dict[str, int]) -> list[str]:
    problems = [f"the Release widget's link map names {name} ({counts[name]} lines)"
                for name in FORBIDDEN_MODULES if counts[name]]
    problems += [f"the link map never names {name}: not the widget's map, or the glance reader is missing"
                 for name in REQUIRED_MODULES if not counts[name]]
    return problems


def check_load_commands(path: str, otool_output: str) -> list[str]:
    problems = [f"{path} loads {name}" for name in FORBIDDEN_MODULES if name in otool_output]
    problems += [f"{path} is itself {name}" for name in FORBIDDEN_MODULES if name in pathlib.PurePath(path).name]
    return problems


def run_binaries(link_map: str, bundles: list[str]) -> int:
    try:
        text = pathlib.Path(link_map).read_text(encoding="utf-8", errors="replace")
    except OSError as error:
        print(f"WIDGET | ERROR | input | cannot read the link map {link_map}: {error}")
        return 2
    counts = link_map_counts(text)
    print(f"WIDGET | link map | {link_map} ({text.count(chr(10))} lines) | "
          + ", ".join(f"{name}: {count}" for name, count in counts.items()))
    problems = check_link_map(counts)
    for bundle in bundles:
        base = pathlib.Path(bundle)
        if not base.is_dir():
            print(f"WIDGET | ERROR | input | {bundle} is not a directory")
            return 2
        machos = [p for p in sorted(base.rglob("*")) if p.is_file() and _magic(p) in MACHO_MAGICS]
        if not machos:
            print(f"WIDGET | ERROR | input | no Mach-O file in {bundle}")
            return 2
        for macho in machos:
            result = subprocess.run(["otool", "-L", str(macho)], capture_output=True, text=True)
            if result.returncode != 0:
                print(f"WIDGET | ERROR | input | otool -L {macho}: {result.stderr.strip()}")
                return 2
            loaded = [line.strip().split(" (")[0] for line in result.stdout.splitlines()[1:] if line.strip()]
            print(f"WIDGET | load commands | {macho} | {', '.join(loaded) or 'none'}")
            problems += check_load_commands(str(macho), result.stdout)
    for problem in problems:
        print(f"WIDGET | FAIL | {problem}")
    print(f"WIDGET | {'FAIL' if problems else 'PASS'} | binaries | {len(problems)} problems")
    return 1 if problems else 0


def self_test() -> int:
    privacy = _privacy_module()
    clean = {"a.swift": '''
        import SwiftUI
        import TallyGlance // import TallyFeatures in a comment is fine
        let note = "loadSnapshot( in a string is fine"
        let store = SnapshotStore(root: r, accountKey: k, sealer: s, isOwner: false)
        _ = await store.loadGlance()
    '''}
    assert scan_sources(clean, privacy.mask) == [], scan_sources(clean, privacy.mask)
    dirty = {"b.swift": '''
        @testable import TallyFeatures
        import TallySync
        _ = await store.loadSnapshot()
        let sealer = VaultSealer(account: a, keyring: k, mayCreateKeys: true)
        let session = URLSession.shared
        SecItemAdd(q as CFDictionary, nil)
        try data.write(to: url)
    '''}
    reasons = [p.split(": ", 2)[1] for p in scan_sources(dirty, privacy.mask)]
    assert reasons.count("imports a forbidden module") == 2, reasons
    for reason in ("decodes the snapshot", "may create keys or own files", "uses the network",
                   "writes the Keychain or reads a password item", "writes files"):
        assert reason in reasons, (reason, reasons)
    assert check_modules(["TallyDesignSystem", "TallyDomain", "TallyGlance", "TallyStore", "TallyWidgets"]) == []
    assert check_modules(["TallyGlance", "TallyStore", "TallyStrings", "TallyWidgets"]) == [], "TallyStrings is allowed"
    assert check_modules(["TallyGlance", "TallyStore", "TallyFeatures"]) == ["the widget links TallyFeatures"]
    assert len(check_modules(["TallyDesignSystem"])) == 2, "a closure without the glance reader must fail"

    link_map = "\n".join([
        "# Path: /x/TallyWidgets.appex/TallyWidgets",
        "[  1] /dd/Intermediates.noindex/TallyAppleKit.build/Release-iphoneos/TallyGlance.build/GlanceReader.o",
        "[  2] /dd/Intermediates.noindex/TallyCore.build/Release-iphoneos/TallyStore.build/SnapshotStore.o",
    ])
    assert check_link_map(link_map_counts(link_map)) == []
    bad_map = link_map + "\n[  3] /dd/TallyAppleKit.build/Release-iphoneos/TallyFeatures.build/AppModel.o"
    assert check_link_map(link_map_counts(bad_map)) == ["the Release widget's link map names TallyFeatures (1 lines)"]
    assert len(check_link_map(link_map_counts("# Path: /x/Other"))) == 2, "a map without the reader must fail"
    otool = "/x/TallyWidgets:\n\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0)\n"
    assert check_load_commands("/x/TallyWidgets", otool) == []
    assert check_load_commands("/x/TallyWidgets.debug.dylib",
                               otool + "\t@rpath/TallyFeatures.framework/TallyFeatures (x)\n") == \
        ["/x/TallyWidgets.debug.dylib loads TallyFeatures"]
    assert check_load_commands("/x/Frameworks/TallyPlatform.framework/TallyPlatform", otool) == \
        ["/x/Frameworks/TallyPlatform.framework/TallyPlatform is itself TallyPlatform"]
    print("check_widget_isolation self-test: 17 checks passed")
    return 0


def main(argv: list[str]) -> int:
    args = argv[1:]
    if args == ["--self-test"]:
        return self_test()
    if args[:1] == ["--sources"] and len(args) <= 2:
        return run_sources(pathlib.Path(args[1] if len(args) == 2 else ".").resolve())
    if args[:1] == ["--link-map"] and len(args) >= 4 and len(args) % 2 == 0:
        bundles = [value for flag, value in zip(args[2::2], args[3::2]) if flag == "--bundle"]
        if len(bundles) == (len(args) - 2) // 2:
            return run_binaries(args[1], bundles)
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
