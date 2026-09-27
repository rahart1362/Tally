"""JSON Schemas (draft 2020-12), one per Canvas object as a *student* caller
receives it with ``Accept: application/json+canvas-string-ids``.

Schemas are strict (``additionalProperties: false``) so a field the canvas-lms
serializer would not emit fails validation. For an owner-run recording against
real Canvas (WP-B07), a failure means "new or conditional field": review it,
do not blindly relax.
"""
from __future__ import annotations

DOCS = "https://developerdocs.instructure.com/services/canvas/resources"
SRC = "canvas-lms@1c9f0bb8013ed69c4f2efe11fd483025469b7e6c"
BASE_ID = "https://schemas.tally.example/canvas/"
RETRIEVED = "Docs retrieved 2026-09-26; canvas-lms master 1c9f0bb (2026-04-30, latest public commit on 2026-09-26)."

ID = {"type": "string", "pattern": "^-?[0-9]+$"}
TS = {"type": "string", "pattern": r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"}
DATE = {"type": "string", "pattern": r"^\d{4}-\d{2}-\d{2}$"}
URL = {"type": "string", "pattern": "^https://"}
REL = {"type": "string", "pattern": "^(/|https://)"}


def n(s):
    return {"anyOf": [s, {"type": "null"}]}


T = {
    "id": ID, "id?": n(ID), "ts": TS, "ts?": n(TS), "str": {"type": "string"}, "str?": n({"type": "string"}),
    "bool": {"type": "boolean"}, "bool?": n({"type": "boolean"}), "num": {"type": "number"},
    "num?": n({"type": "number"}), "int": {"type": "integer"}, "int?": n({"type": "integer"}), "url": URL,
    "url?": n(URL), "rel": REL, "date?": n(DATE), "obj": {"type": "object"}, "arr": {"type": "array"},
    "null": {"type": "null"},
}


def obj(fields: dict, optional=(), title=None, comment=None, extra=None):
    props = {}
    for k, v in fields.items():
        props[k] = T[v] if isinstance(v, str) else v
    s = {"type": "object", "properties": props, "required": [k for k in fields if k not in optional],
         "additionalProperties": False}
    if title:
        s["title"] = title
    if comment:
        s["$comment"] = comment
    if extra:
        s.update(extra)
    return s


def ref(name):
    return {"$ref": f"{name}.schema.json"}


def arr(name):
    return {"type": "array", "items": ref(name)}


def schema(name, body, comment):
    out = {"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": BASE_ID + f"{name}.schema.json",
           "title": name, "$comment": comment + " " + RETRIEVED}
    out.update(body)
    return out


def all_schemas() -> dict:
    S = {}
    S["UserDisplay"] = schema("UserDisplay", obj({
        "id": "id", "anonymous_id": "str", "display_name": "str", "avatar_image_url": "url", "html_url": "url",
        "pronouns": "str?"}), f"{DOCS}/users#userdisplay ; {SRC} lib/api/v1/user.rb#user_display_json. Used for "
        "course teachers and announcement authors.")
    S["Term"] = schema("Term", obj({
        "id": "id", "name": "str", "start_at": "ts?", "end_at": "ts?", "created_at": "ts", "workflow_state": "str",
        "grading_period_group_id": "id?"}), f"{DOCS}/courses#term and {DOCS}/enrollment_terms#enrollmentterm ; "
        f"{SRC} lib/api/v1/enrollment_term.rb#enrollment_term_json (only: id name start_at end_at workflow_state "
        "grading_period_group_id created_at). Field order UNVERIFIED (Rails only-filter follows column order).")
    enr_fields = {
        "type": {"enum": ["student", "observer"]}, "role": {"enum": ["StudentEnrollment", "ObserverEnrollment"]},
        "role_id": "id", "user_id": "id", "enrollment_state": {"enum": ["active", "invited", "completed", "inactive"]},
        "limit_privileges_to_course_section": "bool", "associated_user_id": "id",
        "current_grading_period_id": "id?", "current_grading_period_title": "str?", "has_grading_periods": "bool",
        "multiple_grading_periods_enabled": "bool", "computed_current_grade": "str?",
        "computed_current_score": "num?", "computed_current_letter_grade": "str?", "computed_final_grade": "str?",
        "computed_final_score": "num?", "totals_for_all_grading_periods_option": "bool",
        "current_period_computed_current_score": "num?", "current_period_computed_final_score": "num?",
        "current_period_computed_current_grade": "str?", "current_period_computed_final_grade": "str?"}
    S["CourseEnrollment"] = schema("CourseEnrollment", obj(
        enr_fields, optional=[k for k in enr_fields if k not in (
            "type", "role", "role_id", "user_id", "enrollment_state", "limit_privileges_to_course_section")],
        extra={"allOf": [
            {"if": {"properties": {"type": {"const": "observer"}}},
             "then": {"required": ["associated_user_id"],
                      "not": {"required": ["computed_current_score"]}}},
            {"if": {"properties": {"type": {"const": "student"}}},
             "then": {"required": ["current_grading_period_id", "has_grading_periods"]}}]}),
        f"{DOCS}/enrollments#enrollment (the course-embedded form is documented only in the Course object's "
        f"'enrollments' note) ; {SRC} lib/api/v1/course_json.rb#enrollment_hash, #grading_period_info, "
        "#total_scores (student caller => effective_* scores and computed_current_letter_grade), "
        "#current_grading_period_scores. computed_* keys are ABSENT when the course hides final grades "
        "(include_total_scores? is false) -- never 0. Observer rows (include[]=observed_users) carry "
        "associated_user_id and no scores; the observed student's rows follow them.")
    S["Course"] = schema("Course", {"anyOf": [obj({
        "id": "id", "name": "str", "account_id": "id", "uuid": "str", "start_at": "ts?",
        "grading_standard_id": "id?", "is_public": "bool", "created_at": "ts", "course_code": "str",
        "default_view": "str", "root_account_id": "id", "enrollment_term_id": "id", "license": "str?",
        "grade_passback_setting": "str?", "end_at": "ts?", "public_syllabus": "bool",
        "public_syllabus_to_auth": "bool", "storage_quota_mb": "int", "is_public_to_auth_users": "bool",
        "homeroom_course": "bool", "course_color": "str?", "friendly_name": "str?", "term": ref("Term"),
        "apply_assignment_group_weights": "bool", "teachers": arr("UserDisplay"),
        "calendar": obj({"ics": URL}), "time_zone": "str", "blueprint": "bool", "template": "bool",
        "enrollments": arr("CourseEnrollment"), "hide_final_grades": "bool",
        "workflow_state": {"enum": ["unpublished", "available", "completed", "deleted"]},
        "course_format": "str", "restrict_enrollments_to_course_dates": "bool", "has_grading_periods": "bool",
        "multiple_grading_periods_enabled": "bool", "has_weighted_grading_periods": "bool",
        "original_name": "str"}, optional=["course_format", "original_name"]),
        obj({"id": "id", "access_restricted_by_date": {"const": True}}, title="CourseAccessRestricted")]},
        f"{DOCS}/courses#course ; {SRC} lib/api/v1/course.rb#course_json and lib/api/v1/course_json.rb "
        "(BASE_ATTRIBUTES + methods_to_send; to_hash adds enrollments/hide_final_grades/workflow_state/"
        "restrict_enrollments_to_course_dates; include[]=current_grading_period_scores adds has_grading_periods/"
        "multiple_grading_periods_enabled/has_weighted_grading_periods). Request: GET /api/v1/courses?"
        "enrollment_state=active&include[]=total_scores&include[]=current_grading_period_scores&include[]=term&"
        "include[]=teachers&per_page=100. courses_controller.rb#courses_for_user always adds "
        "access_restricted_by_date, producing the minimal {id, access_restricted_by_date} form.")
    S["Attachment"] = schema("Attachment", obj({
        "id": "id", "folder_id": "id?", "display_name": "str", "filename": "str", "uuid": "str",
        "upload_status": "str", "content-type": "str", "url": "url", "size": "int", "created_at": "ts",
        "updated_at": "ts", "unlock_at": "ts?", "locked": "bool", "hidden": "bool", "lock_at": "ts?",
        "hidden_for_user": "bool", "thumbnail_url": "url?", "modified_at": "ts", "mime_class": "str",
        "media_entry_id": "str?", "category": "str", "locked_for_user": "bool", "preview_url": "str?"}),
        f"{DOCS}/files#file ; {SRC} lib/api/v1/attachment.rb#attachment_json (submission attachments, "
        "skip_permission_checks). preview_url null assumes no Canvadocs preview (UNVERIFIED per institution).")
    S["Submission"] = schema("Submission", obj({
        "id": "id", "body": "str?", "url": "str?", "grade": "str?", "score": "num?", "submitted_at": "ts?",
        "assignment_id": "id", "user_id": "id", "submission_type": "str?",
        "workflow_state": {"enum": ["unsubmitted", "submitted", "graded", "pending_review"]},
        "grade_matches_current_submission": "bool", "graded_at": "ts?", "grader_id": "id?", "attempt": "int?",
        "cached_due_date": "ts?", "excused": "bool?", "late_policy_status": n({"enum": ["late", "missing", "extended", "none"]}),
        "points_deducted": "num?", "grading_period_id": "id?", "extra_attempts": "int?", "posted_at": "ts?",
        "redo_request": "bool", "custom_grade_status_id": "id?", "sticker": "str?", "late": "bool",
        "missing": "bool", "seconds_late": "int", "entered_grade": "str?", "entered_score": "num?",
        "preview_url": "url", "attachments": arr("Attachment")},
        optional=["grade", "score", "entered_grade", "entered_score", "attachments"]),
        f"{DOCS}/submissions#submission ; {SRC} lib/api/v1/submission.rb (SUBMISSION_JSON_FIELDS + "
        "SUBMISSION_JSON_METHODS, preview_url, attachments) and app/models/submission.rb "
        "(#filter_attributes_for_user deletes grade/score/entered_grade/entered_score when "
        "hide_grade_from_student? -- unposted -- so those keys are optional; #late?, #missing?, #seconds_late). "
        "excused null on never-graded rows and negative grader_id for auto-graded classic quizzes are UNVERIFIED "
        "(recalled from real responses, not proven from source).")
    S["Assignment"] = schema("Assignment", obj({
        "id": "id", "description": "str?", "due_at": "ts?", "unlock_at": "ts?", "lock_at": "ts?",
        "points_possible": "num?", "grading_type": {"enum": ["points", "percent", "letter_grade", "gpa_scale",
                                                             "pass_fail", "not_graded"]},
        "assignment_group_id": "id", "grading_standard_id": "id?", "created_at": "ts", "updated_at": "ts",
        "peer_reviews": "bool", "automatic_peer_reviews": "bool", "position": "int",
        "grade_group_students_individually": "bool", "anonymous_peer_reviews": "bool", "group_category_id": "id?",
        "post_to_sis": "bool", "moderated_grading": "bool", "omit_from_final_grade": "bool",
        "intra_group_peer_reviews": "bool", "anonymous_instructor_annotations": "bool", "anonymous_grading": "bool",
        "graders_anonymous_to_graders": "bool", "grader_count": "int", "grader_comments_visible_to_graders": "bool",
        "final_grader_id": "id?", "grader_names_visible_to_final_grader": "bool", "allowed_attempts": "int",
        "annotatable_attachment_id": "id?", "hide_in_gradebook": "bool", "suppress_assignment": "bool",
        "secure_params": "str", "lti_context_id": "str", "course_id": "id", "name": "str",
        "submission_types": {"type": "array", "items": {"type": "string"}}, "has_submitted_submissions": "bool",
        "due_date_required": "bool", "max_name_length": "int",
        "availability_status": obj({"status": {"enum": ["pending", "open", "closed"]}, "date": "ts?"}),
        "graded_submissions_exist": "bool", "is_quiz_assignment": "bool", "can_duplicate": "bool",
        "original_course_id": "id?", "original_assignment_id": "id?", "original_lti_resource_link_id": "str?",
        "original_assignment_name": "str?", "original_quiz_id": "id?", "workflow_state": "str",
        "important_dates": "bool", "muted": "bool", "html_url": "url", "quiz_id": "id",
        "anonymous_submissions": "bool", "allowed_extensions": {"type": "array", "items": {"type": "string"}},
        "published": "bool", "only_visible_to_overrides": "bool", "visible_to_everyone": "bool",
        "submission": {"anyOf": [ref("Submission"), arr("Submission")]}, "locked_for_user": "bool",
        "lock_info": obj({"asset_string": "str", "unlock_at": "ts", "lock_at": "ts", "can_view": "bool"},
                         optional=["unlock_at", "lock_at", "can_view"]),
        "lock_explanation": "str", "submissions_download_url": "url", "post_manually": "bool",
        "anonymize_students": "bool", "new_quizzes_anonymous_participants": "bool",
        "require_lockdown_browser": "bool", "restrict_quantitative_data": "bool", "in_closed_grading_period": "bool"},
        optional=["availability_status", "quiz_id", "anonymous_submissions", "allowed_extensions", "submission",
                  "lock_info", "lock_explanation"]),
        f"{DOCS}/assignments#assignment ; {SRC} lib/api/v1/assignment.rb#assignment_json "
        "(API_ALLOWED_ASSIGNMENT_OUTPUT_FIELDS, then computed keys; student caller so no needs_grading_count, "
        "sis ids, has_overrides or unpublishable) and lib/api/v1/assignment_group.rb (in_closed_grading_period "
        "appended last). 'submission' is an object for a student and an array with include[]=observed_users "
        "(lib/api/v1/assignment.rb#submissions_hash). Key order of the only-filtered prefix UNVERIFIED.")
    S["AssignmentGroup"] = schema("AssignmentGroup", obj({
        "id": "id", "name": "str", "position": "int", "group_weight": "num", "sis_source_id": "str?",
        "integration_data": "obj",
        "rules": obj({"drop_lowest": "int", "drop_highest": "int",
                      "never_drop": {"type": "array", "items": ID}},
                     optional=["drop_lowest", "drop_highest", "never_drop"]),
        "assignments": arr("Assignment"), "any_assignment_in_closed_grading_period": "bool"}),
        f"{DOCS}/assignment_groups#assignmentgroup and #gradingrules ; {SRC} lib/api/v1/assignment_group.rb"
        "#assignment_group_json and app/models/assignment_group.rb#rules_hash (never_drop ids are strings "
        "under canvas-string-ids). Request: GET /api/v1/courses/:id/assignment_groups?include[]=assignments&"
        "include[]=submission&per_page=100.")
    S["GradingPeriod"] = schema("GradingPeriod", obj({
        "id": "id", "grading_period_group_id": "id", "start_date": "ts", "end_date": "ts", "close_date": "ts",
        "weight": "num?", "title": "str",
        "permissions": obj({"read": "bool", "create": "bool", "update": "bool", "delete": "bool"}),
        "is_closed": "bool"}),
        f"{DOCS}/grading_periods#gradingperiod ; {SRC} app/serializers/grading_period_serializer.rb "
        "(ids always stringified by Canvas::APISerialization). Student permission values UNVERIFIED.")
    S["GradingPeriodIndex"] = schema("GradingPeriodIndex", obj({
        "grading_periods": arr("GradingPeriod"),
        "meta": obj({"pagination": obj({"per_page": "int", "next": "url", "last": "url", "prev": "url",
                                        "current": "url", "first": "url", "page": "int", "template": "str",
                                        "count": "int", "page_count": "int"},
                                       optional=["next", "prev", "last", "count", "page_count"]),
                     "primaryCollection": {"const": "grading_periods"}}),
        "can_create_grading_periods": "bool", "grading_periods_read_only": "bool"}),
        f"{DOCS}/grading_periods#method.grading_periods.index ; {SRC} app/controllers/grading_periods_controller.rb"
        "#index (serialize_json_api + index_permissions + grading_periods_read_only) and lib/api.rb#jsonapi_meta.")
    S["PlannerOverride"] = schema("PlannerOverride", obj({
        "id": "id", "plannable_type": "str", "plannable_id": "id", "user_id": "id", "workflow_state": "str",
        "marked_complete": "bool", "deleted_at": "ts?", "created_at": "ts", "updated_at": "ts", "dismissed": "bool",
        "assignment_id": "id?"}), f"{DOCS}/planner#planneroverride ; {SRC} lib/api/v1/planner_override.rb.")
    S["PlannerItem"] = schema("PlannerItem", obj({
        "context_type": {"enum": ["Course", "Group", "User"]}, "course_id": "id",
        "plannable_id": "id", "planner_override": n(ref("PlannerOverride")),
        "plannable_type": {"enum": ["assignment", "quiz", "discussion_topic", "announcement", "wiki_page",
                                    "planner_note", "calendar_event", "assessment_request", "sub_assignment"]},
        "new_activity": "bool",
        "submissions": {"anyOf": [{"const": False}, obj({
            "submitted": "bool", "excused": "bool", "graded": "bool", "posted_at": "ts?", "late": "bool",
            "missing": "bool", "needs_grading": "bool", "has_feedback": "bool", "redo_request": "bool",
            "feedback": obj({"comment": "str", "is_media": "bool", "author_name": "str",
                             "author_avatar_url": "url?"})}, optional=["feedback"])]},
        "plannable_date": "ts",
        "plannable": obj({"id": "id", "title": "str", "course_id": "id?", "location_name": "str?",
                          "todo_date": "ts?", "details": "str?", "unread_count": "int", "read_state": "str",
                          "created_at": "ts", "updated_at": "ts", "all_day": "bool", "location_address": "str?",
                          "description": "str?", "start_at": "ts", "end_at": "ts", "assignment_id": "id",
                          "points_possible": "num?", "due_at": "ts?", "user_id": "id"},
                         optional=["course_id", "location_name", "todo_date", "details", "unread_count",
                                   "read_state", "all_day", "location_address", "description", "start_at",
                                   "end_at", "assignment_id", "points_possible", "due_at", "user_id"]),
        "html_url": "rel", "context_name": "str", "context_image": "str?"},
        optional=["context_type", "course_id", "context_name", "context_image"]),
        f"{DOCS}/planner#method.planner.index (no object definition is published; example response only) ; "
        f"{SRC} lib/api/v1/planner_item.rb#planner_item_json, #plannable_json (API_PLANNABLE_FIELDS/"
        "CALENDAR_PLANNABLE_FIELDS/GRADABLE_FIELDS slices), #submission_statuses. html_url is a relative path "
        "except for calendar events. The plannable sub-object field sets are derived from the slice lists "
        "(UNVERIFIED against a live response).")
    S["CalendarEvent"] = schema("CalendarEvent", obj({
        "id": "id", "title": "str", "start_at": "ts", "end_at": "ts", "workflow_state": "str", "created_at": "ts",
        "updated_at": "ts", "all_day": "bool", "all_day_date": "date?", "comments": "str?", "series_uuid": "str?",
        "rrule": "str?", "blackout_date": "bool", "location_address": "str?", "location_name": "str?",
        "type": {"const": "event"}, "description": "str", "child_events_count": "int",
        "all_context_codes": "str", "context_code": "str", "context_name": "str?", "context_color": "str?",
        "parent_event_id": "id?", "hidden": "bool", "child_events": "arr", "url": "url", "html_url": "url",
        "duplicates": "arr", "important_dates": "bool", "series_head": "bool"}, optional=["series_head"]),
        f"{DOCS}/calendar_events#calendarevent ; {SRC} lib/api/v1/calendar_event.rb#calendar_event_json. "
        "Request: GET /api/v1/calendar_events?type=event&context_codes[]=...(<=10)&start_date&end_date&"
        "per_page=100 (bookmark pagination).")
    S["Announcement"] = schema("Announcement", obj({
        "id": "id", "title": "str", "last_reply_at": "ts?", "created_at": "ts", "delayed_post_at": "ts?",
        "posted_at": "ts?", "assignment_id": "id?", "root_topic_id": "id?", "position": "int?",
        "podcast_has_student_posts": "bool?", "discussion_type": "str", "lock_at": "ts?", "allow_rating": "bool",
        "only_graders_can_rate": "bool", "sort_by_rating": "bool", "is_section_specific": "bool",
        "anonymous_state": "str?", "summary_enabled": "bool", "user_name": "str?",
        "discussion_subentry_count": "int",
        "permissions": obj({"attach": "bool", "update": "bool", "reply": "bool", "delete": "bool",
                            "manage_assign_to": "bool"}),
        "require_initial_post": "bool?", "user_can_see_posts": "bool", "podcast_url": "str?",
        "read_state": {"enum": ["read", "unread"]}, "unread_count": "int", "subscribed": "bool",
        "attachments": "arr", "published": "bool", "can_unpublish": "bool", "locked": "bool", "can_lock": "bool",
        "comments_disabled": "bool", "author": {"anyOf": [ref("UserDisplay"), {"type": "null"}]},
        "html_url": "url", "url": "url", "pinned": "bool", "group_category_id": "id?", "can_group": "bool",
        "topic_children": "arr", "group_topic_children": "arr", "context_code": "str",
        "ungraded_discussion_overrides": "arr", "locked_for_user": "bool", "message": "str",
        "subscription_hold": "str", "todo_date": "ts?", "is_announcement": {"const": True}, "sort_order": "str",
        "sort_order_locked": "bool", "expanded": "bool", "expanded_locked": "bool"}),
        f"{DOCS}/discussion_topics#discussiontopic and {DOCS}/announcements#method.announcements_api.index ; "
        f"{SRC} lib/api/v1/discussion_topics.rb#discussion_topic_api_json (ALLOWED_TOPIC_FIELDS + methods + "
        "permissions, serialize_additional_topic_fields with include_context_code) and "
        "app/controllers/announcements_api_controller.rb#index (default window start_date + 28 days). "
        "The ungraded_discussion_overrides value shape and permission values are UNVERIFIED.")
    S["Profile"] = schema("Profile", obj({
        "id": "id", "name": "str", "short_name": "str", "sortable_name": "str", "avatar_url": "url", "title": "str?",
        "bio": "str?", "pronunciation": "str?", "primary_email": "str", "login_id": "str", "integration_id": "str?",
        "time_zone": "str", "locale": "str?", "effective_locale": "str", "calendar": obj({"ics": URL}),
        "lti_user_id": "str", "k5_user": "bool", "use_classic_font_in_k5": "bool"}),
        f"{DOCS}/users#profile ; {SRC} lib/api/v1/user_profile.rb#user_profile_json (slice! order, then "
        "title/bio/pronunciation/primary_email/login_id/integration_id/time_zone/locale/effective_locale, "
        "self-only calendar/lti_user_id/k5_user/use_classic_font_in_k5). calendar.ics is the ICS feed URL.")
    S["CustomColors"] = schema("CustomColors", obj({"custom_colors": {
        "type": "object", "propertyNames": {"pattern": "^(course|user|group)_[0-9]+$"},
        "additionalProperties": {"type": "string", "pattern": "^#[0-9A-Fa-f]{6}$"}}}),
        f"{DOCS}/users#method.users.get_custom_colors ; {SRC} app/controllers/users_controller.rb#get_custom_colors.")
    S["Observee"] = schema("Observee", obj({
        "id": "id", "name": "str", "created_at": "ts", "sortable_name": "str", "short_name": "str",
        "pronouns": "str?", "avatar_url": "url", "observation_link_root_account_ids": {"type": "array", "items": ID}},
        optional=["pronouns", "avatar_url"]),
        f"{DOCS}/user_observees#method.user_observees.index (returns User objects, {DOCS}/users#user) ; "
        f"{SRC} app/controllers/user_observees_controller.rb#index + #add_linked_root_account_ids_to_user_json, "
        "lib/api/v1/user.rb#user_json (API_USER_JSON_OPTS). Observer feature: shapes derived from source; "
        "not verified against a live observer account (UNVERIFIED).")
    S["AccountSearchResult"] = schema("AccountSearchResult", obj({
        "id": "id", "name": "str", "domain": "str", "distance": n({"type": "number"}),
        "authentication_provider": "str?"}),
        "GET https://canvas.instructure.com/api/v1/accounts/search?name=... is NOT in the REST docs or the "
        "open-source controllers. Field set, types and Link format observed live (unauthenticated) on "
        "2026-09-26; ids were integers because that probe sent no string-ids Accept header. UNVERIFIED as a "
        "documented contract.")
    S["ErrorBody"] = schema("ErrorBody", obj({
        "status": {"enum": ["unauthenticated", "unauthorized"]},
        "errors": {"type": "array", "minItems": 1, "items": obj(
            {"message": "str", "expired_at": "ts?", "error_code": "str"}, optional=["expired_at", "error_code"])},
        "error_report_id": "id"}, optional=["status", "error_report_id"]),
        f"{SRC} app/controllers/application_controller.rb#api_error_json/#rescue_action_in_api and "
        "lib/authentication_methods.rb#render_json_unauthorized. Rate-limit responses are text/plain "
        "(app/middleware/request_throttle.rb) and use RateLimitText.")
    S["RateLimitText"] = schema("RateLimitText", {"type": "string",
                                                  "pattern": r"^(403 Forbidden|429 Too Many Requests) \(Rate Limit Exceeded\)\n$"},
                                f"{SRC} app/middleware/request_throttle.rb#rate_limit_exceeded (validated as the raw body string).")
    S["HeadersSidecar"] = schema("HeadersSidecar", obj({
        "status": "int", "headers": {"type": "object", "additionalProperties": {"type": "string"},
                                     "properties": {"Link": {"type": "string", "pattern": r'^<https?://[^>]+>; rel="[a-z]+"(,<https?://[^>]+>; rel="[a-z]+")*$'},
                                                    "link": {"type": "string"},
                                                    "X-Request-Cost": {"type": "string", "pattern": r"^[0-9.e-]+$"},
                                                    "X-Rate-Limit-Remaining": {"type": "string", "pattern": r"^-?[0-9.e-]+$"}}}}),
        "Tally fixture sidecar (not a Canvas object). Header names as Canvas sets them (app/middleware/"
        "request_throttle.rb, lib/api.rb#build_links_from_hash); match case-insensitively.")
    return S


# file-kind -> schema used for the body
ENDPOINT_SCHEMA = {
    "profile": ("Profile", False), "courses": ("Course", True), "assignment_groups": ("AssignmentGroup", True),
    "grading_periods": ("GradingPeriodIndex", False), "planner_items": ("PlannerItem", True),
    "calendar_events": ("CalendarEvent", True), "announcements": ("Announcement", True),
    "colors": ("CustomColors", False), "observees": ("Observee", True),
    "accounts_search": ("AccountSearchResult", True),
}
