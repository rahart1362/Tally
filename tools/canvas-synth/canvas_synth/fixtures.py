"""Persona fixture generation: one file per request, headers sidecars, route
table entries, expected grades and the flagship change digest."""
from __future__ import annotations

from datetime import date, datetime, timedelta

from . import gradecalc
from . import serialize as S
from .emit import (Out, Quota, add_route, canvas_body, paginate_bookmark, paginate_ordinal)
from .jsonfmt import recursively_stringify_ids, stringify_ids
from .model import Persona
from .prng import Rng
from .tz import iso_z, local_to_utc, utc_to_local

PLANNER_BACK, PLANNER_AHEAD = 14, 60          # TallyConfig.plannerWindow = -14...+60 d
ANNOUNCEMENT_BACK = 14                        # TallyConfig.announcementWindow = 14 d
CONTEXT_CODES_PER_REQUEST = 10                # TallyConfig.contextCodesPerRequest
PER_PAGE = 100
ANNOUNCEMENT_PER_PAGE = 50

COURSE_INCLUDES = ["total_scores", "current_grading_period_scores", "term", "teachers"]


def active_courses(p: Persona):
    cs = [c for c in p.courses
          if c.workflow_state == "available" and any(e.workflow_state == "active" for e in c.enrollments)]
    return sorted(cs, key=lambda c: (c.name.casefold(), c.id))


def windows(p: Persona):
    now = p.captured_at
    today = utc_to_local(p.user.time_zone, now).date()
    ps, pe = today - timedelta(days=PLANNER_BACK), today + timedelta(days=PLANNER_AHEAD)
    tz = p.user.time_zone
    return {
        "planner_start": ps, "planner_end": pe,
        "start_utc": local_to_utc(tz, ps.year, ps.month, ps.day),
        "end_utc": local_to_utc(tz, pe.year, pe.month, pe.day, 23, 59, 59),
        "ann_start": today - timedelta(days=ANNOUNCEMENT_BACK),
    }


def course_list_json(p: Persona, now, courses=None):
    return [S.course_json(c, p, now) for c in (courses or active_courses(p))]


def emit_persona(out: Out, p: Persona, prefix: str, *, seed: int) -> dict:
    now = p.captured_at
    host = p.host
    base = f"https://{host}"
    routes: list = []
    quota = Quota(Rng.from_label(seed, f"quota:{p.key}:{prefix}"))
    w = windows(p)
    courses = active_courses(p)

    # 1 profile
    add_route(out, routes, endpoint="profile", method="GET", host=host, path="/api/v1/users/self/profile",
              params=[], body_rel=f"{prefix}/profile.json", body=canvas_body(S.profile_json(p)),
              headers=quota.charge("profile"))

    # 2 courses
    cparams = [("enrollment_state", "active")] + [("include[]", i) for i in COURSE_INCLUDES] + [("per_page", str(PER_PAGE))]
    clist = course_list_json(p, now, courses)
    pages = paginate_ordinal(clist, f"{base}/api/v1/courses", cparams, PER_PAGE)
    for n, (req, chunk, link) in enumerate(pages, start=1):
        rel = f"{prefix}/courses.json" if len(pages) == 1 else f"{prefix}/courses.page{n}.json"
        add_route(out, routes, endpoint="courses", method="GET", host=host, path="/api/v1/courses", params=req,
                  body_rel=rel, body=canvas_body(chunk), headers={"Link": link, **quota.charge("courses")})

    # 3 assignment groups
    for c in courses:
        path = f"/api/v1/courses/{c.id}/assignment_groups"
        params = [("include[]", "assignments"), ("include[]", "submission"), ("per_page", str(PER_PAGE))]
        groups = S.assignment_groups_json(c, p, now)
        for req, chunk, link in paginate_ordinal(groups, base + path, params, PER_PAGE):
            add_route(out, routes, endpoint="assignment_groups", method="GET", host=host, path=path, params=req,
                      body_rel=f"{prefix}/assignment_groups/{c.id}.json", body=canvas_body(chunk),
                      headers={"Link": link, **quota.charge("assignment_groups")})

    # 4 grading periods (only where has_grading_periods)
    for c in courses:
        if not (c.gp_group and c.gp_group.periods):
            continue
        path = f"/api/v1/courses/{c.id}/grading_periods"
        body = S.grading_periods_json(c, p, now, base + path)
        for gp in body["grading_periods"]:
            stringify_ids(gp)   # Canvas::APISerialization#stringify! (always, non-recursive)
        link = body["meta"]["pagination"]["current"]
        add_route(out, routes, endpoint="grading_periods", method="GET", host=host, path=path, params=[],
                  body_rel=f"{prefix}/grading_periods/{c.id}.json", body=canvas_body(body, stringify=True),
                  headers={"Link": f'<{link}>; rel="current",<{link}>; rel="first",<{link}>; rel="last"',
                           **quota.charge("grading_periods")})

    # 5 planner
    items = S.planner_items(p, now, w["start_utc"], w["end_utc"])
    pparams = [("start_date", w["planner_start"].isoformat()), ("end_date", w["planner_end"].isoformat()),
               ("per_page", str(PER_PAGE))]
    keys = [[iso_z(k[0]), it.get("plannable_id")] for k, it in items]
    pages = paginate_bookmark([it for _, it in items], keys, f"{base}/api/v1/planner/items", pparams, PER_PAGE)
    for n, (req, chunk, link) in enumerate(pages, start=1):
        rel = f"{prefix}/planner_items.json" if len(pages) == 1 else f"{prefix}/planner_items.page{n}.json"
        add_route(out, routes, endpoint="planner_items", method="GET", host=host, path="/api/v1/planner/items",
                  params=req, body_rel=rel, body=canvas_body(chunk),
                  headers={"Link": link, **quota.charge("planner_items")})

    # 6 calendar events, chunked by <= 10 context codes
    chunks = [courses[i:i + CONTEXT_CODES_PER_REQUEST] for i in range(0, len(courses), CONTEXT_CODES_PER_REQUEST)]
    for ci, chunk_courses in enumerate(chunks, start=1):
        evs = []
        for c in chunk_courses:
            for e in c.events:
                if e.created_at <= now and w["start_utc"] <= e.start_at <= w["end_utc"]:
                    evs.append((e.start_at, e.id, S.event_json(e, c, p)))
        evs.sort(key=lambda t: (t[0], t[1]))
        params = [("type", "event")] + [("context_codes[]", f"course_{c.id}") for c in chunk_courses] + [
            ("start_date", w["planner_start"].isoformat()), ("end_date", w["planner_end"].isoformat()),
            ("per_page", str(PER_PAGE))]
        pages = paginate_bookmark([e for *_, e in evs], [[iso_z(t[0]), t[1]] for t in evs],
                                  f"{base}/api/v1/calendar_events", params, PER_PAGE)
        for n, (req, chunk, link) in enumerate(pages, start=1):
            rel = f"{prefix}/calendar_events.chunk{ci}.json" if len(pages) == 1 else \
                f"{prefix}/calendar_events.chunk{ci}.page{n}.json"
            add_route(out, routes, endpoint="calendar_events", method="GET", host=host,
                      path="/api/v1/calendar_events", params=req, body_rel=rel, body=canvas_body(chunk),
                      headers={"Link": link, **quota.charge("calendar_events")})

    # 7 announcements, chunked by <= 10 context codes; default end = start + 28 d
    tz = p.user.time_zone
    a0 = w["ann_start"]
    a_start = local_to_utc(tz, a0.year, a0.month, a0.day)
    a_end = a_start + timedelta(days=28)
    for ci, chunk_courses in enumerate(chunks, start=1):
        anns = []
        for c in chunk_courses:
            for an in c.announcements:
                if a_start <= an.posted_at <= min(a_end, now):
                    anns.append((an.posted_at, an.id, S.announcement_json(an, c, p, now)))
        anns.sort(key=lambda t: (t[0], t[1]), reverse=True)
        params = [("context_codes[]", f"course_{c.id}") for c in chunk_courses] + [
            ("start_date", a0.isoformat()), ("per_page", str(ANNOUNCEMENT_PER_PAGE))]
        pages = paginate_ordinal([t[2] for t in anns], f"{base}/api/v1/announcements", params,
                                 ANNOUNCEMENT_PER_PAGE)
        for n, (req, chunk, link) in enumerate(pages, start=1):
            rel = f"{prefix}/announcements.chunk{ci}.json" if len(pages) == 1 else \
                f"{prefix}/announcements.chunk{ci}.page{n}.json"
            add_route(out, routes, endpoint="announcements", method="GET", host=host,
                      path="/api/v1/announcements", params=req, body_rel=rel, body=canvas_body(chunk),
                      headers={"Link": link, **quota.charge("announcements")})

    # 8 colors
    add_route(out, routes, endpoint="colors", method="GET", host=host, path="/api/v1/users/self/colors",
              params=[], body_rel=f"{prefix}/colors.json", body=canvas_body(S.colors_json(p)),
              headers=quota.charge("colors"))

    return {
        "key": p.key, "title": p.title, "description": p.description, "synthetic": True,
        "school": p.school, "host": host, "user_id": str(p.user.id), "user_name": p.user.name,
        "time_zone": p.user.time_zone, "captured_at": iso_z(p.captured_at), "anchor": iso_z(p.anchor),
        "course_ids": [str(c.id) for c in courses], "request_count": len(routes),
        "covers": p.covers, "routes": routes,
    }


# ----------------------------------------------------------------------------
# Expected grades
# ----------------------------------------------------------------------------

def _dec(x):
    return float(x)


def expected_course(c, p: Persona, now) -> dict:
    sc = S.course_scores(c, now)
    periods = S.periods_of(c)
    cur = gradecalc.current_grading_period(periods, now) if periods else None
    names = {g.id: g.name for g in c.groups}
    groups = []
    for kind in ("current", "final"):
        pass
    for gc, gf in zip(sc["groups"]["current"], sc["groups"]["final"]):
        groups.append({
            "id": str(gc["id"]), "name": names[gc["id"]], "group_weight": gc["weight"],
            "current": {"score": _dec(gc["score"]), "possible": _dec(gc["possible"]), "grade": gc["grade"],
                        "dropped_submission_ids": [str(x) for x in gc["dropped"]]},
            "final": {"score": _dec(gf["score"]), "possible": _dec(gf["possible"]), "grade": gf["grade"],
                      "dropped_submission_ids": [str(x) for x in gf["dropped"]]},
        })
    gps = []
    for gp in periods:
        v = sc["grading_periods"][str(gp["id"])]
        gps.append({"id": str(gp["id"]), "title": gp["title"], "weight": gp["weight"],
                    "current_score": v["current_score"], "final_score": v["final_score"],
                    "current_grade": S.letter(c, v["current_score"]), "final_grade": S.letter(c, v["final_score"])})
    return {
        "course_id": str(c.id), "course_code": c.course_code, "name": c.name,
        "apply_assignment_group_weights": c.apply_weights,
        "weighted_grading_periods": sc["weighted_grading_periods"],
        "hide_final_grades": c.hide_final_grades,
        "visible_in_api": not c.hide_final_grades,
        "grading_standard_id": None if c.grading_standard_id is None else str(c.grading_standard_id),
        "grading_scheme": ([[n, v] for n, v in c.scheme_or_default()] if c.grading_standard_enabled() else None),
        "current_score": sc["current_score"], "final_score": sc["final_score"],
        "current_grade": S.letter(c, sc["current_score"]), "final_grade": S.letter(c, sc["final_score"]),
        "unposted_current_score": sc["unposted_current_score"], "unposted_final_score": sc["unposted_final_score"],
        "current_grading_period_id": None if cur is None else str(cur["id"]),
        "grading_periods": gps,
        "assignment_groups": groups,
        "design_target_current_score": c.target_current_score,
        "notes": c.notes or None,
    }


def expected_grades(p: Persona) -> dict:
    now = p.captured_at
    courses = [expected_course(c, p, now) for c in active_courses(p)]
    vis = [c["current_score"] for c in courses if c["visible_in_api"] and c["current_score"] is not None]
    return {
        "persona": p.key, "synthetic": True, "captured_at": iso_z(now), "tolerance": 0.01,
        "calculator": "tools/canvas-synth/canvas_synth/gradecalc.py -- port of canvas-lms lib/grade_calculator.rb "
                      "@ 1c9f0bb8013ed69c4f2efe11fd483025469b7e6c",
        "parity_rule": "GradeEngine.currentScore(course) == current_score +/- tolerance, computed only from the "
                       "persona's fixture responses (courses, assignment_groups, grading_periods).",
        "caveat": "Synthetic parity proves consistency with this port of Canvas's algorithm only; it does not "
                  "replace an owner-run recording against real Canvas (WP-B07).",
        "courses": courses,
        "tally_overall": {"definition": "mean of visible current scores (Tally 'Average of N courses'; not a "
                                        "Canvas value)",
                          "courses_counted": len(vis),
                          "mean_current_score": (gradecalc.ruby_float_round(sum(vis) / len(vis), 2) if vis else None)},
    }


# ----------------------------------------------------------------------------
# Change digest between two observations of the same world
# ----------------------------------------------------------------------------

def digest(prev: Persona, cur: Persona) -> dict:
    t0, t1 = prev.captured_at, cur.captured_at
    changes = []
    for c in active_courses(cur):
        s0, s1 = S.course_scores(c, t0), S.course_scores(c, t1)
        if s0["current_score"] != s1["current_score"] and not c.hide_final_grades:
            changes.append({"kind": "course_score_changed", "course_id": str(c.id), "course_code": c.course_code,
                            "from": s0["current_score"], "to": s1["current_score"],
                            "delta": gradecalc.ruby_float_round(s1["current_score"] - s0["current_score"], 2)})
        for a in c.assignments:
            if a.created_at > t1:
                continue
            if t0 < a.created_at <= t1:
                changes.append({"kind": "new_assignment", "course_id": str(c.id), "assignment_id": str(a.id),
                                "name": a.name, "due_at": iso_z(a.due_at_as_of(t1))})
                continue
            d0, d1 = a.due_at_as_of(t0), a.due_at_as_of(t1)
            if d0 != d1:
                changes.append({"kind": "due_date_changed", "course_id": str(c.id), "assignment_id": str(a.id),
                                "name": a.name, "from": iso_z(d0), "to": iso_z(d1)})
            s = c.submissions.get(a.id)
            if s:
                st0, st1 = s.state(a, t0), s.state(a, t1)
                v0 = st0["score"] if st0["posted"] else None
                v1 = st1["score"] if st1["posted"] else None
                if v0 != v1 or (st1["excused"] and not st0["excused"]):
                    changes.append({"kind": "newly_graded" if v0 is None else "score_changed",
                                    "course_id": str(c.id), "assignment_id": str(a.id), "submission_id": str(s.id),
                                    "name": a.name, "from": v0, "to": v1, "points_possible": a.points_possible})
                if st1["submitted"] and not st0["submitted"]:
                    changes.append({"kind": "submitted", "course_id": str(c.id), "assignment_id": str(a.id),
                                    "name": a.name, "submitted_at": iso_z(s.submitted_at)})
        for an in c.announcements:
            if t0 < an.posted_at <= t1:
                changes.append({"kind": "new_announcement", "course_id": str(c.id), "announcement_id": str(an.id),
                                "title": an.title, "posted_at": iso_z(an.posted_at)})
    return {"synthetic": True, "previous": {"persona": prev.key, "captured_at": iso_z(t0)},
            "current": {"persona": cur.key, "captured_at": iso_z(t1)},
            "note": "Ground truth from the generator's world model; ChangeDigest tests apply Tally's own "
                    "course-score threshold to course_score_changed.",
            "changes": changes}


# ----------------------------------------------------------------------------
# (g) Parent / observer
# ----------------------------------------------------------------------------

def emit_observer_account(out: Out, student: Persona, observer: dict, prefix: str, *, seed: int) -> dict:
    """Routes a linked observer's session would make on the student's
    institution. Shapes: app/controllers/user_observees_controller.rb#index
    (users_json + observation_link_root_account_ids), courses_controller.rb
    #courses_for_user with include[]=observed_users (ObserverEnrollment rows
    followed by the observed StudentEnrollment rows), lib/api/v1/assignment.rb
    #submissions_hash (``submission`` becomes an array with observed_users),
    planner_controller.rb (GET /api/v1/users/:user_id/planner/items)."""
    now = student.captured_at
    host = student.host
    base = f"https://{host}"
    routes: list = []
    quota = Quota(Rng.from_label(seed, f"quota:observer:{prefix}"))
    courses = active_courses(student)
    oid = observer["id"]

    prof = {"id": oid, "name": observer["name"], "short_name": observer["name"],
            "sortable_name": observer["sortable_name"], "avatar_url": S.avatar_fallback(host), "title": None,
            "bio": None, "pronunciation": None, "primary_email": observer["email"], "login_id": observer["login_id"],
            "integration_id": None, "time_zone": student.user.time_zone, "locale": None, "effective_locale": "en",
            "calendar": {"ics": f"{base}/feeds/calendars/user_{observer['feed_uuid']}.ics"},
            "lti_user_id": observer["lti_user_id"], "k5_user": False, "use_classic_font_in_k5": False}
    add_route(out, routes, endpoint="profile", method="GET", host=host, path="/api/v1/users/self/profile",
              params=[], body_rel=f"{prefix}/profile.json", body=canvas_body(prof), headers=quota.charge("profile"))

    u = student.user
    observees = [{"id": u.id, "name": u.name, "created_at": iso_z(u.created_at), "sortable_name": u.sortable_name,
                  "short_name": u.short_name, "avatar_url": S.avatar_fallback(host),
                  "observation_link_root_account_ids": [courses[0].root_account_id if courses else 1]}]
    oparams = [("include[]", "avatar_url"), ("per_page", str(PER_PAGE))]
    for req, chunk, link in paginate_ordinal(observees, f"{base}/api/v1/users/self/observees", oparams, PER_PAGE):
        add_route(out, routes, endpoint="observees", method="GET", host=host, path="/api/v1/users/self/observees",
                  params=req, body_rel=f"{prefix}/observees.json", body=canvas_body(chunk),
                  headers={"Link": link, **quota.charge("observees")})

    clist = []
    for c in courses:
        h = S.course_json(c, student, now)
        obs_rows = [{"type": "observer", "role": "ObserverEnrollment", "role_id": observer["observer_role_id"],
                     "user_id": oid, "enrollment_state": "active", "limit_privileges_to_course_section": False,
                     "associated_user_id": u.id}]
        h["enrollments"] = obs_rows + S.enrollment_hashes(c, student, now)
        clist.append(h)
    cparams = ([("enrollment_state", "active")] + [("include[]", i) for i in COURSE_INCLUDES + ["observed_users"]]
               + [("per_page", str(PER_PAGE))])
    for req, chunk, link in paginate_ordinal(clist, f"{base}/api/v1/courses", cparams, PER_PAGE):
        add_route(out, routes, endpoint="courses", method="GET", host=host, path="/api/v1/courses", params=req,
                  body_rel=f"{prefix}/courses.json", body=canvas_body(chunk),
                  headers={"Link": link, **quota.charge("courses")})

    for c in courses:
        path = f"/api/v1/courses/{c.id}/assignment_groups"
        params = [("include[]", "assignments"), ("include[]", "submission"), ("include[]", "observed_users"),
                  ("per_page", str(PER_PAGE))]
        groups = S.assignment_groups_json(c, student, now)
        for g in groups:
            for a in g["assignments"]:
                if "submission" in a:
                    a["submission"] = [a["submission"]]
        for req, chunk, link in paginate_ordinal(groups, base + path, params, PER_PAGE):
            add_route(out, routes, endpoint="assignment_groups", method="GET", host=host, path=path, params=req,
                      body_rel=f"{prefix}/assignment_groups/{c.id}.json", body=canvas_body(chunk),
                      headers={"Link": link, **quota.charge("assignment_groups")})

    for c in courses:
        if not (c.gp_group and c.gp_group.periods):
            continue
        path = f"/api/v1/courses/{c.id}/grading_periods"
        body = S.grading_periods_json(c, student, now, base + path)
        for gp in body["grading_periods"]:
            stringify_ids(gp)
        link = body["meta"]["pagination"]["current"]
        add_route(out, routes, endpoint="grading_periods", method="GET", host=host, path=path, params=[],
                  body_rel=f"{prefix}/grading_periods/{c.id}.json", body=canvas_body(body),
                  headers={"Link": f'<{link}>; rel="current",<{link}>; rel="first",<{link}>; rel="last"',
                           **quota.charge("grading_periods")})

    w = windows(student)
    items = S.planner_items(student, now, w["start_utc"], w["end_utc"])
    pparams = ([("context_codes[]", f"course_{c.id}") for c in courses] +
               [("start_date", w["planner_start"].isoformat()), ("end_date", w["planner_end"].isoformat()),
                ("per_page", str(PER_PAGE))])
    keys = [[iso_z(k[0]), it.get("plannable_id")] for k, it in items]
    ppath = f"/api/v1/users/{u.id}/planner/items"
    pages = paginate_bookmark([it for _, it in items], keys, base + ppath, pparams, PER_PAGE)
    for n, (req, chunk, link) in enumerate(pages, start=1):
        rel = f"{prefix}/planner_items.json" if len(pages) == 1 else f"{prefix}/planner_items.page{n}.json"
        add_route(out, routes, endpoint="planner_items", method="GET", host=host, path=ppath, params=req,
                  body_rel=rel, body=canvas_body(chunk), headers={"Link": link, **quota.charge("planner_items")})

    return {"host": host, "school": student.school, "observer_user_id": str(oid),
            "observee": {"persona": student.key, "user_id": str(u.id), "name": u.name},
            "course_ids": [str(c.id) for c in courses], "request_count": len(routes), "routes": routes}
