"""Schema-validate every file under fixtures/canvas.

Requires ``jsonschema`` (run in the pinned container, see VALIDATION.md).
Exit status 1 if any file fails or is not covered by a schema.
"""
from __future__ import annotations

import json
import os
import sys
from collections import Counter

import importlib.metadata

import jsonschema
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from canvas_synth.schemas import ENDPOINT_SCHEMA  # noqa: E402

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else
                       os.path.join(os.path.dirname(__file__), "..", "..", "fixtures", "canvas"))


def main() -> int:
    schemas = {}
    for d in ("schemas", "schemas/tally"):
        for fn in sorted(os.listdir(os.path.join(ROOT, d))):
            if fn.endswith(".schema.json"):
                with open(os.path.join(ROOT, d, fn), encoding="utf-8") as f:
                    schemas[fn[:-len(".schema.json")]] = json.load(f)
    registry = Registry().with_resources((s["$id"], Resource.from_contents(s)) for s in schemas.values())

    def validator(name):
        return Draft202012Validator(schemas[name], registry=registry)

    manifest = json.load(open(os.path.join(ROOT, "manifest.json"), encoding="utf-8"))
    body_rule = {}

    def routes():
        for p in manifest["personas"].values():
            yield from p.get("routes", [])
            for a in p.get("accounts", []):
                yield from a["routes"]
        for s in manifest["scenarios"]:
            yield from s["routes"]

    for r in routes():
        if r["status"] != 200:
            body_rule[r["body"]] = ("RateLimitText", False) if r["body"].endswith(".txt") else ("ErrorBody", False)
        else:
            body_rule[r["body"]] = ENDPOINT_SCHEMA[r["endpoint"]]

    counts, failures, skipped = Counter(), [], []
    for d, _, files in os.walk(ROOT):
        for fn in sorted(files):
            path = os.path.join(d, fn)
            rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
            if rel == "README.md":
                skipped.append(rel)
                continue
            raw = open(path, "rb").read()
            if rel.startswith("schemas/"):
                try:
                    Draft202012Validator.check_schema(json.loads(raw))
                    counts["(metaschema) JSON Schema 2020-12"] += 1
                except jsonschema.SchemaError as e:
                    failures.append((rel, str(e).splitlines()[0]))
                continue
            if rel.endswith(".headers.json"):
                rule = ("HeadersSidecar", False)
            elif rel == "manifest.json":
                rule = ("Manifest", False)
            elif rel == "expected/grades/scenarios.json":
                rule = ("ExpectedScenarioGrades", False)
            elif rel.startswith("expected/grades/"):
                rule = ("ExpectedGrades", False)
            elif rel.startswith("expected/digest/"):
                rule = ("Digest", False)
            elif rel == "errors/index.json":
                rule = ("ErrorsIndex", False)
            elif rel.startswith("errors/"):
                rule = ("RateLimitText", False) if rel.endswith(".txt") else ("ErrorBody", False)
            elif rel == "scenarios/dates/iso8601-variants.json":
                rule = ("DateVariants", False)
            elif rel in body_rule:
                rule = body_rule[rel]
            else:
                failures.append((rel, "no schema mapping (file not referenced by the manifest)"))
                continue
            name, is_array = rule
            doc = raw.decode("utf-8") if name == "RateLimitText" else json.loads(raw)
            v = validator(name)
            if is_array:
                if not isinstance(doc, list):
                    failures.append((rel, f"expected a JSON array of {name}"))
                    continue
                errs = [e for item in doc for e in v.iter_errors(item)]
                label = f"{name}[]"
            else:
                errs = list(v.iter_errors(doc))
                label = name
            if errs:
                e = errs[0]
                failures.append((rel, f"{label}: {e.message[:200]} at {list(e.absolute_path)}"))
            else:
                counts[label] += 1

    total = sum(counts.values())
    print(f"jsonschema {importlib.metadata.version('jsonschema')}; fixtures root: {ROOT}")
    for k in sorted(counts):
        print(f"  {counts[k]:4d}  {k}")
    print(f"validated files: {total}; failures: {len(failures)}; skipped (not JSON fixtures): {skipped}")
    for rel, msg in failures:
        print(f"FAIL {rel}: {msg}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
