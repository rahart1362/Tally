#!/usr/bin/env python3
"""Plan 08 L10N-04: the review pack the paid native-speaker reviewer works from.

The owner's 2026-10-11 decision is "machine pass now, review later": every Spanish value L10N-04
wrote carries the catalog state `needs_review`. This script is the only supported way to move a
row to `translated` — never hand-edit the `.xcstrings` files (they are JSON; the brief's host note
says edit them with a script, to keep Xcode's key order and 2-space formatting reviewable).

    python3 scripts/l10n/es_review.py export --out CSV [ROOT]
        Writes one CSV row per Spanish leaf (a plain value, or one row per plural category) across
        every `.xcstrings` catalog under apps/ and packages/ that has an "es" localization: key,
        catalog (the file's path, relative to ROOT), plural form ("" for a plain value), the
        translator comment, the English value, the current Spanish value, and its state. CSV goes
        wherever --out says (the evidence folder, per the brief — never into the repo).
    python3 scripts/l10n/es_review.py apply CSV [ROOT]
        Reads the reviewer's CSV back (same columns; the reviewer edits "spanish" and, to approve
        a row, changes "state" from needs_review to translated) and writes every row's Spanish
        value into its catalog. A row whose state is "translated" must keep the same format
        specifiers (type and position, `%%` literal) as the English reference: a mismatch refuses
        that one row (it is not written) and the run exits 1, so a reviewer's typo never ships a
        crash. A row not marked "translated" still has its (possibly corrected) wording written,
        at whatever state the CSV gives it — a reviewer can fix wording now and approve later.
    python3 scripts/l10n/es_review.py --self-test

Exit codes: 0 every row applied (or export succeeded); 1 `apply` refused at least one row (every
other row still applied); 2 an input could not be read or understood.
"""
from __future__ import annotations

import csv
import json
import pathlib
import re
import sys

FIELDS = ["key", "catalog", "plural_form", "comment", "english", "spanish", "state"]
ALLOWED_STATES = {"translated", "needs_review"}

FORMAT = re.compile(
    r"%(?:(\d+)\$)?l*[dioux@sfcp%]|%%", re.IGNORECASE
)


class InputError(Exception):
    """An input could not be read or understood: exit 2, never a silent pass."""


# --------------------------------------------------------------------------------------------
# Format specifiers (a smaller, standalone check: the real gate is
# scripts/ci/check_string_catalogs.py, run after this script; this one just keeps a reviewer's
# typo from reaching `translated`, which is the only state the release gate trusts).
# --------------------------------------------------------------------------------------------

def signature(value: str) -> list[tuple[int | None, str]]:
    """[(explicit position or None, the specifier's own text)] in the order they appear."""
    found = []
    for m in FORMAT.finditer(value):
        text = m.group(0)
        if text == "%%":
            continue
        position = int(m.group(1)) if m.group(1) else None
        # Strip the leading "%" and any "N$" positional prefix, but KEEP any length modifier
        # ("l", "ll"): %d and %lld are different argument types (Int32 vs Int), the same
        # distinction check_string_catalogs.py's _kind() makes.
        kind = re.sub(r"^\d+\$", "", text[1:])
        found.append((position, kind))
    return found


def placeholders_match(english: str, candidate: str) -> bool:
    """Same positions and kinds as English (position-normalized: an explicit %1$@ matches a bare
    %@ in the same slot). A candidate may drop a placeholder (one plural form may read "One
    course"), never add one English doesn't have."""
    ref = _normalize(signature(english))
    got = _normalize(signature(candidate))
    return set(got.items()) <= set(ref.items())


def _normalize(sig: list[tuple[int | None, str]]) -> dict[int, str]:
    out: dict[int, str] = {}
    next_position = 1
    for position, kind in sig:
        p = position if position is not None else next_position
        out[p] = kind
        next_position = p + 1
    return out


# --------------------------------------------------------------------------------------------
# Catalog traversal (mirrors check_string_catalogs.py's `leaves`, kept standalone on purpose:
# this script must run correctly even if that one's internals change shape).
# --------------------------------------------------------------------------------------------

def leaves(unit: dict, path: str = "") -> list[tuple[str, dict]]:
    if "stringUnit" in unit:
        return [(path, unit["stringUnit"])]
    found: list[tuple[str, dict]] = []
    for kind, variants in (unit.get("variations") or {}).items():
        for category, inner in variants.items():
            found += leaves(inner, f"{path}{category}" if kind == "plural" else f"{path}{kind}.{category}/")
    return found


def english_leaf_value(entry: dict, plural_form: str) -> str | None:
    source = (entry.get("localizations") or {}).get("en")
    if not isinstance(source, dict):
        return None
    for path, leaf in leaves(source):
        if (path or "") == (plural_form or ""):
            return leaf.get("value")
    return None


# --------------------------------------------------------------------------------------------
# export
# --------------------------------------------------------------------------------------------

def find_catalogs(root: pathlib.Path) -> list[pathlib.Path]:
    return sorted(
        p for d in ("apps", "packages") for p in (root / d).rglob("*.xcstrings")
        if not any(part.startswith(".build") or part == "DerivedData" for part in p.parts)
    )


def export(root: pathlib.Path, out: pathlib.Path) -> int:
    rows = []
    for path in find_catalogs(root):
        try:
            catalog = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise InputError(f"{path}: cannot parse: {error}") from error
        name = path.relative_to(root).as_posix()
        for key, entry in sorted(catalog.get("strings", {}).items()):
            es = (entry.get("localizations") or {}).get("es")
            if not isinstance(es, dict):
                continue
            comment = str(entry.get("comment", ""))
            for plural_form, leaf in leaves(es):
                english = english_leaf_value(entry, plural_form) or ""
                rows.append({
                    "key": key,
                    "catalog": name,
                    "plural_form": plural_form,
                    "comment": comment,
                    "english": english,
                    "spanish": leaf.get("value", ""),
                    "state": leaf.get("state", ""),
                })
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    print(f"ES-REVIEW | EXPORT | {len(rows)} rows, {len(find_catalogs(root))} catalogs -> {out}")
    return 0


# --------------------------------------------------------------------------------------------
# apply
# --------------------------------------------------------------------------------------------

def _set_leaf_value(entry: dict, plural_form: str, value: str, state: str) -> bool:
    es = (entry.setdefault("localizations", {})).get("es")
    if not isinstance(es, dict):
        return False
    if not plural_form:
        if "stringUnit" not in es:
            return False
        es["stringUnit"] = {"state": state, "value": value}
        return True
    # plural_form is the plural category ("one", "other", ...): leaves() prefixes nothing for
    # a plural leaf's path other than the bare category name (see leaves() above).
    plural = (es.get("variations") or {}).get("plural")
    if not isinstance(plural, dict) or plural_form not in plural:
        return False
    plural[plural_form] = {"stringUnit": {"state": state, "value": value}}
    return True


def apply_csv(root: pathlib.Path, csv_path: pathlib.Path) -> int:
    with csv_path.open(encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames != FIELDS:
            raise InputError(f"{csv_path}: expected columns {FIELDS}, found {reader.fieldnames}")
        rows = list(reader)

    by_catalog: dict[str, dict] = {}
    refused = 0
    applied = 0
    for row in rows:
        catalog_name = row["catalog"]
        path = root / catalog_name
        if catalog_name not in by_catalog:
            try:
                by_catalog[catalog_name] = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
                raise InputError(f"{path}: cannot parse: {error}") from error
        catalog = by_catalog[catalog_name]
        key = row["key"]
        entry = catalog.get("strings", {}).get(key)
        if entry is None:
            print(f"ES-REVIEW | REFUSED | {catalog_name}: {key!r} is no longer in the catalog")
            refused += 1
            continue
        state = row["state"].strip() or "needs_review"
        if state not in ALLOWED_STATES:
            print(f"ES-REVIEW | REFUSED | {catalog_name}: {key!r} ({row['plural_form'] or 'value'}): "
                  f"unknown state {state!r}")
            refused += 1
            continue
        english = english_leaf_value(entry, row["plural_form"]) or row["english"]
        if state == "translated" and not placeholders_match(english, row["spanish"]):
            print(f"ES-REVIEW | REFUSED | {catalog_name}: {key!r} ({row['plural_form'] or 'value'}): "
                  f"placeholders {signature(row['spanish'])} do not match English {signature(english)}")
            refused += 1
            continue
        if not _set_leaf_value(entry, row["plural_form"], row["spanish"], state):
            print(f"ES-REVIEW | REFUSED | {catalog_name}: {key!r} ({row['plural_form'] or 'value'}): "
                  f"no matching 'es' leaf to update (catalog shape changed since export)")
            refused += 1
            continue
        applied += 1

    for catalog_name, catalog in by_catalog.items():
        path = root / catalog_name
        path.write_text(
            json.dumps(catalog, indent=2, ensure_ascii=False, separators=(",", " : ")) + "\n",
            encoding="utf-8")

    print(f"ES-REVIEW | APPLY | {applied} applied, {refused} refused, {len(by_catalog)} catalogs written")
    return 1 if refused else 0


# --------------------------------------------------------------------------------------------
# Self-test
# --------------------------------------------------------------------------------------------

def self_test() -> int:
    import tempfile

    checks = 0

    def expect(condition: bool, message: object) -> None:
        nonlocal checks
        checks += 1
        assert condition, message

    # Format specifiers.
    expect(signature("Add %@ to Calendar") == [(None, "@")], signature("Add %@ to Calendar"))
    expect(signature("%1$@ out of %2$@") == [(1, "@"), (2, "@")], "positional")
    expect(signature("90%% of %d") == [(None, "d")], "literal percent is not a placeholder")
    expect(placeholders_match("%1$@ out of %2$@", "%2$@ de %1$@"), "reordering is fine")
    expect(not placeholders_match("%1$@ out of %2$@", "%1$@ de %2$@ (%3$@)"), "an extra placeholder")
    expect(not placeholders_match("%@ out of %@", "%d de %d"), "a type mismatch")
    expect(placeholders_match("%lld course", "Un curso"), "a plural form may drop the count")

    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        catalog_path = root / "packages/TallyAppleKit/Sources/TallyStrings/Resources/Localizable.xcstrings"
        catalog_path.parent.mkdir(parents=True)
        catalog = {
            "sourceLanguage": "en",
            "version": "1.0",
            "strings": {
                "account.done": {
                    "comment": "Dismiss button.",
                    "localizations": {
                        "en": {"stringUnit": {"state": "translated", "value": "Done"}},
                        "es": {"stringUnit": {"state": "needs_review", "value": "Listo"}},
                    },
                },
                "dashboard.hero.averageOfCourses": {
                    "comment": "Plural.",
                    "localizations": {
                        "en": {"variations": {"plural": {
                            "one": {"stringUnit": {"state": "translated", "value": "Average of %lld course"}},
                            "other": {"stringUnit": {"state": "translated", "value": "Average of %lld courses"}},
                        }}},
                        "es": {"variations": {"plural": {
                            "one": {"stringUnit": {"state": "needs_review", "value": "Promedio de %lld curso"}},
                            "other": {"stringUnit": {"state": "needs_review", "value": "Promedio de %lld cursos"}},
                        }}},
                    },
                },
            },
        }
        catalog_path.write_text(json.dumps(catalog), encoding="utf-8")

        # export
        out_csv = root / "evidence" / "es-review.csv"
        expect(export(root, out_csv) == 0, "export exits 0")
        with out_csv.open(encoding="utf-8", newline="") as f:
            exported = list(csv.DictReader(f))
        expect(len(exported) == 3, f"1 plain leaf + 2 plural leaves: {exported}")
        expect({r["key"] for r in exported} == {"account.done", "dashboard.hero.averageOfCourses"},
               "both keys present")
        done_row = next(r for r in exported if r["key"] == "account.done")
        expect(done_row["english"] == "Done" and done_row["spanish"] == "Listo"
               and done_row["state"] == "needs_review" and done_row["plural_form"] == "", done_row)

        # apply: approve the plain key (translated, unchanged wording).
        approve_csv = root / "evidence" / "approve.csv"
        rows = exported
        for row in rows:
            if row["key"] == "account.done":
                row["state"] = "translated"
        with approve_csv.open("w", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=FIELDS)
            writer.writeheader()
            writer.writerows(rows)
        expect(apply_csv(root, approve_csv) == 0, "apply exits 0 when nothing is refused")
        reloaded = json.loads(catalog_path.read_text(encoding="utf-8"))
        es_done = reloaded["strings"]["account.done"]["localizations"]["es"]["stringUnit"]
        expect(es_done == {"state": "translated", "value": "Listo"}, es_done)
        # The un-approved plural key's wording is still exactly what was exported (untouched).
        es_plural_one = reloaded["strings"]["dashboard.hero.averageOfCourses"]["localizations"]["es"]["variations"]["plural"]["one"]["stringUnit"]
        expect(es_plural_one == {"state": "needs_review", "value": "Promedio de %lld curso"}, es_plural_one)

        # apply: a reviewer's corrected wording for a non-approved row is still written.
        reword_csv = root / "evidence" / "reword.csv"
        for row in rows:
            if row["key"] == "dashboard.hero.averageOfCourses" and row["plural_form"] == "other":
                row["spanish"] = "Promedio de %lld cursos (corregido)"
        with reword_csv.open("w", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=FIELDS)
            writer.writeheader()
            writer.writerows(rows)
        expect(apply_csv(root, reword_csv) == 0, "a wording-only fix is not a refusal")
        reloaded2 = json.loads(catalog_path.read_text(encoding="utf-8"))
        es_other = reloaded2["strings"]["dashboard.hero.averageOfCourses"]["localizations"]["es"]["variations"]["plural"]["other"]["stringUnit"]
        expect(es_other == {"state": "needs_review", "value": "Promedio de %lld cursos (corregido)"}, es_other)

        # apply: a row marked translated with a broken placeholder is refused, others still apply.
        broken_csv = root / "evidence" / "broken.csv"
        for row in rows:
            if row["key"] == "dashboard.hero.averageOfCourses" and row["plural_form"] == "other":
                row["state"] = "translated"
                row["spanish"] = "Promedio de %d cursos"  # %d, not %lld: a type mismatch
        with broken_csv.open("w", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=FIELDS)
            writer.writeheader()
            writer.writerows(rows)
        expect(apply_csv(root, broken_csv) == 1, "a broken placeholder refuses and exits 1")
        reloaded3 = json.loads(catalog_path.read_text(encoding="utf-8"))
        es_other3 = reloaded3["strings"]["dashboard.hero.averageOfCourses"]["localizations"]["es"]["variations"]["plural"]["other"]["stringUnit"]
        expect(es_other3["state"] == "needs_review", "the refused row's state is unchanged, not flipped to translated")
        es_done3 = reloaded3["strings"]["account.done"]["localizations"]["es"]["stringUnit"]
        expect(es_done3["state"] == "translated", "the other, unrelated row in the same apply is unaffected")

    print(f"es_review self-test: {checks} checks passed")
    return 0


def main(argv: list[str]) -> int:
    args = argv[1:]
    try:
        if args == ["--self-test"]:
            return self_test()
        if args and args[0] == "export":
            rest = args[1:]
            if len(rest) >= 2 and rest[0] == "--out":
                out = pathlib.Path(rest[1])
                root = pathlib.Path(rest[2]).resolve() if len(rest) > 2 else pathlib.Path(".").resolve()
                return export(root, out)
        if args and args[0] == "apply":
            rest = args[1:]
            if len(rest) >= 1:
                csv_path = pathlib.Path(rest[0])
                root = pathlib.Path(rest[1]).resolve() if len(rest) > 1 else pathlib.Path(".").resolve()
                return apply_csv(root, csv_path)
    except InputError as error:
        print(f"ES-REVIEW | ERROR | input | {error}")
        return 2
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
