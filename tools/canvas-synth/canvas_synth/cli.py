"""Command line: ``python3 -m canvas_synth generate --out <dir>``.

Deterministic: the same code produces byte-identical output (no clock, no
environment, no dict-order or hash-seed dependence, own PRNG)."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys

from . import personas as P
from . import fixtures as F
from . import scenarios as SC
from .docs import readme
from .emit import Out
from .jsonfmt import pretty_json
from .rebase import __doc__ as REBASE_DOC
from .schemas import BASE_ID, ENDPOINT_SCHEMA, all_schemas
from .toolschemas import tool_schemas
from .tz import iso_z

GENERATOR_VERSION = "1.0.0"

OBSERVER = {
    "canvas.northfield.example": {"id": 4820990, "observer_role_id": 21, "lti_user_id": "5f0c1e2d3a4b5c6d7e8f90a1b2c3d4e5f6a7b8c9",
                                  "feed_uuid": "PsObsNorthfield0000000000000000000000000"[:40],
                                  "email": "pat.sample@mail.example", "login_id": "pat.sample@mail.example"},
    "northgate.instructure.example": {"id": 6603990, "observer_role_id": 47,
                                      "lti_user_id": "a9b8c7d6e5f4a3b2c1d0e9f8a7b6c5d4e3f2a1b0",
                                      "feed_uuid": "PsObsNorthgate00000000000000000000000000"[:40],
                                      "email": "pat.sample@mail.example", "login_id": "pat.sample@mail.example"},
}


def build() -> Out:
    out = Out()
    manifest_personas = {}
    worlds = {}
    expected_index = {}
    for key, fn in P.ALL.items():
        p = fn()
        worlds[key] = p
        manifest_personas[key] = F.emit_persona(out, p, f"personas/{key}", seed=P.SEED)
        eg = F.expected_grades(p)
        out.json(f"expected/grades/{key}.json", eg)
        expected_index[key] = f"expected/grades/{key}.json"

    # (g) parent / observer: one person, one Canvas login per institution
    accounts = []
    for student_key, short in (("flagship", "northfield"), ("grading-periods", "northgate")):
        s = worlds[student_key]
        ob = dict(OBSERVER[s.host], name="Pat Sample", sortable_name="Sample, Pat")
        accounts.append(F.emit_observer_account(out, s, ob, f"personas/parent-observer/{short}", seed=P.SEED))
    # de-duplicate bodies that are byte-identical to the observee's own responses
    for acct, student_key in zip(accounts, ("flagship", "grading-periods")):
        own = manifest_personas[student_key]["routes"]
        for r in acct["routes"]:
            twin = next((x for x in own if x["endpoint"] == r["endpoint"]
                         and out.files.get(x["body"]) == out.files.get(r["body"])), None)
            if twin is not None:
                del out.files[r["body"]]
                r["body"] = twin["body"]
                r["body_shared_with"] = f"personas/{student_key}"
    manifest_personas["parent-observer"] = {
        "key": "parent-observer", "title": "Parent observing two students", "synthetic": True,
        "description": "Pat Sample observes Alex Sample (flagship, Northfield State University) and Jordan Sample "
                       "(grading-periods, Northgate Online Academy). Canvas observation links are per root account "
                       "(observation_link_root_account_ids), and the two schools are separate Canvas instances, "
                       "so the parent has one login per institution: two accounts, one observee each. Bodies "
                       "identical to the observee's own responses are shared (body_shared_with).",
        "captured_at": iso_z(P.ANCHOR), "anchor": iso_z(P.ANCHOR), "user_name": "Pat Sample",
        "time_zone": None, "accounts": accounts,
        "request_count": sum(a["request_count"] for a in accounts),
        "covers": ["observees list", "ObserverEnrollment rows with associated_user_id",
                   "observed students' scores in the observer's course list",
                   "submission arrays with include[]=observed_users", "planner via /users/:id/planner/items"],
    }
    for a in accounts:
        a["time_zone"] = worlds["flagship" if "northfield" in a["host"] else "grading-periods"].user.time_zone

    out.json("expected/digest/flagship.json", F.digest(worlds["flagship-previous"], worlds["flagship"]))

    scen, expected_scen = SC.emit_all_scenarios(out, P.SEED)
    out.json("expected/grades/scenarios.json", {
        "synthetic": True, "tolerance": 0.01, "captured_at": iso_z(P.ANCHOR),
        "calculator": "tools/canvas-synth/canvas_synth/gradecalc.py (port of canvas-lms lib/grade_calculator.rb "
                      "@ 1c9f0bb)", "scenarios": expected_scen})

    schemas = all_schemas()
    for name, s in schemas.items():
        out.json(f"schemas/{name}.schema.json", s)
    for name, s in tool_schemas().items():
        out.json(f"schemas/tally/{name}.schema.json", s)

    manifest = {
        "$schema": "schemas/tally/Manifest.schema.json",
        "synthetic": True,
        "provenance": {
            "statement": "Every person, school, course, domain and grade in this tree is fictional and generated. "
                         "No real student data, no recording.",
            "generator": "tools/canvas-synth", "generator_version": GENERATOR_VERSION,
            "command": "cd tools/canvas-synth && python3 -m canvas_synth generate --out ../../fixtures/canvas",
            "seed": P.SEED,
            "canvas_sources": {
                "docs": "https://developerdocs.instructure.com/services/canvas (retrieved 2026-09-26)",
                "code": "https://github.com/instructure/canvas-lms @ 1c9f0bb8013ed69c4f2efe11fd483025469b7e6c "
                        "(master; latest public commit 2026-04-30 as of 2026-09-26)",
            },
            "parity_caveat": "Synthetic grade parity proves consistency with this port of Canvas's algorithm, not "
                             "with production Canvas; an owner-run recording (WP-B07) is still required.",
        },
        "anchor": iso_z(P.ANCHOR),
        "rebasing": {"rule": " ".join(REBASE_DOC.split("\n\n", 1)[1].split()),
                     "reference_implementation": "tools/canvas-synth/canvas_synth/rebase.py"},
        "request_headers": {"Accept": "application/json+canvas-string-ids", "Authorization": "Bearer <token>",
                            "User-Agent": "Tally/<version>"},
        "route_matching": {
            "key": "method + host + path + normalized query",
            "query_normalization": "percent-decode every key and value, sort pairs by (key, value), join as "
                                   "k=v with '&', no re-encoding. 'query' is exact; 'query_match' replaces the "
                                   "values of start_date/end_date with '*' (match any value) so rebased demo "
                                   "requests still match. Follow Link rel=next URLs verbatim; their route "
                                   "entries carry the page parameter.",
            "unmatched_request": "respond 404 with errors/404-not-found.json",
        },
        "schema_map": {
            "personas/**/<endpoint files>, scenarios/<endpoint>/*.json": {k: f"schemas/{v[0]}.schema.json" +
                                                                         (" (array items)" if v[1] else "")
                                                                         for k, v in ENDPOINT_SCHEMA.items()},
            "**/*.headers.json": "schemas/HeadersSidecar.schema.json",
            "errors/*.json": "schemas/ErrorBody.schema.json", "errors/*.txt": "schemas/RateLimitText.schema.json",
            "expected/grades/*.json": "schemas/tally/ExpectedGrades.schema.json (scenarios.json: ExpectedScenarioGrades)",
            "expected/digest/*.json": "schemas/tally/Digest.schema.json",
            "manifest.json": "schemas/tally/Manifest.schema.json",
        },
        "personas": manifest_personas,
        "scenarios": scen,
        "expected": {"grades": expected_index | {"scenarios": "expected/grades/scenarios.json",
                                                 "parent-observer": "reuse flagship + grading-periods"},
                     "digest": {"flagship-previous->flagship": "expected/digest/flagship.json"}},
    }
    out.json("manifest.json", manifest)
    out.put("README.md", readme(manifest, out).encode("utf-8"))
    return out


def write(out: Out, dest: str):
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    for rel in sorted(out.files):
        path = os.path.join(dest, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(out.files[rel])


def tree_digest(dest: str) -> tuple[int, int, str]:
    h = hashlib.sha256()
    n = size = 0
    paths = []
    for root, _, files in os.walk(dest):
        for fn in files:
            paths.append(os.path.relpath(os.path.join(root, fn), dest))
    for rel in sorted(paths):
        data = open(os.path.join(dest, rel), "rb").read()
        h.update(rel.encode() + b"\0" + hashlib.sha256(data).digest())
        n += 1
        size += len(data)
    return n, size, h.hexdigest()


def main(argv=None):
    ap = argparse.ArgumentParser(prog="canvas_synth")
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("generate")
    g.add_argument("--out", required=True)
    d = sub.add_parser("digest")
    d.add_argument("dir")
    args = ap.parse_args(argv)
    if args.cmd == "generate":
        out = build()
        write(out, args.out)
        n, size, h = tree_digest(args.out)
        print(f"wrote {n} files, {size} bytes, tree sha256 {h}")
    else:
        n, size, h = tree_digest(args.dir)
        print(f"{n} files, {size} bytes, tree sha256 {h}")
    return 0
