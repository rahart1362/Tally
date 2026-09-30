#!/usr/bin/env python3
"""Plan 08 §3.8 (L10N-01): Tally's String Catalogs are complete, consistent and ship-safe.

Checks every `.xcstrings` file under apps/ and packages/ (Xcode's String Catalog JSON):
  1. The catalog parses, its source language is English, and every key has an English value
     (semantic keys such as "dashboard.hero.averageOfCourses" are not text themselves) and a
     translator comment.
  2. Placeholder parity: every translation, and every plural form, uses the same format
     specifiers as English: the same types at the same positions (`%lld` is not `%@`; a
     mismatch crashes or misprints at run time). A plural form may leave the count out ("one"
     can read "One course"), never add one. `%%` is a literal percent sign.
  3. Plural forms: each language has every plural category it needs (en and es: one, other)
     and no category that does not exist.
  4. Shipping languages: the languages in any catalog are the ones the app and the widget
     declare in `apps/TallyiOS/project.yml` (`CFBundleLocalizations`, equal for both, with
     `CFBundleDevelopmentRegion: en`). A catalog language that does not ship fails: a partial
     translation on main would show a half-translated app. For each shipping language every key
     is `translated` (unless marked `shouldTranslate: false`).
  5. Code and catalog agree: every keyed lookup in Swift (`LocalizedStringResource("key",
     defaultValue: …)` or `String(localized: "key", defaultValue: …)`) names a key in the
     catalog of its own bundle (the TallyStrings target, or the widget's own catalog), with a
     plain `defaultValue` equal to the English value; every key in those catalogs is used; and
     no other shipping target makes keyed lookups (its bundle has no catalog: use `L10n`).

    python3 scripts/ci/check_string_catalogs.py [ROOT]
    python3 scripts/ci/check_string_catalogs.py --self-test

Exit 0 when every check passes, 1 when one fails, 2 when an input is missing or unreadable.
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

PROJECT_YML = "apps/TallyiOS/project.yml"
SHIPPING_TARGETS = ("Tally", "TallyWidgets")
SOURCE_LANGUAGE = "en"
# The catalogs that must exist (L10N-01), and the Swift sources that look keys up in each.
CATALOG_SOURCES = {
    "packages/TallyAppleKit/Sources/TallyStrings/Resources/Localizable.xcstrings":
        "packages/TallyAppleKit/Sources/TallyStrings",
    "apps/TallyiOS/TallyWidgets/Localizable.xcstrings": "apps/TallyiOS/TallyWidgets",
}
REQUIRED_CATALOGS = tuple(CATALOG_SOURCES) + (
    "apps/TallyiOS/Tally/InfoPlist.xcstrings",
    "apps/TallyiOS/TallyWidgets/InfoPlist.xcstrings",
)
# Shipping Swift that must not make keyed lookups of its own: its bundle has no catalog.
OTHER_SHIPPING_SOURCES = ("packages/TallyAppleKit/Sources", "apps/TallyiOS/Tally")
# CLDR plural categories each language needs; the others are optional. A language not listed
# needs "other" only.
REQUIRED_PLURALS = {"en": {"one", "other"}, "es": {"one", "other"}}
PLURAL_CATEGORIES = {"zero", "one", "two", "few", "many", "other"}

FORMAT = re.compile(
    r"%(?:(\d+)\$)?(#@\w+@|[-+ #0']*(?:\d+|\*)?(?:\.(?:\d+|\*))?(hh|h|ll|l|q|L|z|t|j)?([@dDiuUxXoOfFeEgGaAcCsSp%]))"
)
KEYED_LOOKUP = re.compile(
    r"(?:LocalizedStringResource\s*\(|String\s*\(\s*localized\s*:)\s*\"((?:[^\"\\]|\\.)*)\"\s*,\s*defaultValue\s*:\s*"
    r"(\"(?:[^\"\\]|\\.)*\")?", re.S)


class InputError(Exception):
    """An input could not be read or understood: exit 2, never a silent pass."""


# ------------------------------------------------------------------------------------------------
# Format specifiers
# ------------------------------------------------------------------------------------------------

def _kind(length: str | None, conversion: str) -> str:
    if conversion in "dDi":
        return f"{length or ''}d"
    if conversion in "uUxXoO":
        return f"{length or ''}u"
    if conversion in "fFeEgGaA":
        return f"{length or ''}f"
    return conversion  # @, c, C, s, S, p


def signature(value: str, substitutions: dict | None = None) -> dict[int, str]:
    """{argument position: kind} for a format string. `%#@name@` stands for a substitution's
    argument (`argNum`, `formatSpecifier`)."""
    result: dict[int, str] = {}
    next_position = 1
    for m in FORMAT.finditer(value):
        explicit, body, length, conversion = m.group(1), m.group(2), m.group(3), m.group(4)
        if conversion == "%":
            continue
        if body.startswith("#@"):
            name = body[2:-1]
            sub = (substitutions or {}).get(name)
            if not isinstance(sub, dict):
                raise ValueError(f"%#@{name}@ has no substitution")
            spec = str(sub.get("formatSpecifier", "@"))
            spec_match = re.fullmatch(r"(hh|h|ll|l|q|L|z|t|j)?([@dDiuUxXoOfFeEgGaAcCsSp])", spec)
            if not spec_match:
                raise ValueError(f"substitution {name} has format specifier {spec!r}")
            position = int(sub.get("argNum", next_position))
            kind = _kind(spec_match.group(1), spec_match.group(2))
        else:
            position = int(explicit) if explicit else next_position
            kind = _kind(length, conversion)
        if result.get(position, kind) != kind:
            raise ValueError(f"argument {position} is used as both {result[position]} and {kind}")
        result[position] = kind
        next_position = position + 1
    return result


# ------------------------------------------------------------------------------------------------
# One catalog
# ------------------------------------------------------------------------------------------------

def leaves(unit: dict, path: str = "") -> list[tuple[str, dict]]:
    """(variation path, stringUnit) for a localization: the unit itself, or every variant."""
    if "stringUnit" in unit:
        return [(path, unit["stringUnit"])]
    found: list[tuple[str, dict]] = []
    for kind, variants in (unit.get("variations") or {}).items():
        for category, inner in variants.items():
            found += leaves(inner, f"{path}{kind}.{category}/")
    return found


def plural_categories(unit: dict) -> list[set[str]]:
    """The category sets of every plural variation in a localization (nested ones included)."""
    sets: list[set[str]] = []
    variations = unit.get("variations") or {}
    for kind, variants in variations.items():
        if kind == "plural":
            sets.append(set(variants))
        for inner in variants.values():
            sets += plural_categories(inner)
    return sets


def check_catalog(name: str, catalog: object, shipping: list[str]) -> tuple[list[str], dict[str, str | None]]:
    """(problems, {key: plain English value, or None when it varies}) for one parsed catalog."""
    problems: list[str] = []
    english: dict[str, str | None] = {}
    if not isinstance(catalog, dict) or not isinstance(catalog.get("strings"), dict):
        return [f"{name}: not a String Catalog (no \"strings\")"], english
    if catalog.get("sourceLanguage") != SOURCE_LANGUAGE:
        problems.append(f"{name}: sourceLanguage is {catalog.get('sourceLanguage')!r}, not {SOURCE_LANGUAGE!r}")
    for key, entry in sorted(catalog["strings"].items()):
        where = f"{name}: {key!r}"
        if not isinstance(entry, dict):
            problems.append(f"{where}: not an object")
            continue
        if not str(entry.get("comment", "")).strip():
            problems.append(f"{where}: no translator comment")
        localizations = entry.get("localizations") or {}
        source = localizations.get(SOURCE_LANGUAGE)
        if not isinstance(source, dict) or not leaves(source):
            problems.append(f"{where}: no English value")
            continue
        substitutions = source.get("substitutions")
        try:
            source_leaves = leaves(source)
            english[key] = source_leaves[0][1].get("value") if len(source_leaves) == 1 and not source_leaves[0][0] else None
            reference = _reference_signature(source, substitutions)
        except ValueError as error:
            problems.append(f"{where} (en): {error}")
            continue
        for language, unit in sorted(localizations.items()):
            if language != SOURCE_LANGUAGE and language not in shipping:
                problems.append(f"{where}: has {language!r}, which is not a shipping language "
                                f"(CFBundleLocalizations {shipping}); main ships only declared languages")
                continue
            problems += _check_localization(where, language, unit, reference, substitutions)
        if entry.get("shouldTranslate") is False:
            continue
        for language in shipping:
            if language == SOURCE_LANGUAGE:
                continue
            unit = localizations.get(language)
            states = {leaf.get("state") for _, leaf in leaves(unit)} if isinstance(unit, dict) else set()
            if not unit or states != {"translated"}:
                problems.append(f"{where}: {language!r} ships but this key is not translated (states {sorted(map(str, states))})")
    return problems, english


def _reference_signature(source: dict, substitutions: dict | None) -> dict[int, str]:
    """English's signature: the union over its variants, which must not conflict."""
    reference: dict[int, str] = {}
    for _, leaf in leaves(source):
        for position, kind in signature(str(leaf.get("value", "")), substitutions).items():
            if reference.get(position, kind) != kind:
                raise ValueError(f"English variants disagree on argument {position}")
            reference[position] = kind
    return reference


def _check_localization(where: str, language: str, unit: object, reference: dict[int, str],
                        english_substitutions: dict | None) -> list[str]:
    problems: list[str] = []
    if not isinstance(unit, dict) or not leaves(unit):
        return [f"{where} ({language}): no value"]
    substitutions = unit.get("substitutions") or english_substitutions
    for path, leaf in leaves(unit):
        value = leaf.get("value")
        if not isinstance(value, str) or (not value.strip() and leaf.get("state") == "translated"):
            problems.append(f"{where} ({language} {path or 'value'}): empty value")
            continue
        try:
            found = signature(value, substitutions)
        except ValueError as error:
            problems.append(f"{where} ({language} {path or 'value'}): {error}")
            continue
        is_plural_form = "plural." in path
        extra = {p: k for p, k in found.items() if reference.get(p) != k}
        missing = {p: k for p, k in reference.items() if p not in found}
        if extra or (missing and not is_plural_form):
            problems.append(f"{where} ({language} {path or 'value'}): placeholders {_show(found)} do not match "
                            f"English {_show(reference)}")
    required = REQUIRED_PLURALS.get(language.split("-")[0], {"other"})
    for categories in plural_categories(unit):
        unknown = categories - PLURAL_CATEGORIES
        absent = required - categories
        if unknown:
            problems.append(f"{where} ({language}): unknown plural categories {sorted(unknown)}")
        if absent:
            problems.append(f"{where} ({language}): missing plural categories {sorted(absent)}")
    return problems


def _show(sig: dict[int, str]) -> str:
    return "[" + ", ".join(f"{p}:%{k}" for p, k in sorted(sig.items())) + "]"


# ------------------------------------------------------------------------------------------------
# project.yml: the shipping languages
# ------------------------------------------------------------------------------------------------

def shipping_languages(project: str) -> tuple[list[str], list[str]]:
    """(the shipping languages, problems) from the app's and the widget's info properties."""
    per_target: dict[str, dict[str, object]] = {}
    section, target, collecting, collected_indent = None, None, None, 0
    for raw in project.split("\n"):
        line = re.sub(r"(^|\s)#.*$", "", raw).rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(" "))
        body = line.strip()
        if collecting is not None:
            if indent > collected_indent and body.startswith("- "):
                per_target[target][collecting].append(body[2:].strip().strip("\"'"))  # type: ignore[union-attr]
                continue
            collecting = None
        if indent == 0:
            section = body[:-1] if body.endswith(":") else None
            target = None
            continue
        if section == "targets" and indent == 2 and body.endswith(":"):
            target = body[:-1]
            per_target.setdefault(target, {})
            continue
        if section != "targets" or target not in SHIPPING_TARGETS:
            continue
        key, _, value = body.partition(":")
        if key == "CFBundleLocalizations":
            value = value.strip()
            if value.startswith("["):
                per_target[target][key] = [v.strip().strip("\"'") for v in value.strip("[]").split(",") if v.strip()]
            else:
                per_target[target][key] = []
                collecting, collected_indent = key, indent
        elif key == "CFBundleDevelopmentRegion":
            per_target[target][key] = value.strip().strip("\"'")
    problems: list[str] = []
    languages: list[list[str]] = []
    for name in SHIPPING_TARGETS:
        props = per_target.get(name, {})
        if props.get("CFBundleDevelopmentRegion") != SOURCE_LANGUAGE:
            problems.append(f"{PROJECT_YML}: {name} sets CFBundleDevelopmentRegion "
                            f"{props.get('CFBundleDevelopmentRegion')!r}, not {SOURCE_LANGUAGE!r}")
        declared = props.get("CFBundleLocalizations")
        if not isinstance(declared, list) or SOURCE_LANGUAGE not in declared:
            problems.append(f"{PROJECT_YML}: {name} must list CFBundleLocalizations including {SOURCE_LANGUAGE!r} "
                            f"(found {declared!r})")
            declared = [SOURCE_LANGUAGE]
        languages.append(sorted(set(declared)))
    if len(languages) == 2 and languages[0] != languages[1]:
        problems.append(f"{PROJECT_YML}: the app ships {languages[0]} but the widget ships {languages[1]}")
    return (languages[0] if languages else [SOURCE_LANGUAGE]), problems


# ------------------------------------------------------------------------------------------------
# Swift keyed lookups
# ------------------------------------------------------------------------------------------------

def _mask_comments(text: str) -> str:
    return re.sub(r"//[^\n]*|/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)), text, flags=re.S)


def keyed_lookups(text: str) -> list[tuple[str, str | None, int]]:
    """(key, plain default value or None, line) for each keyed lookup in Swift source."""
    masked = _mask_comments(text)
    found = []
    for m in KEYED_LOOKUP.finditer(masked):
        default = m.group(2)
        plain = None
        if default is not None and "\\(" not in default and "\\u{" not in default:
            try:
                plain = json.loads(default)  # Swift's \" \\ \n \t escapes read the same in JSON
            except json.JSONDecodeError:
                plain = None
        found.append((m.group(1), plain, masked.count("\n", 0, m.start()) + 1))
    return found


def check_code(catalog_name: str, english: dict[str, str | None], sources: dict[str, str]) -> list[str]:
    problems: list[str] = []
    used: set[str] = set()
    for path, text in sorted(sources.items()):
        for key, default, line in keyed_lookups(text):
            used.add(key)
            if key not in english:
                problems.append(f"{path}:{line}: key {key!r} is not in {catalog_name}")
            elif default is not None and english[key] is not None and default != english[key]:
                problems.append(f"{path}:{line}: the defaultValue for {key!r} is {default!r}, "
                                f"but the catalog's English is {english[key]!r}")
    for key in sorted(set(english) - used):
        problems.append(f"{catalog_name}: key {key!r} is never used in code (remove it, or add its L10n wrapper)")
    return problems


def check_stray_lookups(sources: dict[str, str]) -> list[str]:
    return [f"{path}:{line}: keyed lookup {key!r} in a target with no String Catalog; add the string to "
            f"TallyStrings and use L10n" for path, text in sorted(sources.items()) for key, _, line in keyed_lookups(text)]


# ------------------------------------------------------------------------------------------------
# The repository
# ------------------------------------------------------------------------------------------------

def _swift_sources(root: pathlib.Path, directory: str, skip: tuple[str, ...] = ()) -> dict[str, str]:
    base = root / directory
    if not base.is_dir():
        raise InputError(f"{directory} does not exist")
    sources = {}
    for swift in sorted(base.rglob("*.swift")):
        relative = swift.relative_to(root).as_posix()
        if any(relative.startswith(s + "/") for s in skip) or any(p.startswith(".build") for p in relative.split("/")):
            continue
        sources[relative] = swift.read_text(encoding="utf-8")
    return sources


def run(root: pathlib.Path) -> int:
    try:
        project = (root / PROJECT_YML).read_text(encoding="utf-8")
        catalogs = sorted(p for d in ("apps", "packages") for p in (root / d).rglob("*.xcstrings")
                          if not any(part.startswith(".build") or part == "DerivedData" for part in p.parts))
        shipping, problems = shipping_languages(project)
        missing = [c for c in REQUIRED_CATALOGS if not (root / c).is_file()]
        problems += [f"{c}: missing (plan 08 L10N-01)" for c in missing]
        english_by_catalog: dict[str, dict[str, str | None]] = {}
        keys = 0
        for path in catalogs:
            name = path.relative_to(root).as_posix()
            try:
                catalog = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
                problems.append(f"{name}: cannot parse: {error}")
                continue
            found, english = check_catalog(name, catalog, shipping)
            problems += found
            english_by_catalog[name] = english
            keys += len(english)
        catalog_dirs = tuple(CATALOG_SOURCES.values())
        for catalog_name, source_dir in CATALOG_SOURCES.items():
            if catalog_name in english_by_catalog:
                problems += check_code(catalog_name, english_by_catalog[catalog_name], _swift_sources(root, source_dir))
        for directory in OTHER_SHIPPING_SOURCES:
            problems += check_stray_lookups(_swift_sources(root, directory, skip=catalog_dirs))
    except (OSError, UnicodeDecodeError, InputError) as error:
        print(f"CATALOG | ERROR | input | {error}")
        return 2
    if not catalogs:
        print("CATALOG | ERROR | input | no .xcstrings files found")
        return 2
    for problem in problems:
        print(f"CATALOG | FAIL | {problem}")
    print(f"CATALOG | {'FAIL' if problems else 'PASS'} | {len(catalogs)} catalogs, {keys} keys, "
          f"shipping {shipping} | {len(problems)} problems")
    return 1 if problems else 0


# ------------------------------------------------------------------------------------------------
# Self-test
# ------------------------------------------------------------------------------------------------

def _unit(value: str, state: str = "translated") -> dict:
    return {"stringUnit": {"state": state, "value": value}}


def _plural(forms: dict[str, str]) -> dict:
    return {"variations": {"plural": {k: _unit(v) for k, v in forms.items()}}}


def _catalog(strings: dict) -> dict:
    return {"sourceLanguage": "en", "version": "1.0", "strings": strings}


def self_test() -> int:
    checks = 0

    def expect(condition: bool, message: object) -> None:
        nonlocal checks
        checks += 1
        assert condition, message

    def problems_of(strings: dict, shipping: list[str] | None = None) -> list[str]:
        return check_catalog("c.xcstrings", _catalog(strings), shipping or ["en"])[0]

    # Signatures.
    expect(signature("Average of %lld courses") == {1: "lld"}, signature("Average of %lld courses"))
    expect(signature("%1$@ out of %2$@") == {1: "@", 2: "@"}, "positional")
    expect(signature("%2$@ de %1$@") == {1: "@", 2: "@"}, "reordered")
    expect(signature("90%% of %d") == {1: "d"}, "literal percent")
    expect(signature("%i and %lu") == {1: "d", 2: "lu"}, "i is d")
    expect(signature("%#@items@", {"items": {"argNum": 1, "formatSpecifier": "lld"}}) == {1: "lld"}, "substitution")

    good = {"k": {"comment": "c", "localizations": {"en": _plural({"one": "Average of %lld course",
                                                                        "other": "Average of %lld courses"})}}}
    expect(problems_of(good) == [], problems_of(good))
    es = dict(good["k"]["localizations"], es=_plural({"one": "Promedio de %lld curso", "other": "Promedio de %lld cursos"}))
    expect(problems_of({"k": {"comment": "c", "localizations": es}}, ["en", "es"]) == [], "es ships and is complete")
    # A language that does not ship fails: main ships en only.
    expect(any("not a shipping language" in p for p in problems_of({"k": {"comment": "c", "localizations": es}})),
           "partial es on main")
    # Placeholder parity.
    bad_type = dict(es, es=_plural({"one": "Promedio de %@ curso", "other": "Promedio de %@ cursos"}))
    expect(len([p for p in problems_of({"k": {"comment": "c", "localizations": bad_type}}, ["en", "es"])
                if "do not match" in p]) == 2, "type mismatch in both forms")
    one_without_number = dict(es, es=_plural({"one": "Un curso", "other": "%lld cursos"}))
    expect(problems_of({"k": {"comment": "c", "localizations": one_without_number}}, ["en", "es"]) == [],
           "a plural form may omit the count")
    other_without_number = dict(es, es=_plural({"one": "%lld curso", "other": "Cursos"}))
    expect(problems_of({"k": {"comment": "c", "localizations": other_without_number}}, ["en", "es"]) == [],
           "any plural form may omit it")
    extra = {"k": {"comment": "c", "localizations": {"en": _unit("%1$@ out of %2$@"),
                                                     "es": _unit("%1$@ de %2$@ (%3$@)")}}}
    expect(any("do not match" in p for p in problems_of(extra, ["en", "es"])), "an extra placeholder")
    dropped = {"k": {"comment": "c", "localizations": {"en": _unit("%1$@ out of %2$@"), "es": _unit("%1$@")}}}
    expect(any("do not match" in p for p in problems_of(dropped, ["en", "es"])), "a dropped placeholder")
    reordered = {"k": {"comment": "c", "localizations": {"en": _unit("%1$@ out of %2$@"), "es": _unit("%2$@: %1$@")}}}
    expect(problems_of(reordered, ["en", "es"]) == [], "positional reordering is fine")
    # Plural categories.
    no_one = {"k": {"comment": "c", "localizations": {"en": _plural({"other": "%lld courses"})}}}
    expect(any("missing plural categories ['one']" in p for p in problems_of(no_one)), problems_of(no_one))
    odd = {"k": {"comment": "c", "localizations": {"en": _plural({"one": "%lld", "other": "%lld", "several": "%lld"})}}}
    expect(any("unknown plural categories" in p for p in problems_of(odd)), "unknown category")
    # English value, comment, state.
    expect(any("no English value" in p for p in problems_of({"k": {"comment": "c", "localizations": {}}})), "no en")
    expect(any("no translator comment" in p for p in problems_of({"k": {"localizations": {"en": _unit("Hi")}}})),
           "no comment")
    untranslated = {"k": {"comment": "c", "localizations": {"en": _unit("Hi"), "es": _unit("Hola", "needs_review")}}}
    expect(any("not translated" in p for p in problems_of(untranslated, ["en", "es"])), "needs_review")
    absent = {"k": {"comment": "c", "localizations": {"en": _unit("Hi")}}}
    expect(any("not translated" in p for p in problems_of(absent, ["en", "es"])), "missing es")
    expect(problems_of({"k": {"comment": "c", "shouldTranslate": False, "localizations": {"en": _unit("Tally")}}},
                       ["en", "es"]) == [], "shouldTranslate false")
    expect(check_catalog("c", {"sourceLanguage": "fr", "strings": {}}, ["en"])[0] != [], "source language")

    # project.yml.
    yml = ("targets:\n  Tally:\n    info:\n      properties:\n        CFBundleDevelopmentRegion: en\n"
           "        CFBundleLocalizations:\n          - en\n        CFBundleVersion: \"1\"\n"
           "  TallyWidgets:\n    info:\n      properties:\n        CFBundleDevelopmentRegion: en\n"
           "        CFBundleLocalizations: [en]\n")
    expect(shipping_languages(yml) == (["en"], []), shipping_languages(yml))
    expect(shipping_languages(yml.replace("CFBundleLocalizations: [en]", "CFBundleLocalizations: [en, es]"))[1] != [],
           "app and widget differ")
    expect(shipping_languages(yml.replace("CFBundleDevelopmentRegion: en\n        CFBundleLocalizations:\n",
                                          "CFBundleLocalizations:\n"))[1] != [], "no development region")
    expect(shipping_languages("targets:\n  Tally:\n    x: 1\n")[1] != [], "nothing declared")

    # Code and catalog.
    swift = ('let a = LocalizedStringResource(\n    "k.a", defaultValue: "Next Up",\n    comment: "c")\n'
             'let b = LocalizedStringResource("k.b", defaultValue: "Due \\(n)", bundle: #bundle, comment: "c")\n'
             '// LocalizedStringResource("k.commented", defaultValue: "x")\n')
    expect([(k, d) for k, d, _ in keyed_lookups(swift)] == [("k.a", "Next Up"), ("k.b", None)], keyed_lookups(swift))
    expect(check_code("cat", {"k.a": "Next Up", "k.b": None}, {"a.swift": swift}) == [], "code and catalog agree")
    expect(any("is not in cat" in p for p in check_code("cat", {"k.b": None}, {"a.swift": swift})), "unknown key")
    expect(any("never used" in p for p in check_code("cat", {"k.a": "Next Up", "k.b": None, "k.c": "x"},
                                                        {"a.swift": swift})), "unused key")
    expect(any("defaultValue" in p for p in check_code("cat", {"k.a": "Next up", "k.b": None}, {"a.swift": swift})),
           "default value drift")
    expect(len(check_stray_lookups({"f.swift": swift})) == 2, "lookups outside a catalog's target")
    print(f"check_string_catalogs self-test: {checks} checks passed")
    return 0


def main(argv: list[str]) -> int:
    args = argv[1:]
    if args == ["--self-test"]:
        return self_test()
    if len(args) <= 1 and not (args and args[0].startswith("--")):
        return run(pathlib.Path(args[0] if args else ".").resolve())
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
