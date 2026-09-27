"""Canvas-shaped JSON builders for a *student* caller.

Key order and field presence follow the canvas-lms serializers at commit
1c9f0bb (see each function's docstring). Values are built with integer ids;
the emitter applies StringifyIds (``Accept: application/json+canvas-string-ids``).
"""
from __future__ import annotations

import base64
import hashlib
import json
from datetime import datetime, timedelta

from . import gradecalc
from .model import Announcement, Assignment, Course, Event, Persona, Submission, Teacher
from .tz import iso_z, utc_to_local


def _b36(n: int) -> str:
    digits = "0123456789abcdefghijklmnopqrstuvwxyz"
    out = ""
    n = int(n)
    while True:
        n, r = divmod(n, 36)
        out = digits[r] + out
        if n == 0:
            return out


def avatar_fallback(host: str) -> str:
    return f"https://{host}/images/messages/avatar-50.png"


# ----------------------------------------------------------------------------
# Grade calculation input
# ----------------------------------------------------------------------------

def periods_of(c: Course):
    if not c.gp_group:
        return []
    return [{"id": p.id, "weight": p.weight, "start_date": p.start_date, "end_date": p.end_date,
             "close_date": p.close_date, "title": p.title} for p in c.gp_group.periods]


def visible_assignments(c: Course, now: datetime):
    return [a for a in c.assignments if a.created_at <= now]


def calc_input(c: Course, now: datetime) -> dict:
    periods = periods_of(c)
    assignments, submissions = [], []
    for a in visible_assignments(c, now):
        due = a.due_at_as_of(now)
        assignments.append({
            "id": a.id, "assignment_group_id": a.group_id, "points_possible": a.points_possible,
            "omit_from_final_grade": a.omit_from_final_grade, "gradeable": a.gradeable(), "published": True,
            "grading_period_id": gradecalc.grading_period_for_due_at(due, periods) if periods else None,
        })
        s = c.submissions.get(a.id)
        if s is not None:
            st = s.state(a, now)
            submissions.append({"id": s.id, "assignment_id": a.id, "score": st["score"],
                                "excused": bool(st["excused"]), "posted": st["posted"],
                                "workflow_state": st["workflow_state"]})
    return {
        "apply_assignment_group_weights": c.apply_weights,
        "groups": [{"id": g.id, "group_weight": g.group_weight, "rules": g.rules} for g in c.groups],
        "assignments": assignments, "submissions": submissions,
        "grading_periods": ({"weighted": c.gp_group.weighted, "periods": periods} if periods else None),
        "enrollment_completed": all(e.workflow_state == "completed" for e in c.enrollments),
    }


def course_scores(c: Course, now: datetime) -> dict:
    return gradecalc.compute_enrollment_scores(calc_input(c, now), now=now)


def letter(c: Course, score):
    if score is None or not c.grading_standard_enabled():
        return None
    return gradecalc.score_to_grade(score, c.scheme_or_default())


# ----------------------------------------------------------------------------
# Profile  (lib/api/v1/user_profile.rb#user_profile_json)
# ----------------------------------------------------------------------------

def profile_json(p: Persona) -> dict:
    u = p.user
    return {
        "id": u.id, "name": u.name, "short_name": u.short_name, "sortable_name": u.sortable_name,
        "avatar_url": avatar_fallback(p.host),
        "title": None, "bio": None, "pronunciation": None,
        "primary_email": u.email, "login_id": u.login_id, "integration_id": None,
        "time_zone": u.time_zone, "locale": u.locale, "effective_locale": u.locale or "en",
        "calendar": {"ics": f"https://{p.host}/feeds/calendars/user_{u.feed_uuid}.ics"},
        "lti_user_id": u.lti_user_id, "k5_user": False, "use_classic_font_in_k5": False,
    }


# ----------------------------------------------------------------------------
# Courses  (lib/api/v1/course.rb#course_json + lib/api/v1/course_json.rb)
# ----------------------------------------------------------------------------

def user_display_json(t: Teacher, host: str, course_id: int | None = None) -> dict:
    url = f"https://{host}/courses/{course_id}/users/{t.id}" if course_id else f"https://{host}/users/{t.id}"
    return {"id": t.id, "anonymous_id": _b36(t.id), "display_name": t.short_name,
            "avatar_image_url": avatar_fallback(host), "html_url": url, "pronouns": t.pronouns}


def term_json(c: Course) -> dict:
    t = c.term
    return {"id": t.id, "name": t.name, "start_at": iso_z(t.start_at), "end_at": iso_z(t.end_at),
            "created_at": iso_z(t.created_at), "workflow_state": "active",
            "grading_period_group_id": t.grading_period_group_id}


def enrollment_hashes(c: Course, p: Persona, now: datetime, scores: dict | None = None) -> list[dict]:
    scores = scores or course_scores(c, now)
    periods = periods_of(c)
    cur = gradecalc.current_grading_period(periods, now) if periods else None
    out = []
    for e in c.enrollments:
        h = {"type": "student", "role": "StudentEnrollment", "role_id": p.role_id_student,
             "user_id": p.user.id, "enrollment_state": e.workflow_state,
             "limit_privileges_to_course_section": False}
        # grading_period_info (merged before total_scores)
        h["current_grading_period_id"] = cur["id"] if cur else None
        h["current_grading_period_title"] = cur["title"] if cur else None
        h["has_grading_periods"] = bool(periods)
        h["multiple_grading_periods_enabled"] = bool(periods)
        if not c.hide_final_grades:
            h["computed_current_grade"] = letter(c, scores["current_score"])
            h["computed_current_score"] = scores["current_score"]
            h["computed_current_letter_grade"] = letter(c, scores["current_score"])
            h["computed_final_grade"] = letter(c, scores["final_score"])
            h["computed_final_score"] = scores["final_score"]
            gp_scores = scores["grading_periods"].get(str(cur["id"])) if cur else None
            h["totals_for_all_grading_periods_option"] = bool(c.gp_group and c.gp_group.display_totals)
            h["current_period_computed_current_score"] = gp_scores["current_score"] if gp_scores else None
            h["current_period_computed_final_score"] = gp_scores["final_score"] if gp_scores else None
            h["current_period_computed_current_grade"] = letter(c, gp_scores["current_score"]) if gp_scores else None
            h["current_period_computed_final_grade"] = letter(c, gp_scores["final_score"]) if gp_scores else None
        out.append(h)
    return out


def course_json(c: Course, p: Persona, now: datetime) -> dict:
    """include[]=total_scores, current_grading_period_scores, term, teachers."""
    h = {
        "id": c.id, "name": c.name, "account_id": c.account_id, "uuid": c.uuid,
        "start_at": iso_z(c.start_at), "grading_standard_id": c.grading_standard_id, "is_public": False,
        "created_at": iso_z(c.created_at), "course_code": c.course_code, "default_view": c.default_view,
        "root_account_id": c.root_account_id, "enrollment_term_id": c.term.id, "license": c.license,
        "grade_passback_setting": None, "end_at": iso_z(c.end_at), "public_syllabus": False,
        "public_syllabus_to_auth": False, "storage_quota_mb": c.storage_quota_mb,
        "is_public_to_auth_users": False, "homeroom_course": False, "course_color": None,
        "friendly_name": None,
    }
    h["term"] = term_json(c)
    h["apply_assignment_group_weights"] = c.apply_weights
    h["teachers"] = [user_display_json(t, p.host) for t in c.teachers]
    h["calendar"] = {"ics": f"https://{p.host}/feeds/calendars/course_{c.uuid}.ics"}
    h["time_zone"] = c.time_zone
    h["blueprint"] = False
    h["template"] = False
    h["enrollments"] = enrollment_hashes(c, p, now)
    h["hide_final_grades"] = c.hide_final_grades
    h["workflow_state"] = c.workflow_state
    if c.course_format:
        h["course_format"] = c.course_format
    h["restrict_enrollments_to_course_dates"] = c.restrict_enrollments_to_course_dates
    h["has_grading_periods"] = bool(c.gp_group and c.gp_group.periods)
    h["multiple_grading_periods_enabled"] = h["has_grading_periods"]
    h["has_weighted_grading_periods"] = bool(c.gp_group and c.gp_group.periods and c.gp_group.weighted)
    return h


def access_restricted_course_json(c: Course) -> dict:
    return {"id": c.id, "access_restricted_by_date": True}


# ----------------------------------------------------------------------------
# Assignment groups (lib/api/v1/assignment_group.rb, assignment.rb, submission.rb)
# ----------------------------------------------------------------------------

def fake_jwt(label: str) -> str:
    def b64(b: bytes) -> str:
        return base64.urlsafe_b64encode(b).decode().rstrip("=")
    header = b64(b'{"typ":"JWT","alg":"HS256"}')
    body = b64(json.dumps({"lti_assignment_id": label, "lti_assignment_description": ""},
                          separators=(",", ":")).encode())
    sig = b64(hashlib.sha256(("synthetic:" + label).encode()).digest())
    return f"{header}.{body}.{sig}"


def _past_due(a: Assignment, due, submitted_at, submission_type, now):
    if due is None:
        return False
    t = submitted_at or now
    if submission_type == "online_quiz" or a.is_quiz():
        t = t - timedelta(seconds=60)
    return t > due


def submission_flags(a: Assignment, s: Submission, st: dict, now: datetime) -> dict:
    """Submission#late?, #missing?, #seconds_late (app/models/submission.rb)."""
    due = a.due_at_as_of(now)
    submitted_at = s.submitted_at if st["submitted"] else None
    lps = s.late_policy_status if st["graded"] or s.late_policy_status == "late" else None
    excused = bool(st["excused"])
    grader_id = s.grader_id if st["graded"] else None
    stype = s.submission_type if st["submitted"] else None
    if excused:
        late = False
    elif lps:
        late = lps == "late"
    else:
        late = submitted_at is not None and _past_due(a, due, submitted_at, stype, now)
    if excused:
        missing = False
    elif grader_id is not None and lps is None:
        missing = False
    elif lps:
        missing = lps == "missing"
    elif submitted_at is not None:
        missing = False
    elif not _past_due(a, due, None, stype, now):
        missing = False
    else:
        missing = a.expects_submission()
    if lps == "late":
        seconds_late = s.seconds_late_override or 0
    else:
        t = submitted_at or now
        if stype == "online_quiz" or a.is_quiz():
            t = t - timedelta(seconds=60)
        seconds_late = 0 if (due is None or t <= due) else int((t - due).total_seconds())
    return {"late": late, "missing": missing, "seconds_late": seconds_late, "lps": lps,
            "grader_id": grader_id, "submitted_at": submitted_at, "stype": stype}


def attachment_json(att, host: str) -> dict:
    return {
        "id": att.id, "folder_id": att.folder_id, "display_name": att.display_name, "filename": att.filename,
        "uuid": att.uuid, "upload_status": "success", "content-type": att.content_type,
        "url": f"https://{host}/files/{att.id}/download?download_frd=1&verifier={att.uuid}",
        "size": att.size, "created_at": iso_z(att.created_at), "updated_at": iso_z(att.created_at),
        "unlock_at": None, "locked": False, "hidden": False, "lock_at": None, "hidden_for_user": False,
        "thumbnail_url": None, "modified_at": iso_z(att.created_at), "mime_class": att.mime_class,
        "media_entry_id": None, "category": "uncategorized", "locked_for_user": False, "preview_url": None,
    }


def submission_json(c: Course, a: Assignment, s: Submission, p: Persona, now: datetime,
                    periods: list, scores_visible: bool = True) -> dict:
    st = s.state(a, now)
    f = submission_flags(a, s, st, now)
    due = a.due_at_as_of(now)
    gp_id = gradecalc.grading_period_for_due_at(due, periods) if periods else None
    version = 1 + (1 if st["submitted"] else 0) + (1 if st["graded"] else 0)
    body = None
    if st["submitted"]:
        body = s.body
    h = {"id": s.id, "body": body, "url": None}
    if st["posted"] or not st["graded"]:
        # Submission#filter_attributes_for_user deletes grade/score (and
        # entered_*) when the student cannot read the grade (unposted).
        h["grade"] = st["grade"]
        h["score"] = st["score"]
    h.update({
        "submitted_at": iso_z(f["submitted_at"]), "assignment_id": a.id, "user_id": p.user.id,
        "submission_type": f["stype"], "workflow_state": st["workflow_state"],
        "grade_matches_current_submission": True, "graded_at": iso_z(s.graded_at) if st["graded"] else None,
        "grader_id": f["grader_id"],
        "attempt": (1 if st["submitted"] else None), "cached_due_date": iso_z(due),
        "excused": st["excused"], "late_policy_status": f["lps"],
        "points_deducted": st["points_deducted"], "grading_period_id": gp_id, "extra_attempts": None,
        "posted_at": iso_z(s.posted_at) if st["posted"] else None, "redo_request": False,
        "custom_grade_status_id": None, "sticker": None,
        "late": f["late"], "missing": f["missing"], "seconds_late": f["seconds_late"],
    })
    if st["posted"] or not st["graded"]:
        h["entered_grade"] = st["entered_grade"]
        h["entered_score"] = st["entered_score"]
    h["preview_url"] = (f"https://{p.host}/courses/{c.id}/assignments/{a.id}/submissions/"
                        f"{p.user.id}?preview=1&version={version}")
    if st["submitted"] and s.attachments:
        h["attachments"] = [attachment_json(att, p.host) for att in s.attachments]
    return h


def lock_state(a: Assignment, now: datetime, tzname: str):
    if a.unlock_at and a.unlock_at > now:
        info = {"asset_string": f"assignment_{a.id}", "unlock_at": iso_z(a.unlock_at)}
        local = utc_to_local(tzname, a.unlock_at)
        hour = local.hour % 12 or 12
        ampm = "am" if local.hour < 12 else "pm"
        t = f"{hour}{ampm}" if local.minute == 0 else f"{hour}:{local.minute:02d}{ampm}"
        expl = f"This assignment is locked until {local.strftime('%b')} {local.day} at {t}."
        return True, info, expl
    if a.lock_at and a.lock_at < now:
        info = {"asset_string": f"assignment_{a.id}", "lock_at": iso_z(a.lock_at), "can_view": True}
        local = utc_to_local(tzname, a.lock_at)
        return True, info, f"This assignment was locked {local.strftime('%b')} {local.day} at {local.strftime('%-I:%M%p').lower()}."
    return False, None, None


def availability(a: Assignment, now: datetime):
    if a.unlock_at and a.unlock_at > now:
        return {"status": "pending", "date": iso_z(a.unlock_at)}
    if a.lock_at and a.lock_at < now:
        return {"status": "closed", "date": None}
    if a.lock_at:
        return {"status": "open", "date": iso_z(a.lock_at)}
    return None


def assignment_json(c: Course, a: Assignment, p: Persona, now: datetime, periods: list) -> dict:
    s = c.submissions.get(a.id)
    due = a.due_at_as_of(now)
    locked, lock_info, lock_expl = lock_state(a, now, c.time_zone)
    subs_exist = any(sub.submitted_at is not None and sub.submitted_at <= now
                     for sub in [s] if sub is not None)
    graded_exist = s is not None and s.graded_at is not None and s.graded_at <= now
    unposted = (s is not None and s.graded_at is not None and s.graded_at <= now
                and (s.posted_at is None or s.posted_at > now))
    h = {
        "id": a.id, "description": None if (locked and not lock_info.get("can_view")) else a.description,
        "due_at": iso_z(due),
        "unlock_at": iso_z(a.unlock_at), "lock_at": iso_z(a.lock_at),
        "points_possible": a.points_possible, "grading_type": a.grading_type,
        "assignment_group_id": a.group_id, "grading_standard_id": a.grading_standard_id,
        "created_at": iso_z(a.created_at), "updated_at": iso_z(a.updated_at_as_of(now)),
        "peer_reviews": False, "automatic_peer_reviews": False, "position": a.position,
        "grade_group_students_individually": False, "anonymous_peer_reviews": False,
        "group_category_id": None, "post_to_sis": False, "moderated_grading": False,
        "omit_from_final_grade": a.omit_from_final_grade, "intra_group_peer_reviews": False,
        "anonymous_instructor_annotations": False, "anonymous_grading": False,
        "graders_anonymous_to_graders": False, "grader_count": 0,
        "grader_comments_visible_to_graders": True, "final_grader_id": None,
        "grader_names_visible_to_final_grader": True,
        "allowed_attempts": a.allowed_attempts if a.allowed_attempts is not None else -1,
        "annotatable_attachment_id": None, "hide_in_gradebook": a.hide_in_gradebook,
        "suppress_assignment": False, "secure_params": a.secure_params, "lti_context_id": a.lti_context_id,
        "course_id": c.id, "name": a.name, "submission_types": list(a.submission_types),
        "has_submitted_submissions": subs_exist, "due_date_required": False, "max_name_length": 255,
    }
    avail = availability(a, now)
    if avail:
        h["availability_status"] = avail
    h["graded_submissions_exist"] = graded_exist
    h["is_quiz_assignment"] = a.is_quiz()
    h["can_duplicate"] = not a.is_quiz()
    h["original_course_id"] = None
    h["original_assignment_id"] = None
    h["original_lti_resource_link_id"] = None
    h["original_assignment_name"] = None
    h["original_quiz_id"] = None
    h["workflow_state"] = "published"
    h["important_dates"] = False
    h["muted"] = bool(a.post_manually and unposted)
    h["html_url"] = f"https://{p.host}/courses/{c.id}/assignments/{a.id}"
    if a.quiz_id:
        h["quiz_id"] = a.quiz_id
        h["anonymous_submissions"] = False
    if a.allowed_extensions:
        h["allowed_extensions"] = list(a.allowed_extensions)
    h["published"] = True
    h["only_visible_to_overrides"] = False
    h["visible_to_everyone"] = True
    if s is not None:
        h["submission"] = submission_json(c, a, s, p, now, periods)
    h["locked_for_user"] = locked
    if locked:
        h["lock_info"] = lock_info
        h["lock_explanation"] = lock_expl
    h["submissions_download_url"] = f"https://{p.host}/courses/{c.id}/assignments/{a.id}/submissions?zip=1"
    h["post_manually"] = a.post_manually
    h["anonymize_students"] = False
    h["new_quizzes_anonymous_participants"] = False
    h["require_lockdown_browser"] = False
    h["restrict_quantitative_data"] = False
    in_closed = False
    if periods:
        gp_id = gradecalc.grading_period_for_due_at(due, periods)
        gp = next((x for x in periods if x["id"] == gp_id), None)
        in_closed = bool(gp and now >= gp["close_date"])
    h["in_closed_grading_period"] = in_closed
    return h


def assignment_groups_json(c: Course, p: Persona, now: datetime) -> list[dict]:
    periods = periods_of(c)
    out = []
    for g in sorted(c.groups, key=lambda g: (g.position, g.id)):
        rules = {}
        if g.rules.get("drop_lowest"):
            rules["drop_lowest"] = g.rules["drop_lowest"]
        if g.rules.get("drop_highest"):
            rules["drop_highest"] = g.rules["drop_highest"]
        if g.rules.get("never_drop"):
            rules["never_drop"] = [str(i) for i in g.rules["never_drop"]]  # rules_hash(stringify_json_ids: true)
        h = {"id": g.id, "name": g.name, "position": g.position, "group_weight": float(g.group_weight),
             "sis_source_id": None, "integration_data": {}, "rules": rules}
        assigns = sorted([a for a in visible_assignments(c, now) if a.group_id == g.id],
                         key=lambda a: (a.position, a.id))
        h["assignments"] = [assignment_json(c, a, p, now, periods) for a in assigns]
        h["any_assignment_in_closed_grading_period"] = any(x["in_closed_grading_period"] for x in h["assignments"])
        out.append(h)
    return out


# ----------------------------------------------------------------------------
# Grading periods (app/controllers/grading_periods_controller.rb#index,
# app/serializers/grading_period_serializer.rb)
# ----------------------------------------------------------------------------

def grading_periods_json(c: Course, p: Persona, now: datetime, base_url: str) -> dict:
    periods = sorted(c.gp_group.periods, key=lambda x: x.start_date) if c.gp_group else []
    gps = []
    for gp in periods:
        gps.append({
            "id": gp.id, "grading_period_group_id": gp.group_id, "start_date": iso_z(gp.start_date),
            "end_date": iso_z(gp.end_date), "close_date": iso_z(gp.close_date),
            "weight": gp.weight, "title": gp.title,
            "permissions": {"read": True, "create": False, "update": False, "delete": False},
            "is_closed": now > gp.close_date,
        })
    link = f"{base_url}?page=1&per_page=10"
    meta = {"pagination": {"per_page": 10, "last": link, "current": link, "first": link,
                           "page": 1, "template": f"{base_url}?page={{page}}&per_page=10",
                           "count": len(gps), "page_count": 1},
            "primaryCollection": "grading_periods"}
    return {"grading_periods": gps, "meta": meta, "can_create_grading_periods": False,
            "grading_periods_read_only": True}


# ----------------------------------------------------------------------------
# Calendar events (lib/api/v1/calendar_event.rb#calendar_event_json)
# ----------------------------------------------------------------------------

def event_json(e: Event, c: Course, p: Persona) -> dict:
    h = {
        "id": e.id, "title": e.title, "start_at": iso_z(e.start_at), "end_at": iso_z(e.end_at),
        "workflow_state": "active", "created_at": iso_z(e.created_at), "updated_at": iso_z(e.created_at),
        "all_day": e.all_day, "all_day_date": e.all_day_date, "comments": None,
        "series_uuid": e.series_uuid, "rrule": e.rrule, "blackout_date": False,
        "location_address": e.location_address, "location_name": e.location_name,
        "type": "event", "description": e.description or "", "child_events_count": 0,
        "all_context_codes": f"course_{c.id}", "context_code": f"course_{c.id}",
        "context_name": c.name, "context_color": None, "parent_event_id": None, "hidden": False,
        "child_events": [], "url": f"https://{p.host}/api/v1/calendar_events/{e.id}",
        "html_url": f"https://{p.host}/calendar?event_id={e.id}&include_contexts=course_{c.id}",
        "duplicates": [], "important_dates": e.important_dates,
    }
    if e.series_uuid and e.rrule:
        h["series_head"] = bool(e.series_head)
    return h


# ----------------------------------------------------------------------------
# Announcements (app/controllers/announcements_api_controller.rb#index ->
# lib/api/v1/discussion_topics.rb#discussion_topic_api_json)
# ----------------------------------------------------------------------------

def announcement_json(an: Announcement, c: Course, p: Persona, now: datetime) -> dict:
    read = an.read_at is not None and an.read_at <= now
    html = f"https://{p.host}/courses/{c.id}/discussion_topics/{an.id}"
    return {
        "id": an.id, "title": an.title, "last_reply_at": iso_z(an.posted_at),
        "created_at": iso_z(an.posted_at), "delayed_post_at": None, "posted_at": iso_z(an.posted_at),
        "assignment_id": None, "root_topic_id": None, "position": None,
        "podcast_has_student_posts": False, "discussion_type": "side_comment", "lock_at": None,
        "allow_rating": False, "only_graders_can_rate": False, "sort_by_rating": False,
        "is_section_specific": False, "anonymous_state": None, "summary_enabled": False,
        "user_name": an.author.name, "discussion_subentry_count": an.replies,
        "permissions": {"attach": False, "update": False, "reply": not an.comments_disabled,
                        "delete": False, "manage_assign_to": False},
        "require_initial_post": None, "user_can_see_posts": True, "podcast_url": None,
        "read_state": "read" if read else "unread", "unread_count": 0, "subscribed": False,
        "attachments": [], "published": True, "can_unpublish": False, "locked": an.comments_disabled,
        "can_lock": False, "comments_disabled": an.comments_disabled,
        "author": user_display_json(an.author, p.host, c.id), "html_url": html, "url": html,
        "pinned": False, "group_category_id": None, "can_group": True, "topic_children": [],
        "group_topic_children": [], "context_code": f"course_{c.id}", "ungraded_discussion_overrides": [],
        "locked_for_user": False, "message": an.message, "subscription_hold": "topic_is_announcement",
        "todo_date": None, "is_announcement": True, "sort_order": "desc", "sort_order_locked": False,
        "expanded": False, "expanded_locked": False,
    }


# ----------------------------------------------------------------------------
# Planner items (lib/api/v1/planner_item.rb#planner_item_json)
# ----------------------------------------------------------------------------

def planner_override_json(o, uid: int) -> dict | None:
    if o is None:
        return None
    types = {"Assignment": "assignment", "Quizzes::Quiz": "quiz", "CalendarEvent": "calendar_event",
             "Announcement": "announcement", "DiscussionTopic": "discussion_topic", "PlannerNote": "planner_note"}
    return {"id": o.id, "plannable_type": types[o.plannable_type], "plannable_id": o.plannable_id,
            "user_id": uid, "workflow_state": "active", "marked_complete": o.marked_complete,
            "deleted_at": None, "created_at": iso_z(o.created_at), "updated_at": iso_z(o.created_at),
            "dismissed": o.dismissed, "assignment_id": None}


def _override_for(p: Persona, cls: str, pid: int, now: datetime):
    for o in p.planner_overrides:
        if o.plannable_type == cls and o.plannable_id == pid and o.created_at <= now:
            return o
    return None


def planner_items(p: Persona, now: datetime, start: datetime, end: datetime) -> list[tuple]:
    """Returns [(sort_key, item_dict)]. Window: start <= plannable_date <= end."""
    items = []
    uid = p.user.id
    for c in p.courses:
        if c.workflow_state != "available" or all(e.workflow_state != "active" for e in c.enrollments):
            continue
        ctx = {"context_type": "Course", "course_id": c.id}
        for a in visible_assignments(c, now):
            due = a.due_at_as_of(now)
            if due is None or not (start <= due <= end):
                continue
            s = c.submissions.get(a.id)
            st = s.state(a, now) if s else None
            f = submission_flags(a, s, st, now) if s else None
            subs = {
                "submitted": bool(st and st["submitted"]),
                "excused": bool(st and st["excused"]),
                "graded": bool(st and (st["excused"] or (st["score"] is not None and st["workflow_state"] == "graded"))),
                "posted_at": iso_z(s.posted_at) if (st and st["posted"]) else None,
                "late": bool(f and f["late"]), "missing": bool(f and f["missing"]),
                "needs_grading": bool(st and st["workflow_state"] in ("submitted", "pending_review")),
                "has_feedback": bool(st and st["posted"] and s.teacher_comment),
                "redo_request": False,
            }
            if subs["has_feedback"]:
                subs["feedback"] = {"comment": s.teacher_comment, "is_media": False,
                                    "author_name": s.comment_author.name,
                                    "author_avatar_url": avatar_fallback(p.host)}
            new_activity = bool(st and st["unread"])
            if a.is_quiz() and a.quiz_id:
                ov = _override_for(p, "Quizzes::Quiz", a.quiz_id, now) or _override_for(p, "Assignment", a.id, now)
                h = dict(ctx)
                h.update({"plannable_id": a.quiz_id, "planner_override": planner_override_json(ov, uid),
                          "plannable_type": "quiz", "new_activity": new_activity, "submissions": subs,
                          "plannable_date": iso_z(due),
                          "plannable": {"id": a.quiz_id, "title": a.name, "created_at": iso_z(a.created_at),
                                        "updated_at": iso_z(a.updated_at_as_of(now)), "assignment_id": a.id,
                                        "points_possible": a.points_possible, "due_at": iso_z(due)},
                          "html_url": f"/courses/{c.id}/quizzes/{a.quiz_id}"})
            else:
                ov = _override_for(p, "Assignment", a.id, now)
                url = (f"/courses/{c.id}/assignments/{a.id}/submissions/{uid}"
                       if (subs["submitted"] or subs["graded"] or subs["has_feedback"])
                       else f"/courses/{c.id}/assignments/{a.id}")
                h = dict(ctx)
                h.update({"plannable_id": a.id, "planner_override": planner_override_json(ov, uid),
                          "plannable_type": "assignment", "new_activity": new_activity, "submissions": subs,
                          "plannable_date": iso_z(due),
                          "plannable": {"id": a.id, "title": a.name, "created_at": iso_z(a.created_at),
                                        "updated_at": iso_z(a.updated_at_as_of(now)),
                                        "points_possible": a.points_possible, "due_at": iso_z(due)},
                          "html_url": url})
            h["context_name"] = c.name
            h["context_image"] = None
            items.append(((due, 0, h["plannable_id"]), h))
        for e in c.events:
            if e.created_at > now or not (start <= e.start_at <= end):
                continue
            ov = _override_for(p, "CalendarEvent", e.id, now)
            plannable = {"id": e.id, "title": e.title, "location_name": e.location_name,
                         "created_at": iso_z(e.created_at), "updated_at": iso_z(e.created_at),
                         "all_day": e.all_day, "location_address": e.location_address,
                         "description": e.description or "", "start_at": iso_z(e.start_at),
                         "end_at": iso_z(e.end_at)}
            h = dict(ctx)
            h.update({"plannable_id": e.id, "planner_override": planner_override_json(ov, uid),
                      "plannable_type": "calendar_event", "new_activity": False, "submissions": False,
                      "plannable_date": iso_z(e.start_at), "plannable": plannable,
                      "html_url": f"https://{p.host}/calendar?event_id={e.id}&include_contexts=course_{c.id}",
                      "context_name": c.name, "context_image": None})
            items.append(((e.start_at, 1, e.id), h))
        for an in c.announcements:
            if an.posted_at > now or not (start <= an.posted_at <= end):
                continue
            read = an.read_at is not None and an.read_at <= now
            ov = _override_for(p, "Announcement", an.id, now)
            h = dict(ctx)
            h.update({"plannable_id": an.id, "planner_override": planner_override_json(ov, uid),
                      "plannable_type": "announcement",
                      "new_activity": False if (ov and ov.marked_complete) else (not read),
                      "submissions": False, "plannable_date": iso_z(an.posted_at),
                      "plannable": {"id": an.id, "title": an.title, "unread_count": 0,
                                    "read_state": "read" if read else "unread",
                                    "created_at": iso_z(an.posted_at), "updated_at": iso_z(an.posted_at)},
                      "html_url": f"/courses/{c.id}/discussion_topics/{an.id}",
                      "context_name": c.name, "context_image": None})
            items.append(((an.posted_at, 2, an.id), h))
    for n in p.planner_notes:
        if n.created_at > now or not (start <= n.todo_date <= end):
            continue
        ov = _override_for(p, "PlannerNote", n.id, now)
        h = {}
        if n.course_id:
            h.update({"context_type": "Course", "course_id": n.course_id})
        h.update({"plannable_id": n.id, "planner_override": planner_override_json(ov, uid),
                  "plannable_type": "planner_note", "new_activity": False, "submissions": False,
                  "plannable_date": iso_z(n.todo_date),
                  "plannable": {"id": n.id, "title": n.title, "course_id": n.course_id,
                                "todo_date": iso_z(n.todo_date), "details": n.details,
                                "created_at": iso_z(n.created_at), "updated_at": iso_z(n.created_at),
                                "user_id": uid},
                  "html_url": f"https://{p.host}/api/v1/planner_notes/{n.id}"})
        if n.course_id:
            h["context_name"] = p.course(n.course_id).name
            h["context_image"] = None
        items.append(((n.todo_date, 3, n.id), h))
    items.sort(key=lambda t: t[0])
    return items


def colors_json(p: Persona) -> dict:
    return {"custom_colors": dict(p.custom_colors)}
