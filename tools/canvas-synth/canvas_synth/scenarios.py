"""Edge-case scenarios from architecture section 3.3, error bodies and the
onboarding institution search. Each scenario is a self-contained route set."""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

from . import serialize as S
from .builder import Builder, finalize
from .emit import (JSON_CT, Out, Quota, add_route, canvas_body, link_header, page_url, paginate_bookmark,
                   paginate_ordinal)
from .fixtures import COURSE_INCLUDES, PER_PAGE, expected_course
from .jsonfmt import canvas_json, recursively_stringify_ids, stringify_ids
from .model import Enrollment, Persona
from .personas import ANCHOR, SEED, PASS_FAIL_SCALE, _ids
from .prng import Rng
from .tz import iso_offset, iso_z

HOST = "canvas.northfield.example"
BASE = f"https://{HOST}"


def _student_world(key: str, **idover) -> tuple[Builder, Persona]:
    ids = _ids(user=4899001, teacher=301900, course=58000, group=199000, assignment=1290000, quiz=95000,
               submission=990000000, enrollment=7390000, section=69000, event=3390000, topic=2590000,
               attachment=51900000, folder=779000)
    ids.update(idover)
    b = _plain(Builder(f"scenario:{key}", SEED, HOST, "America/Chicago", root_account_id=10, account_id=145,
                       id_base=ids))
    user = b.user("Sam Sample", "Sample, Sam", "ssample", "sam.sample@students.northfield.example",
                  b.at(2025, 8, 12, 9, 0), uid=4899001)
    p = Persona(key=key, title=key, description="", host=HOST, school="Northfield State University", user=user,
                courses=[], captured_at=ANCHOR, anchor=ANCHOR, role_id_student=19)
    return b, p


def _term(b: Builder):
    return b.term("Fall 2026", b.at(2026, 8, 24), b.at(2026, 12, 19), b.at(2026, 2, 17, 10, 3, 41))


def _simple_course(b, p, name, code, **kw):
    t = b.teacher("Avery Scenario")
    c = b.course(name, code, _term(b), [t], b.at(2026, 4, 2, 11, 0), grading_standard_id=kw.pop("gsid", 0), **kw)
    p.courses.append(c)
    return c


def _due(b, m, d, h=23, mi=59, s=59):
    return b.at(2026, m, d, h, mi, s)


TXT = ("online_text_entry",)


def _plain(b):
    """Scenario assignments carry no description (Canvas returns null)."""
    orig = b.assignment

    def f(*a, **k):
        k.setdefault("description", "")
        return orig(*a, **k)
    b.assignment = f
    return b


def grade_scenarios():
    """Returns [(name, description, covers, persona, extra)]."""
    out = []

    # weighted groups (weights sum to 100; an ungraded group scales the rest up)
    b, p = _student_world("weighted-groups")
    c = _simple_course(b, p, "Scenario: Weighted Groups", "SCN 101", apply_weights=True)
    hw, qz, fin = b.group(c, "Homework", 40), b.group(c, "Quizzes", 35), b.group(c, "Final", 25)
    for i, (sc, pts) in enumerate([(18, 20), (9, 10), (27.5, 30)], 1):
        a = b.assignment(c, hw, f"Homework {i}", pts, _due(b, 9, 3 + 7 * i), types=TXT)
        b.grade(c, a, sc, submitted=_due(b, 9, 3 + 7 * i, 20), graded=_due(b, 9, 5 + 7 * i, 9))
    b.assignment(c, hw, "Homework 4", 20, _due(b, 10, 8), types=TXT)
    for i, sc in enumerate([41, 44], 1):
        a = b.assignment(c, qz, f"Quiz {i}", 50, _due(b, 9, 8 + 7 * i, 10, 0, 0), quiz=True)
        b.grade(c, a, sc, submitted=_due(b, 9, 8 + 7 * i, 9, 40, 0), graded=_due(b, 9, 8 + 7 * i, 9, 40, 30))
    b.assignment(c, fin, "Final Exam", 100, _due(b, 12, 15, 10, 0, 0), types=("on_paper",))
    out.append(("weighted-groups", "apply_assignment_group_weights=true; the ungraded Final group (25%) is left out "
                "of the current score and the remaining 75% is scaled to 100%.", ["weighted groups", "weight scaling"], p))

    # unweighted groups (points)
    b, p = _student_world("unweighted-groups")
    c = _simple_course(b, p, "Scenario: Points", "SCN 102")
    g1, g2 = b.group(c, "Assignments"), b.group(c, "Exams")
    for i, (sc, pts) in enumerate([(100, 100), (42, 91), (14, 55), (3, 38)], 1):
        a = b.assignment(c, g1 if i < 3 else g2, f"Item {i}", pts, _due(b, 9, 2 + 3 * i), types=TXT)
        b.grade(c, a, sc, submitted=_due(b, 9, 2 + 3 * i, 18), graded=_due(b, 9, 4 + 3 * i, 9))
    b.assignment(c, g2, "Item 5", 1000, _due(b, 9, 20), types=TXT)
    out.append(("unweighted-groups", "Points-based course; mirrors canvas-lms "
                "ui/shared/grading/__tests__/CourseGradeCalculator2.test.js (159/284 current, 159/1284 final).",
                ["unweighted groups", "ungraded counts as zero in final"], p))

    # drop lowest (Kane & Kane bisection, mixed points)
    b, p = _student_world("drop-lowest")
    c = _simple_course(b, p, "Scenario: Drop Lowest", "SCN 103")
    g = b.group(c, "Labs", 0, drop_lowest=2)
    for i, (sc, pts) in enumerate([(100, 100), (42, 91), (14, 55), (3, 38), (None, 1000)], 1):
        a = b.assignment(c, g, f"Lab {i}", pts, _due(b, 9, 1 + 3 * i), types=TXT)
        if sc is not None:
            b.grade(c, a, sc, submitted=_due(b, 9, 1 + 3 * i, 18), graded=_due(b, 9, 3 + 3 * i, 9))
    out.append(("drop-lowest", "drop_lowest=2 on mixed points; current keeps 100/100 + 3/38 (103/138), final drops "
                "3/38 and the ungraded 0/1000 (156/246). Mirrors AssignmentGroupGradeCalculator2.test.js.",
                ["drop lowest"], p))

    b, p = _student_world("drop-highest")
    c = _simple_course(b, p, "Scenario: Drop Highest", "SCN 104")
    g = b.group(c, "Quizzes", 0, drop_highest=1)
    for i, (sc, pts) in enumerate([(31, 40), (17, 24), (6, 10)], 1):
        a = b.assignment(c, g, f"Quiz {i}", pts, _due(b, 9, 2 + 5 * i), types=TXT)
        b.grade(c, a, sc, submitted=_due(b, 9, 2 + 5 * i, 18), graded=_due(b, 9, 4 + 5 * i, 9))
    out.append(("drop-highest", "drop_highest=1 drops 31/40 (the best percentage), leaving 23/34.",
                ["drop highest"], p))

    b, p = _student_world("never-drop")
    c = _simple_course(b, p, "Scenario: Never Drop", "SCN 105")
    g = b.group(c, "Homework", 0, drop_lowest=1)
    items = []
    for i, sc in enumerate([4, 9, 8, 10], 1):
        a = b.assignment(c, g, f"Homework {i}", 10, _due(b, 9, 2 + 5 * i), types=TXT)
        items.append(a)
        b.grade(c, a, sc, submitted=_due(b, 9, 2 + 5 * i, 18), graded=_due(b, 9, 4 + 5 * i, 9))
    g.rules["never_drop"] = [items[0].id]
    out.append(("never-drop", "drop_lowest=1 with never_drop on the lowest item (4/10): Homework 3 (8/10) is "
                "dropped instead; rules.never_drop is an array of string ids.", ["never_drop"], p))

    b, p = _student_world("excused")
    c = _simple_course(b, p, "Scenario: Excused", "SCN 106", apply_weights=True)
    g1, g2 = b.group(c, "Labs", 60), b.group(c, "Field Trip", 40)
    for i, (sc, ex) in enumerate([(18, False), (None, True), (16, False)], 1):
        a = b.assignment(c, g1, f"Lab {i}", 20, _due(b, 9, 2 + 5 * i), types=TXT)
        if ex:
            b.grade(c, a, None, graded=_due(b, 9, 4 + 5 * i, 9), excused=True)
        else:
            b.grade(c, a, sc, submitted=_due(b, 9, 2 + 5 * i, 18), graded=_due(b, 9, 4 + 5 * i, 9))
    a = b.assignment(c, g2, "Field Trip Report", 50, _due(b, 9, 20), types=TXT)
    b.grade(c, a, None, graded=_due(b, 9, 22, 9), excused=True)
    out.append(("excused", "Excused submissions are removed from score and possible; a group whose only "
                "item is excused has possible 0 and its 40% weight is dropped from the scaling.",
                ["excused"], p))

    b, p = _student_world("pass-fail")
    c = _simple_course(b, p, "Scenario: Pass/Fail", "SCN 107", gsid=5510, scheme=PASS_FAIL_SCALE)
    g = b.group(c, "Logs")
    for i, lt in enumerate(["complete", "complete", "incomplete", None], 1):
        a = b.assignment(c, g, f"Log {i}", 10, _due(b, 9, 2 + 5 * i), grading_type="pass_fail", types=TXT)
        if lt:
            b.grade(c, a, letter=lt, submitted=_due(b, 9, 2 + 5 * i, 18), graded=_due(b, 9, 4 + 5 * i, 9))
    out.append(("pass-fail", "grading_type=pass_fail: grade 'complete'/'incomplete', score = points_possible or 0; "
                "course uses a Pass/Fail scheme (computed_current_grade 'Pass').", ["pass_fail"], p))

    b, p = _student_world("letter-grades")
    c = _simple_course(b, p, "Scenario: Letter Grades", "SCN 108")
    g = b.group(c, "Projects")
    for i, lt in enumerate(["A", "B+", "C-", None], 1):
        a = b.assignment(c, g, f"Project {i}", 50, _due(b, 9, 2 + 5 * i), grading_type="letter_grade", types=TXT)
        if lt:
            b.grade(c, a, letter=lt, submitted=_due(b, 9, 2 + 5 * i, 18), graded=_due(b, 9, 4 + 5 * i, 9))
    out.append(("letter-grades", "grading_type=letter_grade: grade is the letter; score is "
                "GradingStandard#grade_to_score x points_possible (A=100%; otherwise one point below the next-higher "
                "cutoff: B+=89%, C-=73% on the default scheme).", ["letter grades"], p))

    b, p = _student_world("no-due-date")
    c = _simple_course(b, p, "Scenario: No Due Date", "SCN 109")
    g = b.group(c, "Portfolio")
    a1 = b.assignment(c, g, "Portfolio Piece 1", 25, None, types=TXT)
    b.grade(c, a1, 22, submitted=_due(b, 9, 10, 15), graded=_due(b, 9, 12, 9))
    b.assignment(c, g, "Portfolio Piece 2", 25, None, types=TXT)
    b.assignment(c, g, "Reflection", 10, _due(b, 10, 2), types=TXT)
    out.append(("no-due-date", "due_at null: no cached_due_date, never late or missing, absent from planner items; "
                "with grading periods such items belong to the last period.", ["no due date"], p))

    b, p = _student_world("unposted-and-omitted")
    c = _simple_course(b, p, "Scenario: Unposted & Omitted", "SCN 110")
    g = b.group(c, "Work")
    a = b.assignment(c, g, "Posted Essay", 100, _due(b, 9, 11), types=TXT)
    b.grade(c, a, 80, submitted=_due(b, 9, 11, 18), graded=_due(b, 9, 14, 9))
    a = b.assignment(c, g, "Unposted Essay (manual post policy)", 100, _due(b, 9, 18), types=TXT, post_manually=True)
    b.grade(c, a, 40, submitted=_due(b, 9, 18, 18), graded=_due(b, 9, 21, 9), posted=None)
    a = b.assignment(c, g, "Practice Set (omit from final grade)", 20, _due(b, 9, 15), types=TXT,
                     omit_from_final_grade=True)
    b.grade(c, a, 5, submitted=_due(b, 9, 15, 18), graded=_due(b, 9, 16, 9))
    b.assignment(c, g, "Reading (not graded)", None, _due(b, 9, 20), types=("not_graded",))
    b.assignment(c, g, "Survey (hidden from gradebook)", 0, _due(b, 9, 20), types=("not_graded",),
                 hide_in_gradebook=True, omit_from_final_grade=True)
    q = b.assignment(c, g, "Essay Quiz (pending review)", 10, _due(b, 9, 24, 10, 0, 0), quiz=True)
    b.grade(c, q, 6, submitted=_due(b, 9, 24, 9, 50, 0), graded=_due(b, 9, 24, 9, 50, 30), pending_review=True)
    out.append(("unposted-and-omitted", "Unposted grade (score/grade keys omitted, posted_at null) is ignored; "
                "omit_from_final_grade, not_graded and hide_in_gradebook items never count; a pending_review quiz "
                "is ignored for current and counts 0 for final.",
                ["unposted", "omit_from_final_grade", "hide_in_gradebook", "not_graded", "pending_review"], p))

    for weighted in (True, False):
        b, p = _student_world(f"{'weighted' if weighted else 'unweighted'}-grading-periods")
        gpg = b.gp_group(weighted, True, [
            ("Period 1", b.at(2026, 8, 24), b.at(2026, 9, 30, 23, 59, 59), b.at(2026, 10, 7, 23, 59, 59), 50.0),
            ("Period 2", b.at(2026, 10, 1), b.at(2026, 12, 19, 23, 59, 59), b.at(2026, 12, 23, 23, 59, 59), 50.0)])
        c = _simple_course(b, p, "Scenario: Grading Periods", "SCN 111" if weighted else "SCN 112",
                           apply_weights=True, gp_group=gpg)
        g1, g2, g3 = b.group(c, "Homework", 60), b.group(c, "Quizzes", 20), b.group(c, "Tests", 20)
        spec = [(g1, 10, 10, (9, 10)), (g1, 10, 5, (9, 17)), (g2, 20, 12, (9, 24)), (g3, 40, 16, (10, 20))]
        for i, (g, pts, sc, (m, d)) in enumerate(spec, 1):
            a = b.assignment(c, g, f"Item {i}", pts, _due(b, m, d), types=TXT)
            if (m, d) < (9, 28):
                b.grade(c, a, sc, submitted=_due(b, m, d, 18), graded=_due(b, m, d + 1, 9))
        b.assignment(c, g1, "Extra Practice (no due date)", 10, None, types=TXT)
        out.append((f"{'weighted' if weighted else 'unweighted'}-grading-periods",
                    ("Weighted grading periods (50/50): the course score is the weighted mean of the stored period "
                     "scores; Period 2 has no graded work so the current score is Period 1 alone."
                     if weighted else
                     "Grading periods without weights: the course score is computed from all assignments; "
                     "period scores are informational."),
                    ["weighted grading periods" if weighted else "unweighted grading periods",
                     "current_period_computed_* fields", "no due date -> last period"], p))

    b, p = _student_world("hidden-final-grades")
    c = _simple_course(b, p, "Scenario: Hidden Totals", "SCN 113", hide_final_grades=True)
    g = b.group(c, "Labs")
    a = b.assignment(c, g, "Lab 1", 20, _due(b, 9, 10), types=TXT)
    b.grade(c, a, 17, submitted=_due(b, 9, 10, 18), graded=_due(b, 9, 12, 9))
    out.append(("hidden-final-grades", "hide_final_grades=true: include[]=total_scores is ignored, so the enrollment "
                "has no computed_* keys at all (never render 0%). Assignment scores stay visible.",
                ["hidden final grades"], p))

    b, p = _student_world("late-and-missing")
    c = _simple_course(b, p, "Scenario: Late & Missing", "SCN 114")
    g = b.group(c, "Work")
    a = b.assignment(c, g, "Late with deduction", 20, _due(b, 9, 14), types=TXT)
    b.grade(c, a, 18, submitted=_due(b, 9, 15, 20, 30, 0), graded=_due(b, 9, 17, 9), deducted=2.0)
    a = b.assignment(c, g, "Missing (never submitted)", 20, _due(b, 9, 21), types=TXT)
    a = b.assignment(c, g, "Missing, marked 0 by teacher", 20, _due(b, 9, 22), types=TXT)
    b.grade(c, a, 0, graded=_due(b, 9, 25, 9), late_policy_status="missing")
    a = b.assignment(c, g, "Marked late manually (no deduction)", 10, _due(b, 9, 16), types=TXT)
    b.grade(c, a, 9, submitted=_due(b, 9, 16, 23, 0, 0), graded=_due(b, 9, 18, 9), late_policy_status="late",
            seconds_late_override=172800)
    a = b.assignment(c, g, "On-paper exam (never missing)", 50, _due(b, 9, 23, 10, 0, 0), types=("on_paper",))
    q = b.assignment(c, g, "Quiz submitted 30 s after due (60 s grace)", 10, _due(b, 9, 24, 10, 0, 0), quiz=True)
    b.grade(c, q, 8, submitted=_due(b, 9, 24, 10, 0, 30), graded=_due(b, 9, 24, 10, 1, 0))
    out.append(("late-and-missing", "late=true with points_deducted (score = entered_score - deduction); missing "
                "unsubmitted item (no score, seconds_late grows with now); teacher-marked missing with score 0 "
                "(counts); manual late status; on_paper never missing; quiz 60-second grace.",
                ["late", "missing", "late_policy_status", "seconds_late"], p))

    b, p = _student_world("concluded-course")
    c = _simple_course(b, p, "Scenario: Spring Course (concluded)", "SCN 090", workflow_state="completed",
                       enrollment_state="completed")
    c.term = b.term("Spring 2026", b.at(2026, 1, 12), b.at(2026, 5, 9), b.at(2025, 9, 1, 9, 0))
    g = b.group(c, "Work")
    for i, sc in enumerate([88, 92, None], 1):
        a = b.assignment(c, g, f"Assignment {i}", 100, b.at(2026, 2, 2 + 7 * i, 23, 59, 59), types=TXT,
                         created=b.at(2026, 1, 5))
        if sc is not None:
            b.grade(c, a, sc, submitted=b.at(2026, 2, 2 + 7 * i, 18), graded=b.at(2026, 2, 4 + 7 * i, 9))
    out.append(("concluded-course", "Hard-concluded course (workflow_state 'completed', enrollment_state "
                "'completed'); returned only for enrollment_state=completed, never by the enrollment_state=active "
                "request Tally makes. With every enrollment completed, Canvas drops unsubmitted/unposted items "
                "from the final score too.", ["concluded course"], p))

    b, p = _student_world("multiple-enrollments")
    c = _simple_course(b, p, "Scenario: Cross-listed Sections", "SCN 115", sections=2)
    g = b.group(c, "Work")
    a = b.assignment(c, g, "Essay", 100, _due(b, 9, 18), types=TXT)
    b.grade(c, a, 86, submitted=_due(b, 9, 18, 18), graded=_due(b, 9, 20, 9))
    out.append(("multiple-enrollments", "One course, two StudentEnrollment rows (lecture + lab section); each "
                "carries identical scores. De-duplicate by course id.", ["multiple enrollments"], p))

    b, p = _student_world("large-ids", course=184670000000012345, group=184670000000045678,
                          assignment=184670000000123456, submission=184670000009876543,
                          enrollment=184670000000777001, teacher=184670000000300001, term=184670000000000231)
    c = _simple_course(b, p, "Scenario: Cross-shard IDs", "SCN 116")
    g = b.group(c, "Work")
    a = b.assignment(c, g, "Shard test", 10, _due(b, 9, 18), types=TXT)
    b.grade(c, a, 9, submitted=_due(b, 9, 18, 18), graded=_due(b, 9, 20, 9))
    out.append(("large-ids", "Ids above 2^53 (9007199254740992), as produced by Canvas's sharded global ids; "
                "with Accept: application/json+canvas-string-ids they arrive as strings and must never be "
                "parsed as Double.", ["string IDs above 2^53"], p))

    for _, _, _, per in out:
        finalize(per)
    return out


def emit_grade_scenario(out: Out, name: str, desc: str, covers, p: Persona, quota: Quota) -> dict:
    now = p.captured_at
    routes = []
    c = p.courses[0]
    concluded = c.workflow_state == "completed"
    cparams = [("enrollment_state", "completed" if concluded else "active")] + \
        [("include[]", i) for i in COURSE_INCLUDES] + [("per_page", str(PER_PAGE))]
    clist = [S.course_json(x, p, now) for x in p.courses]
    for req, chunk, link in paginate_ordinal(clist, f"{BASE}/api/v1/courses", cparams, PER_PAGE):
        add_route(out, routes, endpoint="courses", method="GET", host=HOST, path="/api/v1/courses", params=req,
                  body_rel=f"scenarios/courses/{name}.json", body=canvas_body(chunk),
                  headers={"Link": link, **quota.charge("courses")})
    path = f"/api/v1/courses/{c.id}/assignment_groups"
    params = [("include[]", "assignments"), ("include[]", "submission"), ("per_page", str(PER_PAGE))]
    for req, chunk, link in paginate_ordinal(S.assignment_groups_json(c, p, now), BASE + path, params, PER_PAGE):
        add_route(out, routes, endpoint="assignment_groups", method="GET", host=HOST, path=path, params=req,
                  body_rel=f"scenarios/assignment_groups/{name}.json", body=canvas_body(chunk),
                  headers={"Link": link, **quota.charge("assignment_groups")})
    if c.gp_group:
        gpath = f"/api/v1/courses/{c.id}/grading_periods"
        body = S.grading_periods_json(c, p, now, BASE + gpath)
        for gp in body["grading_periods"]:
            stringify_ids(gp)
        link = body["meta"]["pagination"]["current"]
        add_route(out, routes, endpoint="grading_periods", method="GET", host=HOST, path=gpath, params=[],
                  body_rel=f"scenarios/grading_periods/{name}.json", body=canvas_body(body),
                  headers={"Link": f'<{link}>; rel="current",<{link}>; rel="first",<{link}>; rel="last"',
                           **quota.charge("grading_periods")})
    return {"id": f"grades/{name}", "description": desc, "covers": covers, "canvas_emits": True,
            "captured_at": iso_z(now), "routes": routes}


def emit_all_scenarios(out: Out, seed: int):
    quota = Quota(Rng.from_label(seed, "quota:scenarios"))
    scen = []
    expected = {}
    for name, desc, covers, p in grade_scenarios():
        scen.append(emit_grade_scenario(out, name, desc, covers, p, quota))
        expected[name] = expected_course(p.courses[0], p, p.captured_at)

    # --- access_restricted_by_date -----------------------------------------
    b, p = _student_world("access-restricted")
    c1 = _simple_course(b, p, "Scenario: Visible Course", "SCN 117")
    c2 = _simple_course(b, p, "Scenario: Restricted Past Course", "SCN 089", enrollment_state="completed")
    finalize(p)
    routes = []
    cparams = [("enrollment_state", "active")] + [("include[]", i) for i in COURSE_INCLUDES] + [("per_page", "100")]
    body = [S.course_json(c1, p, ANCHOR), S.access_restricted_course_json(c2)]
    for req, chunk, link in paginate_ordinal(body, f"{BASE}/api/v1/courses", cparams, 100):
        add_route(out, routes, endpoint="courses", method="GET", host=HOST, path="/api/v1/courses", params=req,
                  body_rel="scenarios/courses/access-restricted-by-date.json", body=canvas_body(chunk),
                  headers={"Link": link, **quota.charge("courses")})
    scen.append({"id": "courses/access-restricted-by-date", "canvas_emits": True, "captured_at": iso_z(ANCHOR),
                 "description": "courses_controller.rb always adds include 'access_restricted_by_date': a course "
                                "whose enrollments are all inactive and whose dates restrict access is returned as "
                                "{id, access_restricted_by_date: true} only. Treat as not viewable.",
                 "covers": ["access_restricted_by_date"], "routes": routes})

    # --- multi-page courses (numbered pages with rel=last) ---------------------
    b, p = _student_world("multi-page")
    for i, nm in enumerate(["Art History", "Botany", "Choir"]):
        c = _simple_course(b, p, nm, f"SCN 2{i}0")
    finalize(p)
    routes = []
    cparams = [("enrollment_state", "active")] + [("include[]", i) for i in COURSE_INCLUDES] + [("per_page", "2")]
    body = [S.course_json(c, p, ANCHOR) for c in p.courses]
    pages = paginate_ordinal(body, f"{BASE}/api/v1/courses", cparams, 2)
    for n, (req, chunk, link) in enumerate(pages, 1):
        add_route(out, routes, endpoint="courses", method="GET", host=HOST, path="/api/v1/courses", params=req,
                  body_rel=f"scenarios/courses/multi-page.page{n}.json", body=canvas_body(chunk),
                  headers={"Link": link, **quota.charge("courses")})
    scen.append({"id": "courses/multi-page", "canvas_emits": True, "captured_at": iso_z(ANCHOR),
                 "description": "Numbered pagination (Api.paginate over an Array): Link carries current/next/prev/"
                                "first/last; per_page=2 here only to force two pages.",
                 "covers": ["multi-page Link", "rel=last present"], "routes": routes})

    # --- multi-page planner (bookmarks, no rel=last) -----------------------------
    b, p = _student_world("planner-multi-page")
    c = _simple_course(b, p, "Scenario: Planner", "SCN 118")
    g = b.group(c, "Work")
    for i in range(5):
        b.assignment(c, g, f"Task {i + 1}", 10, _due(b, 9, 29 + i) if i < 2 else _due(b, 10, i - 1), types=TXT)
    finalize(p)
    routes = []
    items = S.planner_items(p, ANCHOR, b.at(2026, 9, 14), b.at(2026, 11, 27, 23, 59, 59))
    pparams = [("start_date", "2026-09-14"), ("end_date", "2026-11-27"), ("per_page", "2")]
    pages = paginate_bookmark([it for _, it in items], [[iso_z(k[0]), it["plannable_id"]] for k, it in items],
                              f"{BASE}/api/v1/planner/items", pparams, 2)
    for n, (req, chunk, link) in enumerate(pages, 1):
        add_route(out, routes, endpoint="planner_items", method="GET", host=HOST, path="/api/v1/planner/items",
                  params=req, body_rel=f"scenarios/planner_items/multi-page.page{n}.json", body=canvas_body(chunk),
                  headers={"Link": link, **quota.charge("planner_items")})
    scen.append({"id": "planner_items/multi-page", "canvas_emits": True, "captured_at": iso_z(ANCHOR),
                 "description": "BookmarkedCollection pagination: page=first, then opaque page=bookmark:... tokens; "
                                "no rel=last. Follow rel=next until absent.",
                 "covers": ["multi-page Link", "rel=last absent", "opaque next URL"], "routes": routes})

    # --- defensive pagination / header cases (not Canvas behaviour) --------------
    b, p = _student_world("pagination")
    c = _simple_course(b, p, "Scenario: Headers", "SCN 119")
    finalize(p)
    body = canvas_body([S.course_json(c, p, ANCHOR)])
    q = [("enrollment_state", "active")] + [("include[]", i) for i in COURSE_INCLUDES] + [("per_page", "100")]
    url1 = page_url(f"{BASE}/api/v1/courses", q, 1, 100)
    for sid, desc, link, lower in [
        ("pagination/lowercase-header-names", "HTTP/2 delivers lower-case header names (link, x-request-cost, "
         "x-rate-limit-remaining). Header lookup must be case-insensitive. Canvas-emitted over HTTP/2.",
         f'<{url1}>; rel="current",<{url1}>; rel="first",<{url1}>; rel="last"', True),
        ("pagination/next-link-foreign-host", "Defensive: rel=next points to a host outside the account's allowed "
         "set. The client must not attach the bearer token and must stop paginating (not Canvas behaviour).",
         f'<{url1}>; rel="current",<https://canvas.untrusted.example/api/v1/courses?page=2&per_page=100>; rel="next"',
         False),
        ("pagination/next-link-http", "Defensive: rel=next uses http://. The client must refuse it (not Canvas "
         "behaviour).", f'<{url1}>; rel="current",<http://{HOST}/api/v1/courses?page=2&per_page=100>; rel="next"',
         False)]:
        routes = []
        hdr = {"Link": link, **quota.charge("courses")}
        if lower:
            hdr = {k.lower(): v for k, v in hdr.items()}
        name = sid.split("/")[1]
        add_route(out, routes, endpoint="courses", method="GET", host=HOST, path="/api/v1/courses", params=q,
                  body_rel=f"scenarios/pagination/{name}.json", body=body, headers=hdr,
                  content_type=JSON_CT)
        if lower:
            hd = out.files[routes[0]["headers"]]
            import json as _j
            doc = _j.loads(hd)
            doc["headers"] = {k.lower(): v for k, v in doc["headers"].items()}
            out.files[routes[0]["headers"]] = (_j.dumps(doc, indent=2) + "\n").encode()
        scen.append({"id": sid, "canvas_emits": lower, "captured_at": iso_z(ANCHOR), "description": desc,
                     "covers": ["pagination safety"], "routes": routes})

    # --- dates: parser robustness (explicitly NOT Canvas REST output) ------------
    t = datetime(2026, 9, 28, 13, 0, 0, 123456, tzinfo=timezone.utc)
    variants = [
        {"form": "canvas_rest", "value": "2026-09-28T13:00:00Z", "canvas_emits": True,
         "source": "config/initializers/json.rb time_precision = 0; config/initializers/time.rb JsonTimeInUTC"},
        {"form": "offset", "value": iso_offset(t.replace(microsecond=0), "America/Chicago"), "canvas_emits": False},
        {"form": "offset_no_colon", "value": iso_offset(t.replace(microsecond=0), "America/New_York").replace("-04:00", "-0400"),
         "canvas_emits": False},
        {"form": "fraction_3", "value": "2026-09-28T13:00:00.123Z", "canvas_emits": False},
        {"form": "fraction_6_offset", "value": iso_offset(t, "America/Los_Angeles", 6), "canvas_emits": False},
        {"form": "date_only", "value": "2026-09-28", "canvas_emits": True,
         "source": "calendar event all_day_date (Date)"},
        {"form": "quiz_submission_body_time", "value": "2026-09-17 15:38:12 +0000", "canvas_emits": True,
         "source": "classic quiz submission body text, not a timestamp field"},
    ]
    out.json("scenarios/dates/iso8601-variants.json", {
        "synthetic": True, "instant_utc": "2026-09-28T13:00:00.123456Z",
        "note": "Parser-robustness input for WP-B05, not a Canvas response. canvas-lms serializes Time values in "
                "the endpoints Tally calls as UTC 'Z' with zero fractional digits; offsets and fractions appear "
                "in GraphQL, in some other REST fields (e.g. user last_login via Time#iso8601), and in "
                "developer-doc examples. Every 'offset'/'fraction' value denotes the same instant as "
                "instant_utc truncated as shown.", "values": variants})
    scen.append({"id": "dates/iso8601-variants", "canvas_emits": False, "captured_at": iso_z(ANCHOR),
                 "description": "Date-parser input with offsets and fractional seconds (see file note).",
                 "covers": ["ISO 8601 offsets", "fractional seconds"], "routes": [],
                 "file": "scenarios/dates/iso8601-variants.json"})

    # --- empty collections ---------------------------------------------------------
    b, p = _student_world("no-grading-periods")
    c = _simple_course(b, p, "Scenario: No Periods", "SCN 120")
    finalize(p)
    routes = []
    gpath = f"/api/v1/courses/{c.id}/grading_periods"
    body = S.grading_periods_json(c, p, ANCHOR, BASE + gpath)
    link = body["meta"]["pagination"]["current"]
    add_route(out, routes, endpoint="grading_periods", method="GET", host=HOST, path=gpath, params=[],
              body_rel="scenarios/grading_periods/none.json", body=canvas_body(body),
              headers={"Link": f'<{link}>; rel="current",<{link}>; rel="first",<{link}>; rel="last"',
                       **quota.charge("grading_periods")})
    scen.append({"id": "grading_periods/none", "canvas_emits": True, "captured_at": iso_z(ANCHOR),
                 "description": "Course without grading periods (Tally only calls this when has_grading_periods, "
                                "but the empty envelope is valid).", "covers": ["empty grading periods"],
                 "routes": routes})

    scen += emit_errors(out, quota)
    scen += emit_accounts_search(out, seed)
    return scen, expected


# ----------------------------------------------------------------------------
# Errors
# ----------------------------------------------------------------------------

ERRORS = [
    # file, status, content-type, body, extra headers, description, source
    ("401-invalid-access-token.json", 401, JSON_CT, {"errors": [{"message": "Invalid access token."}]},
     {"WWW-Authenticate": 'Bearer realm="canvas-lms"'},
     "OAuth access token past expires_at (AccessToken#usable? false -> AccessTokenError). This is what an "
     "expired 1-hour token returns: refresh once, then authExpired.",
     "app/controllers/application_controller.rb#api_error_json; lib/authentication_methods.rb; app/models/access_token.rb"),
    ("401-expired-access-token.json", 401, JSON_CT,
     {"errors": [{"message": "Expired access token.", "expired_at": "2026-09-28T12:00:00Z"}]},
     {"WWW-Authenticate": 'Bearer realm="canvas-lms"'},
     "Token past permanent_expires_at (ExpiredAccessTokenError).", "same"),
    ("401-revoked-access-token.json", 401, JSON_CT, {"errors": [{"message": "Revoked access token."}]},
     {"WWW-Authenticate": 'Bearer realm="canvas-lms"'}, "Token deleted/revoked (RevokedAccessTokenError).", "same"),
    ("401-insufficient-scopes.json", 401, JSON_CT, {"errors": [{"message": "Insufficient scopes on access token."}]},
     {}, "Scoped developer key missing the endpoint's scope (AccessTokenScopeError, mapped to 401 in "
     "config/application.rb).", "same; config/application.rb rescue_responses"),
    ("401-unauthenticated.json", 401, JSON_CT,
     {"status": "unauthenticated", "errors": [{"message": "user authorization required"}]},
     {"WWW-Authenticate": 'Bearer realm="canvas-lms"'}, "No credentials at all.",
     "lib/authentication_methods.rb#render_json_unauthorized"),
    ("403-unauthorized.json", 403, JSON_CT,
     {"status": "unauthorized", "errors": [{"message": "user not authorized to perform that action"}]},
     {}, "Authenticated but not permitted. A 403 that is NOT a rate limit (no 'Rate Limit Exceeded').",
     "lib/authentication_methods.rb#render_json_unauthorized"),
    ("403-rate-limit-exceeded.txt", 403, "text/plain; charset=utf-8", "403 Forbidden (Rate Limit Exceeded)\n",
     {"X-Rate-Limit-Remaining": "0.0"}, "Throttled (default hosted behaviour). Plain text, not JSON; no X-Request-Cost.",
     "app/middleware/request_throttle.rb#rate_limit_exceeded"),
    ("429-rate-limit-exceeded.txt", 429, "text/plain; charset=utf-8", "429 Too Many Requests (Rate Limit Exceeded)\n",
     {"X-Rate-Limit-Remaining": "0.0"}, "Throttled when Setting request_throttle.send_429_response is true.",
     "app/middleware/request_throttle.rb#rate_limit_exceeded"),
    ("404-not-found.json", 404, JSON_CT, {"errors": [{"message": "The specified resource does not exist."}]},
     {}, "Course (or other record) not found / deleted.", "application_controller.rb#api_error_json"),
    ("500-internal-server-error.json", 500, JSON_CT,
     {"errors": [{"message": "An error occurred.", "error_code": "internal_server_error"}],
      "error_report_id": 81233407}, {}, "Unhandled server error; error_report_id is stringified with string ids.",
     "application_controller.rb#rescue_action_in_api"),
]


def emit_errors(out: Out, quota: Quota):
    scen = []
    catalog = []
    for fname, status, ctype, body, extra, desc, src in ERRORS:
        if isinstance(body, dict):
            data = canvas_body(dict(body))
        else:
            data = body.encode()
        rel = f"errors/{fname}"
        out.put(rel, data)
        hdr = {"Content-Type": ctype, **extra}
        out.json(rel.rsplit(".", 1)[0] + ".headers.json", {"status": status, "headers": hdr})
        catalog.append({"file": rel, "status": status, "description": desc, "source": src})
    # endpoint-bound scenarios that reuse the catalog bodies
    bind = [
        ("courses/rate-limited-429", "courses", "/api/v1/courses", "429-rate-limit-exceeded.txt"),
        ("courses/rate-limited-403", "courses", "/api/v1/courses", "403-rate-limit-exceeded.txt"),
        ("courses/forbidden-403", "courses", "/api/v1/courses", "403-unauthorized.json"),
        ("profile/token-invalid-401", "profile", "/api/v1/users/self/profile", "401-invalid-access-token.json"),
        ("profile/token-expired-401", "profile", "/api/v1/users/self/profile", "401-expired-access-token.json"),
        ("profile/token-revoked-401", "profile", "/api/v1/users/self/profile", "401-revoked-access-token.json"),
        ("profile/unauthenticated-401", "profile", "/api/v1/users/self/profile", "401-unauthenticated.json"),
        ("planner_items/insufficient-scope-401", "planner_items", "/api/v1/planner/items", "401-insufficient-scopes.json"),
        ("assignment_groups/course-not-found-404", "assignment_groups", "/api/v1/courses/51899/assignment_groups",
         "404-not-found.json"),
        ("calendar_events/server-error-500", "calendar_events", "/api/v1/calendar_events",
         "500-internal-server-error.json"),
    ]
    q_by_ep = {
        "courses": [("enrollment_state", "active")] + [("include[]", i) for i in COURSE_INCLUDES] + [("per_page", "100")],
        "profile": [],
        "planner_items": [("start_date", "2026-09-14"), ("end_date", "2026-11-27"), ("per_page", "100")],
        "assignment_groups": [("include[]", "assignments"), ("include[]", "submission"), ("per_page", "100")],
        "calendar_events": [("type", "event"), ("context_codes[]", "course_51842"), ("start_date", "2026-09-14"),
                            ("end_date", "2026-11-27"), ("per_page", "100")],
    }
    for sid, ep, path, fname in bind:
        ext = fname.rsplit(".", 1)[1]
        rel = f"scenarios/{sid}.{ext}"
        src = out.files[f"errors/{fname}"]
        hdr_doc = __import__("json").loads(out.files[f"errors/{fname.rsplit('.', 1)[0]}.headers.json"])
        routes = []
        add_route(out, routes, endpoint=ep, method="GET", host=HOST, path=path, params=q_by_ep[ep],
                  body_rel=rel, body=src, status=hdr_doc["status"],
                  headers={k: v for k, v in hdr_doc["headers"].items() if k != "Content-Type"},
                  content_type=hdr_doc["headers"]["Content-Type"])
        entry = next(e for e in catalog if e["file"] == f"errors/{fname}")
        scen.append({"id": sid, "canvas_emits": True, "captured_at": iso_z(ANCHOR),
                     "description": entry["description"], "source": entry["source"],
                     "covers": [f"HTTP {hdr_doc['status']}"], "routes": routes})
    out.json("errors/index.json", {"synthetic": True, "errors": catalog})
    return scen


# ----------------------------------------------------------------------------
# Institution search (onboarding, unauthenticated, canvas.instructure.com)
# ----------------------------------------------------------------------------

SCHOOLS = [
    (1017, "Northfield State University", "canvas.northfield.example", "saml"),
    (2231, "Northfield Community College", "northfieldcc.instructure.example", "canvas"),
    (3302, "North Ridge Technical Institute", "nrti.instructure.example", "openid_connect"),
    (4410, "Northgate Online Academy", "northgate.instructure.example", "canvas"),
    (5566, "Lakeshore University", "canvas.lakeshore.example", "38"),
    (6120, "Harbor City College", "harborcity.instructure.example", "saml"),
]


def emit_accounts_search(out: Out, seed: int):
    quota = Quota(Rng.from_label(seed, "quota:accounts_search"))
    host = "canvas.instructure.com"
    scen = []
    for name in ["north", "northfield", "lakeshore", "zzqx"]:
        hits = [{"id": i, "name": n, "domain": d, "distance": None, "authentication_provider": ap}
                for i, n, d, ap in SCHOOLS if name in n.lower()]
        routes = []
        params = [("name", name)]
        for req, chunk, link in paginate_ordinal(hits, f"https://{host}/api/v1/accounts/search", params, 10):
            add_route(out, routes, endpoint="accounts_search", method="GET", host=host,
                      path="/api/v1/accounts/search", params=req,
                      body_rel=f"scenarios/accounts_search/{'no-match' if not hits else name}.json",
                      body=canvas_body(chunk), headers={"Link": link, **quota.charge("accounts_search")})
        scen.append({"id": f"accounts_search/{'no-match' if not hits else name}", "canvas_emits": True,
                     "captured_at": iso_z(ANCHOR),
                     "description": "Institution directory search used by onboarding (unauthenticated). Field set "
                                    "and Link format observed live on 2026-09-26 (not in the REST docs); every "
                                    "school here is fictional. ids are strings because Tally sends the "
                                    "canvas-string-ids Accept header (ints were observed without it).",
                     "covers": ["institution search"], "routes": routes})
    return scen
