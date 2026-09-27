"""Contract self-checks over the generated tree, reading only fixture files
(the client's view): grade parity, string ids, pagination chains, mockup values.
FIXTURES_DIR overrides the default ../../fixtures/canvas."""
import json
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from canvas_synth import gradecalc as G  # noqa: E402
from canvas_synth.emit import normalize_query, parse_url  # noqa: E402

ROOT = os.environ.get("FIXTURES_DIR") or os.path.join(os.path.dirname(__file__), "..", "..", "..", "fixtures", "canvas")
ID_KEY = re.compile(r"(^|_)id$")
IDS_KEY = re.compile(r"(^|_)ids$")


def load(rel):
    with open(os.path.join(ROOT, rel), "rb") as f:
        return json.loads(f.read())


def route_sets():
    m = load("manifest.json")
    for key, p in m["personas"].items():
        if "routes" in p:
            yield f"persona:{key}", p["routes"], p.get("user_id")
        for a in p.get("accounts", []):
            yield f"persona:{key}:{a['host']}", a["routes"], a["observee"]["user_id"]
    for s in m["scenarios"]:
        if s["routes"] and s["id"].startswith("grades/"):
            yield f"scenario:{s['id']}", s["routes"], "4899001"


def collect(routes, endpoint, path=None):
    out = []
    for r in routes:
        if r["endpoint"] == endpoint and (path is None or r["path"] == path) and r["status"] == 200:
            body = load(r["body"])
            out.extend(body if isinstance(body, list) else [body])
    return out


class Parity(unittest.TestCase):
    def test_client_side_recomputation_matches_enrollment_fields(self):
        """Contract: +/-0.01. Self-consistency: the generator's fixtures must agree exactly."""
        checked = 0
        self.max_diff = 0.0
        for label, routes, student_id in route_sets():
            for course in collect(routes, "courses"):
                if "enrollments" not in course:
                    continue
                cid = course["id"]
                groups = collect(routes, "assignment_groups", f"/api/v1/courses/{cid}/assignment_groups")
                gps = collect(routes, "grading_periods", f"/api/v1/courses/{cid}/grading_periods")
                inp = G.course_input_from_api(course, groups, gps[0] if gps else None, student_id=student_id)
                res = G.compute_enrollment_scores(inp)
                for e in course["enrollments"]:
                    if e["type"] != "student":
                        self.assertNotIn("computed_current_score", e)
                        continue
                    if course["hide_final_grades"]:
                        self.assertNotIn("computed_current_score", e, f"{label} {cid}")
                        continue
                    for k_api, k_calc in (("computed_current_score", "current_score"),
                                          ("computed_final_score", "final_score")):
                        a, b = e[k_api], res[k_calc]
                        if a is None or b is None:
                            self.assertEqual(a, b, f"{label} {cid} {k_api}")
                        else:
                            self.assertAlmostEqual(a, b, delta=0.01, msg=f"{label} {cid} {k_api}")
                            self.max_diff = max(self.max_diff, abs(a - b))
                    gp_id = e.get("current_grading_period_id")
                    if gp_id:
                        want = res["grading_periods"][gp_id]
                        self.assertAlmostEqual(e["current_period_computed_current_score"], want["current_score"],
                                               delta=0.01, msg=f"{label} {cid} period")
                    checked += 1
        self.assertGreater(checked, 40)
        self.assertEqual(self.max_diff, 0.0)

    def test_expected_files_match_enrollments(self):
        m = load("manifest.json")
        for key, p in m["personas"].items():
            if "routes" not in p:
                continue
            exp = {c["course_id"]: c for c in load(f"expected/grades/{key}.json")["courses"]}
            for course in collect(p["routes"], "courses"):
                e = course["enrollments"][0]
                x = exp[course["id"]]
                if x["visible_in_api"]:
                    self.assertEqual(e["computed_current_score"], x["current_score"])
                    self.assertEqual(e["computed_current_grade"], x["current_grade"])

    def test_flagship_matches_mockup(self):
        want = {"MATH 122": (90.1, "A-"), "PSY 101": (87.2, "B+"), "BIO 101": (93.4, "A"),
                "HIST 210": (82.0, "B"), "ENG 101": (89.0, "A-")}
        got = {c["course_code"]: (c["current_score"], c["current_grade"])
               for c in load("expected/grades/flagship.json")["courses"]}
        self.assertEqual(got, want)

    def test_digest_has_real_changes(self):
        kinds = {c["kind"] for c in load("expected/digest/flagship.json")["changes"]}
        self.assertTrue({"newly_graded", "new_announcement", "due_date_changed", "new_assignment",
                         "course_score_changed"} <= kinds, kinds)


class Contract(unittest.TestCase):
    def walk_ids(self, v, where):
        if isinstance(v, dict):
            for k, x in v.items():
                if ID_KEY.search(k):
                    self.assertTrue(x is None or isinstance(x, str), f"{where}: {k}={x!r}")
                elif IDS_KEY.search(k) and isinstance(x, list):
                    for i in x:
                        self.assertIsInstance(i, str, f"{where}: {k}")
                self.walk_ids(x, where)
        elif isinstance(v, list):
            for x in v:
                self.walk_ids(x, where)

    def all_routes(self):
        m = load("manifest.json")
        for p in m["personas"].values():
            yield from p.get("routes", [])
            for a in p.get("accounts", []):
                yield from a["routes"]
        for s in m["scenarios"]:
            yield from s["routes"]

    def test_every_route_file_exists_and_ids_are_strings(self):
        n = 0
        for r in self.all_routes():
            self.assertTrue(os.path.exists(os.path.join(ROOT, r["body"])), r["body"])
            self.assertTrue(os.path.exists(os.path.join(ROOT, r["headers"])), r["headers"])
            if r["body"].endswith(".json") and r["endpoint"] != "grading_periods_meta":
                self.walk_ids(load(r["body"]), r["body"])
            n += 1
        self.assertGreater(n, 150)

    def test_link_next_chains_resolve_to_routes(self):
        routes = list(self.all_routes())
        index = {(r["host"], r["path"], r["query"]) for r in routes}
        followed = 0
        for r in routes:
            hdr = load(r["headers"])["headers"]
            link = next((v for k, v in hdr.items() if k.lower() == "link"), None)
            if not link:
                continue
            m = re.search(r'<([^>]+)>; rel="next"', link)
            if not m:
                continue
            scheme, host, path, q = parse_url(m.group(1))
            if scheme != "https" or host != r["host"]:
                continue  # defensive scenarios: the client must refuse these
            self.assertIn((host, path, normalize_query(q)), index, m.group(1))
            followed += 1
        self.assertGreater(followed, 5)

    def test_timestamps_are_canvas_form(self):
        ts = re.compile(r'"\d{4}-\d{2}-\d{2}T[^"]*"')
        ok = re.compile(r'^"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"$')
        for r in self.all_routes():
            if not r["body"].endswith(".json"):
                continue
            with open(os.path.join(ROOT, r["body"]), encoding="utf-8") as f:
                for t in ts.findall(f.read()):
                    self.assertRegex(t, ok, r["body"])


if __name__ == "__main__":
    unittest.main()
