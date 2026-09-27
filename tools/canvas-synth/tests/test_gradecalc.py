"""Reference grade calculator tests.

HAND-*   : computed by hand in the comments.
JS-*     : mirrored from canvas-lms ui/shared/grading/__tests__/
           AssignmentGroupGradeCalculator{1,2}.test.js and CourseGradeCalculator{2,4}.test.js
RB-*     : mirrored from canvas-lms spec/lib/grade_calculator_spec.rb
(canvas-lms @ 1c9f0bb8013ed69c4f2efe11fd483025469b7e6c)
"""
import os
import sys
import unittest
from datetime import datetime, timezone

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from canvas_synth import gradecalc as G  # noqa: E402

UTC = timezone.utc


def course(groups, weighting="points", periods=None):
    """groups: [(gid, weight, rules, [(aid, points, score|None, flags...)])]."""
    assignments, subs = [], []
    for gid, weight, rules, items in groups:
        for it in items:
            aid, pts, score = it[0], it[1], it[2]
            f = it[3] if len(it) > 3 else {}
            assignments.append({"id": aid, "assignment_group_id": gid, "points_possible": pts,
                                "omit_from_final_grade": f.get("omit", False), "gradeable": True,
                                "grading_period_id": f.get("gp")})
            subs.append({"id": 9000 + aid, "assignment_id": aid, "score": score, "excused": f.get("excused", False),
                         "posted": not f.get("hidden", False),
                         "workflow_state": "pending_review" if f.get("pending") else "graded"})
    return {"apply_assignment_group_weights": weighting == "percent",
            "groups": [{"id": g[0], "group_weight": g[1], "rules": g[2]} for g in groups],
            "assignments": assignments, "submissions": subs, "grading_periods": periods}


def group(c, kind="current", idx=0):
    return G.compute_scores(c)["groups"][kind][idx]


class RubyRounding(unittest.TestCase):
    def test_hand_ruby_float_round_differs_from_python(self):
        # Ruby Float#round rounds the decimal literal half-up; Python rounds the binary value.
        self.assertEqual(G.ruby_float_round(93.825, 2), 93.83)   # RB: "without floating point calculation errors"
        self.assertEqual(G.ruby_float_round(1.005, 2), 1.01)
        self.assertEqual(round(1.005, 2), 1.0)
        self.assertEqual(G.ruby_float_round(2.675, 2), 2.68)
        self.assertEqual(round(2.675, 2), 2.67)
        self.assertEqual(G.ruby_float_round(60.835, 2), 60.84)
        self.assertEqual(G.ruby_float_round(90.1, 2), 90.1)
        self.assertEqual(G.ruby_float_round(0.0, 2), 0.0)


class Schemes(unittest.TestCase):
    def test_hand_default_scheme_boundaries(self):
        self.assertEqual(G.score_to_grade(94.0), "A")
        self.assertEqual(G.score_to_grade(93.99), "A-")
        self.assertEqual(G.score_to_grade(90.0), "A-")
        self.assertEqual(G.score_to_grade(89.99), "B+")
        self.assertEqual(G.score_to_grade(82.0), "B-")
        self.assertEqual(G.score_to_grade(-5), "F")

    def test_hand_custom_schemes(self):
        from canvas_synth.personas import BIO_SCALE, STRAIGHT_SCALE, COMP_SCALE, PASS_FAIL_SCALE
        self.assertEqual(G.score_to_grade(93.4, BIO_SCALE), "A")
        self.assertEqual(G.score_to_grade(82.0, STRAIGHT_SCALE), "B")
        self.assertEqual(G.score_to_grade(89.0, COMP_SCALE), "A-")
        self.assertEqual(G.score_to_grade(59.99, PASS_FAIL_SCALE), "Fail")

    def test_hand_grade_to_score(self):
        self.assertEqual(G.grade_to_score("A"), 100.0)
        self.assertEqual(G.grade_to_score("A-"), 93.0)   # one point under A's 94 cutoff
        self.assertEqual(G.grade_to_score("B+"), 89.0)
        self.assertIsNone(G.grade_to_score("Z"))


class GradingPeriodMembership(unittest.TestCase):
    P = [{"id": 1, "start_date": datetime(2026, 8, 24, 5, tzinfo=UTC), "end_date": datetime(2026, 10, 1, 4, 59, 59, tzinfo=UTC)},
         {"id": 2, "start_date": datetime(2026, 10, 1, 5, tzinfo=UTC), "end_date": datetime(2026, 12, 20, 5, tzinfo=UTC)}]

    def test_hand_boundaries(self):
        f = G.grading_period_for_due_at
        self.assertEqual(f(datetime(2026, 10, 1, 4, 59, 59, tzinfo=UTC), self.P), 1)  # == end -> inside
        self.assertEqual(f(datetime(2026, 8, 24, 5, 0, 30, tzinfo=UTC), self.P), None)  # == start (minute) -> outside
        self.assertEqual(f(None, self.P), 2)  # no due date -> last period
        self.assertEqual(f(datetime(2027, 1, 5, tzinfo=UTC), self.P), None)


class Hand(unittest.TestCase):
    def test_hand_points_two_groups(self):
        # (18 + 9) / (20 + 10) = 90.0
        c = course([(1, 0, {}, [(1, 20, 18)]), (2, 0, {}, [(2, 10, 9)])])
        self.assertEqual(G.compute_scores(c)["current"]["grade"], 90.0)

    def test_hand_weighted_scaling_with_ungraded_group(self):
        # HW 54.5/60 x 40 + Q 85/100 x 35 = 36.3333 + 29.75 = 66.0833 over 75 -> 88.11
        c = course([(1, 40, {}, [(1, 20, 18), (2, 10, 9), (3, 30, 27.5)]), (2, 35, {}, [(4, 50, 41), (5, 50, 44)]),
                    (3, 25, {}, [(6, 100, None)])], "percent")
        r = G.compute_scores(c)
        self.assertEqual(r["current"]["grade"], 88.11)
        # final: 66.0833 + 0 x 25 = 66.08
        self.assertEqual(r["final"]["grade"], 66.08)

    def test_hand_unposted_ignored_for_current_zero_for_final(self):
        c = course([(1, 0, {}, [(1, 100, 80), (2, 100, 40, {"hidden": True})])])
        r = G.compute_scores(c)
        self.assertEqual(r["current"]["grade"], 80.0)   # 80/100
        self.assertEqual(r["final"]["grade"], 40.0)     # 80/200
        u = G.compute_scores(c, ignore_unposted=False)
        self.assertEqual(u["current"]["grade"], 60.0)   # 120/200

    def test_hand_excused_unposted_counts_as_missing_in_final(self):
        # An unposted excused submission is invisible to the posted calculation (s = nil), so it is
        # not "excused" there: final counts it as 0/10.
        c = course([(1, 0, {}, [(1, 10, 10), (2, 10, None, {"excused": True, "hidden": True})])])
        r = G.compute_scores(c)
        self.assertEqual(r["current"]["grade"], 100.0)
        self.assertEqual(r["final"]["grade"], 50.0)

    def test_hand_weighted_grading_periods_scaled_current(self):
        rows = [{"id": 1, "current": 71.25, "final": 71.25}, {"id": 2, "current": None, "final": 0.0}]
        r = G.combine_weighted_grading_periods(rows, {"1": 50.0, "2": 50.0})
        self.assertEqual(r["current"], 71.25)  # only period 1 has a current score -> scaled to 100
        self.assertEqual(r["final"], 35.63)    # 35.625 -> Ruby Float#round -> 35.63 (Python round gives 35.62)


class JsAssignmentGroup(unittest.TestCase):
    ITEMS = [(201, 100, 100), (202, 91, 42), (203, 55, 14), (204, 38, 3), (205, 1000, None)]

    def base(self, rules=None, mutate=None):
        items = [list(i) + [{}] for i in self.ITEMS]
        if mutate:
            mutate(items)
        return course([(301, 0, rules or {}, [tuple(i) for i in items])])

    def test_js_adds_scores_and_possible(self):
        c = self.base()
        self.assertEqual((float(group(c)["score"]), float(group(c)["possible"])), (159, 284))
        self.assertEqual((float(group(c, "final")["score"]), float(group(c, "final")["possible"])), (159, 1284))

    def test_js_hidden_and_excused_and_pending(self):
        for flag in ("hidden", "excused"):
            c = self.base(mutate=lambda it: it[1][3].update({flag: True}))
            self.assertEqual((float(group(c)["score"]), float(group(c)["possible"])), (117, 193))
        c = self.base(mutate=lambda it: it[1][3].update({"excused": True}))
        self.assertEqual(float(group(c, "final")["possible"]), 1193)
        # Divergence: the JS calculator drops a hidden (unposted) submission from the final possible (1193);
        # Ruby's posted branch treats it as absent (s = nil) and counts it as 0 of 91 -> 1284.
        c = self.base(mutate=lambda it: it[1][3].update({"hidden": True}))
        self.assertEqual((float(group(c, "final")["score"]), float(group(c, "final")["possible"])), (117, 1284))
        c = self.base(mutate=lambda it: it[1][3].update({"pending": True}))
        self.assertEqual((float(group(c)["score"]), float(group(c)["possible"])), (117, 193))
        self.assertEqual((float(group(c, "final")["score"]), float(group(c, "final")["possible"])), (159, 1284))

    def test_js_omit_from_final_grade(self):
        c = self.base(mutate=lambda it: it[2][3].update({"omit": True}))
        self.assertEqual((float(group(c)["score"]), float(group(c)["possible"])), (145, 229))
        self.assertEqual(float(group(c, "final")["possible"]), 1229)
        c = self.base(mutate=lambda it: it[4][3].update({"omit": True}))
        self.assertEqual(float(group(c, "final")["possible"]), 284)

    def test_js_unpointed_scores_count(self):
        c = course([(301, 0, {}, [(201, 0, 10), (202, 10, 10)])])
        self.assertEqual(float(group(c)["score"]), 20)

    def test_js_drop_lowest_1(self):
        items = [(201, 40, 31), (202, 24, 17), (203, 10, 6)]
        c = course([(1, 0, {"drop_lowest": 1}, items)])
        self.assertEqual((float(group(c)["score"]), float(group(c)["possible"])), (48, 64))
        self.assertEqual(group(c)["dropped"], [9203])
        c = course([(1, 0, {"drop_lowest": 1}, [(201, 40, 31), (202, 24, 17), (203, 10, 7)])])
        self.assertEqual((float(group(c)["score"]), float(group(c)["possible"])), (38, 50))  # drops 17/24
        c = course([(1, 0, {"drop_lowest": 1}, [(201, 0, 31), (202, 24, 17), (203, 10, 6)])])
        self.assertEqual(float(group(c)["score"]), 37)  # drops pointed 202 over unpointed 201
        c = course([(1, 0, {"drop_lowest": 1}, [(201, 40, 31), (202, 24, 17), (203, 10, None)])])
        self.assertEqual((float(group(c)["score"]), float(group(c, "final")["score"])), (31, 48))

    def test_js_drop_lowest_2_and_4(self):
        c = self.base({"drop_lowest": 2})
        self.assertEqual((float(group(c)["score"]), float(group(c)["possible"])), (103, 138))
        self.assertEqual((float(group(c, "final")["score"]), float(group(c, "final")["possible"])), (156, 246))
        c = self.base({"drop_lowest": 4})
        self.assertEqual((float(group(c)["score"]), float(group(c)["possible"])), (100, 100))
        self.assertEqual((float(group(c, "final")["score"]), float(group(c, "final")["possible"])), (100, 100))

    def test_js_ridiculous_circumstances(self):
        items = [(201, 20, None), (202, 10, 3), (203, 10, None), (204, 1e50, None), (205, None, None)]
        c = course([(1, 0, {"drop_lowest": 2}, items)])
        self.assertEqual((float(group(c)["score"]), float(group(c)["possible"])), (3, 10))
        self.assertEqual((float(group(c, "final")["score"]), float(group(c, "final")["possible"])), (3, 20))

    def test_js_drop_highest(self):
        items = [(201, 40, 31), (202, 24, 17), (203, 10, 6)]
        c = course([(1, 0, {"drop_highest": 1}, items)])
        self.assertEqual((float(group(c)["score"]), float(group(c)["possible"])), (23, 34))
        c = course([(1, 0, {"drop_highest": 1}, [(201, 40, 31), (202, 24, 17), (203, 10, 10)])])
        self.assertEqual((float(group(c)["score"]), float(group(c)["possible"])), (48, 64))
        c = course([(1, 0, {"drop_highest": 1}, [(201, 40, None), (202, 24, 17), (203, 10, 6)])])
        self.assertEqual((float(group(c)["score"]), float(group(c)["possible"])), (6, 10))
        self.assertEqual(float(group(c, "final")["possible"]), 50)

    def test_js_tie_drops_highest_id(self):
        c = course([(1, 0, {"drop_lowest": 1}, [(2301, 10, 10), (2302, 10, 10), (2303, 10, 10)])])
        self.assertEqual(float(group(c)["score"]), 20)
        self.assertEqual(group(c)["dropped"], [9000 + 2303])

    def test_js_all_unpointed_drop_lowest(self):
        c = course([(1, 0, {"drop_lowest": 1}, [(2301, 0, 15), (2302, 0, 5), (2303, 0, 10)])])
        self.assertEqual(float(group(c)["score"]), 25)
        self.assertEqual(group(c)["dropped"], [9000 + 2302])

    def test_never_drop(self):
        # HAND: drop_lowest 1 over 4,9,8,10 (each /10) with never_drop on the 4 -> drops the 8.
        c = course([(1, 0, {"drop_lowest": 1, "never_drop": ["1"]}, [(1, 10, 4), (2, 10, 9), (3, 10, 8), (4, 10, 10)])])
        self.assertEqual(float(group(c)["score"]), 23)
        self.assertEqual(group(c)["dropped"], [9003])


class JsCourse(unittest.TestCase):
    def two_groups(self, w1, w2, scheme="percent"):
        return course([(301, w1, {}, [(201, 100, 100), (202, 91, 42)]),
                       (302, w2, {}, [(203, 55, 14), (204, 38, 3), (205, 1000, None)])], scheme)

    def test_js_points(self):
        r = G.compute_scores(self.two_groups(50, 50, "points"))
        self.assertEqual(r["current"]["grade"], G.ruby_float_round(159 / 284 * 100, 2))
        self.assertEqual(r["current"]["total"], 159.0)

    def test_js_weighted_variants(self):
        cases = [((50, 50), 46.31, 37.95), ((5, 5), 46.31, 37.95), ((100, 100), 92.63, 75.9),
                 ((75, 25), 60.33, 56.15), ((33.33, 50), 40.7, 30.67)]
        for (w1, w2), cur, fin in cases:
            r = G.compute_scores(self.two_groups(w1, w2))
            self.assertEqual((r["current"]["grade"], r["final"]["grade"]), (cur, fin), (w1, w2))

    def gp_course(self, weights=(50, 50), scheme="percent", groups=None, empty_302=False):
        items = {301: [(201, 10, 10, {"gp": 701}), (202, 10, 5, {"gp": 701})],
                 302: [] if empty_302 else [(203, 20, 12, {"gp": 702})],
                 303: [(204, 40, 16, {"gp": 702})]}
        gdefs = [(301, 60, {}, items[301]), (302, 20, {}, items[302]), (303, 20, {}, items[303])]
        if groups:
            gdefs = [g for g in gdefs if g[0] in groups]
        periods = {"weighted": True, "periods": [
            {"id": 701, "weight": weights[0], "start_date": None, "end_date": datetime(2026, 1, 1, tzinfo=UTC)},
            {"id": 702, "weight": weights[1], "start_date": None, "end_date": datetime(2026, 6, 1, tzinfo=UTC)}]}
        return course(gdefs, scheme, periods)

    def score(self, c):
        r = G.compute_enrollment_scores(c)
        return r["current_score"], r["final_score"]

    def test_js_weighted_grading_periods(self):
        self.assertEqual(self.score(self.gp_course()), (62.5, 62.5))
        self.assertEqual(self.score(self.gp_course((5, 5))), (62.5, 62.5))
        self.assertEqual(self.score(self.gp_course((100, 100))), (125.0, 125.0))
        self.assertEqual(self.score(self.gp_course((None, 5))), (50.0, 50.0))
        self.assertEqual(self.score(self.gp_course((0, 0))), (0.0, 0.0))
        self.assertEqual(self.score(self.gp_course((25, 75))), (56.25, 56.25))
        c = self.gp_course(groups=[301])
        self.assertEqual(self.score(c), (75.0, 37.5))
        self.assertEqual(self.score(self.gp_course(empty_302=True)), (57.5, 57.5))

    def test_js_vs_ruby_divergence_points_weighting(self):
        # JS spec expects 60.83 (it combines unrounded period grades); Ruby combines the stored,
        # rounded period scores 75.0 and 46.67 -> 60.835 -> Float#round -> 60.84.
        self.assertEqual(self.score(self.gp_course(scheme="points")), (60.84, 60.84))


class RubySpec(unittest.TestCase):
    def test_rb_irrational_weights(self):
        g = [(i, w, {}, [(i, pts, sc)]) for i, (w, pts, sc) in enumerate(
            [(12, 12, 11.8), (10, 82, 82), (15, 100, 89.5), (21, 100, 85), (21, 100, 85), (21, 100, 83)], 1)]
        self.assertEqual(G.compute_scores(course(g, "percent"))["current"]["grade"], 88.36)

    def test_rb_weights_under_100_precision(self):
        c = course([(1, 9.9, {}, [(1, 100, 75)]), (2, 23.1, {}, [(2, 100, 53.75)])], "percent")
        self.assertEqual(G.compute_scores(c)["current"]["grade"], 60.13)

    def test_rb_float_error_percent(self):
        c = course([(1, 50, {}, [(1, 200, 267.9)]), (2, 50, {}, [(2, 100, 53.7)])], "percent")
        self.assertEqual(G.compute_scores(c)["current"]["grade"], 93.83)

    def test_rb_float_error_points(self):
        c = course([(1, 0, {}, [(1, 100, 88.56), (2, 100, 69.71)])])
        self.assertEqual(G.compute_scores(c)["current"]["grade"], 79.14)

    def two(self, a1, a2, w=(50, 50), scheme="percent"):
        return course([(1, w[0], {}, [(1, 10, a1)]), (2, w[1], {}, [(2, 40, a2)])], scheme)

    def pair(self, c):
        r = G.compute_scores(c)
        return r["current"]["grade"], r["final"]["grade"]

    def test_rb_computes_weighted_grade(self):
        self.assertEqual(self.pair(self.two(None, None, scheme="points")), (None, 0.0))
        self.assertEqual(self.pair(self.two(9, None, scheme="points")), (90.0, 18.0))
        self.assertEqual(self.pair(self.two(9, None)), (90.0, 45.0))
        self.assertEqual(self.pair(self.two(9, 20)), (70.0, 70.0))
        self.assertEqual(self.pair(self.two(9, 20, scheme="points")), (58.0, 58.0))

    def test_rb_extra_credit(self):
        self.assertEqual(self.pair(self.two(10, None, (50, 60), "points")), (100.0, 20.0))
        self.assertEqual(self.pair(self.two(10, None, (50, 60))), (100.0, 50.0))
        self.assertEqual(self.pair(self.two(10, 40, (50, 60))), (110.0, 110.0))
        self.assertEqual(self.pair(self.two(11, 45, (50, 60))), (122.5, 122.5))
        self.assertEqual(self.pair(self.two(11, 45, (50, 60), "points")), (112.0, 112.0))

    def test_rb_total_weight_under_100(self):
        self.assertEqual(self.pair(self.two(10, None, (50, 40))), (100.0, 55.56))
        self.assertEqual(self.pair(self.two(10, 40, (50, 40))), (100.0, 100.0))

    def test_rb_not_graded_assignment_ignored(self):
        c = course([(1, 0, {}, [(1, 10, 9), (2, None, 1)])])
        c["assignments"][1]["gradeable"] = False
        self.assertEqual(self.pair(c), (90.0, 90.0))


if __name__ == "__main__":
    unittest.main()
