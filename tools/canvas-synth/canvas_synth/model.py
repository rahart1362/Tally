"""World model. One persona world carries a timeline (created/submitted/graded/
posted/changed timestamps), and every fixture is a *snapshot* of that world at
an observation instant ``now``. The "one day earlier" persona is the same
world observed 24 hours earlier, so the change digest sees real diffs.

All ids are Python ints here; the emitter applies Canvas's StringifyIds.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Any

from .gradecalc import grade_to_score, score_to_grade, DEFAULT_GRADING_SCHEME


@dataclass
class User:
    id: int
    name: str
    short_name: str
    sortable_name: str
    login_id: str
    email: str
    time_zone: str
    lti_user_id: str
    feed_uuid: str
    created_at: datetime
    locale: str | None = None


@dataclass
class Teacher:
    id: int
    name: str
    short_name: str
    pronouns: str | None = None


@dataclass
class Term:
    id: int
    name: str
    start_at: datetime | None
    end_at: datetime | None
    created_at: datetime
    grading_period_group_id: int | None = None


@dataclass
class GradingPeriod:
    id: int
    title: str
    start_date: datetime
    end_date: datetime
    close_date: datetime
    weight: float | None
    group_id: int


@dataclass
class GradingPeriodGroup:
    id: int
    weighted: bool
    display_totals: bool
    periods: list[GradingPeriod] = field(default_factory=list)


@dataclass
class Group:
    id: int
    name: str
    position: int
    group_weight: float
    rules: dict = field(default_factory=dict)  # drop_lowest, drop_highest, never_drop (assignment ids)


@dataclass
class Assignment:
    id: int
    course_id: int
    name: str
    group_id: int
    points_possible: float | None
    due_at: datetime | None
    position: int
    created_at: datetime
    grading_type: str = "points"
    submission_types: tuple = ("online_upload",)
    unlock_at: datetime | None = None
    lock_at: datetime | None = None
    omit_from_final_grade: bool = False
    hide_in_gradebook: bool = False
    quiz_id: int | None = None
    description: str | None = None
    allowed_attempts: int | None = None
    post_manually: bool = False
    grading_standard_id: int | None = None
    scheme: list | None = None               # letter_grade scheme (course default if None)
    allowed_extensions: list | None = None
    lti_context_id: str = ""
    secure_params: str = ""
    due_changes: list = field(default_factory=list)   # [(changed_at, new_due_at)]
    updated_at: datetime | None = None

    def due_at_as_of(self, now: datetime):
        due = self.due_at
        for changed_at, new_due in sorted(self.due_changes, key=lambda x: x[0]):
            if changed_at <= now:
                due = new_due
        return due

    def updated_at_as_of(self, now: datetime):
        ts = [self.updated_at or self.created_at]
        ts += [c for c, _ in self.due_changes if c <= now]
        return max(t for t in ts if t <= now) if any(t <= now for t in ts) else self.created_at

    def is_quiz(self):
        return "online_quiz" in self.submission_types

    def expects_submission(self):
        return not set(self.submission_types) & {"none", "not_graded", "on_paper", "wiki_page", "external_tool"}

    def gradeable(self):
        return not set(self.submission_types) & {"not_graded", "wiki_page"}


@dataclass
class Attachment:
    id: int
    uuid: str
    folder_id: int
    display_name: str
    filename: str
    content_type: str
    size: int
    created_at: datetime
    mime_class: str


@dataclass
class Submission:
    """Timeline of one student's submission for one assignment."""
    id: int
    assignment_id: int
    user_id: int
    submitted_at: datetime | None = None
    submission_type: str | None = None
    graded_at: datetime | None = None
    posted_at: datetime | None = None          # None = never posted (manual post policy)
    entered_score: float | None = None          # before late deduction
    points_deducted: float | None = None
    letter: str | None = None                  # letter_grade / pass_fail entered grade
    excused: bool = False
    grader_id: int | None = None
    late_policy_status: str | None = None
    seconds_late_override: int | None = None
    body: str | None = None
    attachments: list = field(default_factory=list)
    teacher_comment: str | None = None
    comment_author: Teacher | None = None
    viewed_at: datetime | None = None           # when the student last saw the grade
    pending_review: bool = False

    def state(self, a: Assignment, now: datetime) -> dict:
        submitted = self.submitted_at is not None and self.submitted_at <= now
        graded = self.graded_at is not None and self.graded_at <= now
        posted = graded and self.posted_at is not None and self.posted_at <= now
        excused = self.excused and graded
        score = None
        grade = None
        entered_score = None
        entered_grade = None
        if graded and not excused and self.entered_score is not None and not self.pending_review:
            entered_score = float(self.entered_score)
            score = round(entered_score - (self.points_deducted or 0.0), 2)
            grade = grade_string(a, score, self.letter)
            entered_grade = grade if score == entered_score else grade_string(a, entered_score, self.letter)
        if self.pending_review and submitted:
            wf = "pending_review"
        elif graded and (score is not None or excused):
            wf = "graded"
        elif submitted:
            wf = "submitted"
        else:
            wf = "unsubmitted"
        return {
            "submitted": submitted, "graded": graded, "posted": posted, "excused": excused if graded else None,
            "score": score, "grade": grade, "entered_score": entered_score, "entered_grade": entered_grade,
            "workflow_state": wf,
            "points_deducted": (self.points_deducted if graded else None),
            "unread": bool(posted and (self.viewed_at is None or self.viewed_at > now)
                           and self.posted_at is not None and self.posted_at <= now),
        }


def _round_if_whole(x: float) -> str:
    return str(int(x)) if float(x).is_integer() else repr(float(x))


def grade_string(a: Assignment, score: float, letter: str | None) -> str | None:
    if score is None:
        return None
    gt = a.grading_type
    if gt == "points":
        return _round_if_whole(score)
    if gt == "percent":
        pct = round(score / a.points_possible * 100, 2) if a.points_possible else 0.0
        return _round_if_whole(pct) + "%"
    if gt == "pass_fail":
        return "complete" if (score > 0 or not a.points_possible) else "incomplete"
    if gt == "letter_grade":
        if letter:
            return letter
        pct = score / a.points_possible * 100 if a.points_possible else 0.0
        return score_to_grade(pct, a.scheme or DEFAULT_GRADING_SCHEME)
    return _round_if_whole(score)


def letter_score(a: Assignment, letter: str) -> float:
    pct = grade_to_score(letter, a.scheme or DEFAULT_GRADING_SCHEME)
    return round(a.points_possible * pct / 100.0, 2)


@dataclass
class Event:
    id: int
    course_id: int
    title: str
    start_at: datetime
    end_at: datetime
    created_at: datetime
    location_name: str | None = None
    location_address: str | None = None
    description: str | None = None
    all_day: bool = False
    all_day_date: str | None = None
    series_uuid: str | None = None
    rrule: str | None = None
    series_head: bool | None = None
    important_dates: bool = False


@dataclass
class Announcement:
    id: int
    course_id: int
    title: str
    message: str
    posted_at: datetime
    author: Teacher
    read_at: datetime | None = None
    comments_disabled: bool = True
    replies: int = 0


@dataclass
class Enrollment:
    id: int
    section_id: int
    workflow_state: str = "active"


@dataclass
class Course:
    id: int
    name: str
    course_code: str
    uuid: str
    term: Term
    created_at: datetime
    account_id: int
    root_account_id: int
    time_zone: str
    teachers: list[Teacher]
    enrollments: list[Enrollment]
    default_view: str = "modules"
    license: str = "private"
    apply_weights: bool = False
    grading_standard_id: int | None = None
    scheme: list | None = None
    hide_final_grades: bool = False
    course_format: str | None = None
    start_at: datetime | None = None
    end_at: datetime | None = None
    workflow_state: str = "available"
    storage_quota_mb: int = 500
    restrict_enrollments_to_course_dates: bool = False
    gp_group: GradingPeriodGroup | None = None
    groups: list[Group] = field(default_factory=list)
    assignments: list[Assignment] = field(default_factory=list)
    submissions: dict = field(default_factory=dict)   # assignment id -> Submission
    events: list[Event] = field(default_factory=list)
    announcements: list[Announcement] = field(default_factory=list)
    color: str | None = None
    target_current_score: float | None = None
    notes: str = ""

    def scheme_or_default(self):
        return self.scheme or DEFAULT_GRADING_SCHEME

    def grading_standard_enabled(self):
        return self.grading_standard_id is not None


@dataclass
class PlannerNote:
    id: int
    title: str
    details: str | None
    todo_date: datetime
    created_at: datetime
    course_id: int | None = None


@dataclass
class PlannerOverride:
    id: int
    plannable_type: str       # Canvas class name, e.g. "Assignment"
    plannable_id: int
    marked_complete: bool
    dismissed: bool
    created_at: datetime


@dataclass
class Persona:
    key: str
    title: str
    description: str
    host: str
    school: str
    user: User
    courses: list[Course]
    captured_at: datetime
    anchor: datetime
    role_id_student: int
    planner_notes: list[PlannerNote] = field(default_factory=list)
    planner_overrides: list[PlannerOverride] = field(default_factory=list)
    custom_colors: dict = field(default_factory=dict)
    covers: list[str] = field(default_factory=list)
    extra: dict[str, Any] = field(default_factory=dict)

    def course(self, cid: int) -> Course:
        return next(c for c in self.courses if c.id == cid)


def days(n: float) -> timedelta:
    return timedelta(days=n)
