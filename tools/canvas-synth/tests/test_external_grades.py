"""The external-grades persona (plan 08 section 4.5, XG-01): each course sits on the intended side
of the grade-availability classifier's rules, read from the generated fixture files (the client's
view). The thresholds are read from the Swift source (InsightsConfig), so they cannot drift apart.
The Swift classifier itself is tested in TallyDomainTests/GradeAvailabilityTests.swift.
FIXTURES_DIR overrides the default ../../fixtures/canvas."""
import json
import os
import re
import sys
import unittest
from datetime import timedelta

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from canvas_synth import personas as P  # noqa: E402
from canvas_synth.tz import parse_iso  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..", "..")
ROOT = os.environ.get("FIXTURES_DIR") or os.path.join(REPO, "fixtures", "canvas")
INSIGHTS_CONFIG = os.path.join(REPO, "packages", "TallyCore", "Sources", "TallyDomain", "Insights", "InsightsConfig.swift")
SAMPLE_FIXTURES = os.path.join(REPO, "packages", "TallyAppleKit", "Sources", "TallySampleFixtures", "CanvasFixtures")
KEY = "external-grades"
OFFLINE = {"on_paper", "none"}
# validate.sh mounts only tools/canvas-synth and fixtures/canvas; these checks need the whole repo.
WHOLE_REPO = os.path.exists(INSIGHTS_CONFIG) and os.path.isdir(SAMPLE_FIXTURES)
needs_whole_repo = unittest.skipUnless(WHOLE_REPO, "needs the whole repo checkout (Swift thresholds, app bundle)")


def swift_int(name: str) -> int:
    with open(INSIGHTS_CONFIG, encoding="utf-8") as f:
        m = re.search(rf"static let {name}: Int = (\d+)", f.read())
    if m is None:
        raise AssertionError(f"{name} not found in InsightsConfig.swift")
    return int(m.group(1))


if WHOLE_REPO:
    MIN_PAST_DUE = swift_int("externalGradesMinPastDueItems")
    GRACE_DAYS = swift_int("externalGradesGraceDays")
    MIN_SUBMITTED_OR_OFFLINE = swift_int("externalGradesMinSubmittedOrOffline")


def load(rel):
    with open(os.path.join(ROOT, rel), "rb") as f:
        return json.loads(f.read())


def courses():
    return {c["course_code"]: c for c in load(f"personas/{KEY}/courses.json")}


def assignments(course):
    return [a for g in load(f"personas/{KEY}/assignment_groups/{course['id']}.json") for a in g["assignments"]]


def graded_signal(a):
    s = a.get("submission") or {}
    return (s.get("score") is not None or s.get("grade") is not None or s.get("graded_at") is not None
            or s.get("workflow_state") == "graded")


def eligible(a):
    types = a["submission_types"]
    if not a["published"] or "not_graded" in types or "wiki_page" in types:
        return False
    if a["grading_type"] == "not_graded" or a["omit_from_final_grade"]:
        return False
    return (a["points_possible"] or 0) > 0 or a["grading_type"] in ("letter_grade", "pass_fail")


def evidence(course):
    """(eligible items due GRACE_DAYS+ days ago, of those submitted or offline)."""
    cutoff = P.ANCHOR - timedelta(days=GRACE_DAYS)
    past = [a for a in assignments(course) if eligible(a) and a["due_at"] and parse_iso(a["due_at"]) <= cutoff]
    done = [a for a in past if (a.get("submission") or {}).get("submitted_at") or set(a["submission_types"]) <= OFFLINE]
    return len(past), len(done)


class ExternalGradesPersona(unittest.TestCase):
    def test_registered_with_six_courses(self):
        self.assertIs(P.ALL[KEY], P.external_grades)
        p = P.external_grades()
        self.assertEqual(sorted(c.course_code for c in p.courses),
                         ["ADVISORY", "ALG2", "ART-1", "BIO-H", "ENG-10", "SPAN-2"])
        self.assertEqual(p.captured_at, P.ANCHOR)
        self.assertTrue(p.host.endswith(".example"))
        self.assertEqual(set(courses()), {"ADVISORY", "ALG2", "ART-1", "BIO-H", "ENG-10", "SPAN-2"})

    @needs_whole_repo
    def test_kept_outside_courses_meet_the_threshold_with_no_grade(self):
        cs = courses()
        for code in ("ENG-10", "ALG2", "BIO-H"):
            c = cs[code]
            with self.subTest(code):
                for e in c["enrollments"]:
                    self.assertIsNone(e.get("computed_current_score"))
                    self.assertIsNone(e.get("computed_current_grade"))
                    self.assertIsNone(e.get("current_period_computed_current_score"))
                self.assertFalse(any(graded_signal(a) for a in assignments(c)))
                past, done = evidence(c)
                self.assertGreaterEqual(past, MIN_PAST_DUE)
                self.assertGreaterEqual(done, MIN_SUBMITTED_OR_OFFLINE)

    @needs_whole_repo
    def test_each_kept_outside_course_takes_a_different_path(self):
        cs = courses()
        eng, alg, bio = cs["ENG-10"], cs["ALG2"], cs["BIO-H"]
        self.assertEqual(evidence(eng), (8, 8))
        self.assertTrue(all("on_paper" not in a["submission_types"] for a in assignments(eng)), "ENG-10: online only")
        # Canvas counts ungraded work as zero in the final score: 0.0 and, with a scheme, "F".
        self.assertEqual(eng["enrollments"][0]["computed_final_score"], 0.0)
        self.assertEqual(eng["enrollments"][0]["computed_final_grade"], "F")
        self.assertEqual(evidence(alg), (9, 9))
        self.assertFalse(any((a.get("submission") or {}).get("submitted_at") for a in assignments(alg)),
                         "ALG2: nothing submitted online; paper work only")
        self.assertTrue(bio["hide_final_grades"])
        self.assertTrue(all("computed_current_score" not in e for e in bio["enrollments"]))
        self.assertEqual(evidence(bio), (8, 8))
        self.assertTrue(any(a["due_at"] is None for a in assignments(bio)), "BIO-H: one item with no due date")

    @needs_whole_repo
    def test_art_has_two_items_past_due_and_no_grade(self):
        art = courses()["ART-1"]
        items = assignments(art)
        self.assertEqual(sum(1 for a in items if parse_iso(a["due_at"]) < P.ANCHOR), 2)
        self.assertLess(evidence(art)[0], MIN_PAST_DUE)
        self.assertFalse(any(graded_signal(a) for a in items))

    def test_advisory_has_only_not_graded_items(self):
        items = assignments(courses()["ADVISORY"])
        self.assertGreater(len(items), 0)
        for a in items:
            self.assertEqual(a["grading_type"], "not_graded")
            self.assertEqual(a["submission_types"], ["not_graded"])
            self.assertFalse(eligible(a))

    def test_spanish_is_graded_in_canvas(self):
        span = courses()["SPAN-2"]
        self.assertIsNotNone(span["enrollments"][0]["computed_current_score"])
        self.assertTrue(any(graded_signal(a) for a in assignments(span)))

    @needs_whole_repo
    def test_not_bundled_into_sample_mode(self):
        """Sample mode ships the flagship persona only (plan 08 section 4.5)."""
        self.assertEqual(sorted(os.listdir(os.path.join(SAMPLE_FIXTURES, "personas"))), ["flagship"])
        with open(os.path.join(SAMPLE_FIXTURES, "manifest.json"), encoding="utf-8") as f:
            self.assertNotIn(KEY, f.read())


if __name__ == "__main__":
    unittest.main()
