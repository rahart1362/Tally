"""Small DSL for building persona worlds deterministically."""
from __future__ import annotations

from datetime import date, datetime, timedelta
from itertools import product

from . import gradecalc
from .model import (Announcement, Assignment, Attachment, Course, Enrollment, Event, Group,
                    GradingPeriod, GradingPeriodGroup, Persona, PlannerNote, PlannerOverride,
                    Submission, Teacher, Term, User, letter_score)
from .prng import Rng
from .serialize import calc_input, fake_jwt
from .tz import local_to_utc, UTC

WEEKDAYS = {"MO": 0, "TU": 1, "WE": 2, "TH": 3, "FR": 4, "SA": 5, "SU": 6}

MIME = {
    "pdf": ("application/pdf", "pdf"),
    "docx": ("application/vnd.openxmlformats-officedocument.wordprocessingml.document", "doc"),
    "py": ("text/x-python", "code"),
    "xlsx": ("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "xls"),
    "pptx": ("application/vnd.openxmlformats-officedocument.presentationml.presentation", "ppt"),
}


class Builder:
    def __init__(self, key: str, seed: int, host: str, tzname: str, *, root_account_id: int,
                 account_id: int, id_base: dict):
        self.key = key
        self.rng = Rng.from_label(seed, key)
        self.host = host
        self.tz = tzname
        self.root_account_id = root_account_id
        self.account_id = account_id
        self._next = dict(id_base)

    # ids ------------------------------------------------------------------
    def nid(self, kind: str) -> int:
        v = self._next[kind]
        self._next[kind] = v + self._step(kind)
        return v

    def _step(self, kind):
        return {"submission": 1 + (self.rng.next_u64() % 97), "attachment": 1 + (self.rng.next_u64() % 13),
                "event": 1 + (self.rng.next_u64() % 3)}.get(kind, 1)

    # time -----------------------------------------------------------------
    def at(self, y, mo, d, h=0, mi=0, s=0) -> datetime:
        return local_to_utc(self.tz, y, mo, d, h, mi, s)

    def on(self, d: date, h=0, mi=0, s=0) -> datetime:
        return local_to_utc(self.tz, d.year, d.month, d.day, h, mi, s)

    def jitter(self, dt: datetime, minutes: int) -> datetime:
        return dt + timedelta(seconds=self.rng.randint(0, minutes * 60))

    # people ---------------------------------------------------------------
    def user(self, name, sortable, login, email, created_at, uid=None, locale=None) -> User:
        return User(id=uid or self.nid("user"), name=name, short_name=name, sortable_name=sortable,
                    login_id=login, email=email, time_zone=self.tz, lti_user_id=self.rng.hex(40),
                    feed_uuid=self.rng.alnum(40), created_at=created_at, locale=locale)

    def teacher(self, name, short=None, pronouns=None) -> Teacher:
        return Teacher(id=self.nid("teacher"), name=name, short_name=short or name, pronouns=pronouns)

    # structure ------------------------------------------------------------
    def term(self, name, start, end, created, gpg_id=None) -> Term:
        return Term(id=self.nid("term"), name=name, start_at=start, end_at=end, created_at=created,
                    grading_period_group_id=gpg_id)

    def gp_group(self, weighted: bool, display_totals: bool, periods: list) -> GradingPeriodGroup:
        gid = self.nid("gpgroup")
        g = GradingPeriodGroup(id=gid, weighted=weighted, display_totals=display_totals)
        for title, start, end, close, weight in periods:
            g.periods.append(GradingPeriod(id=self.nid("gp"), title=title, start_date=start, end_date=end,
                                           close_date=close, weight=weight, group_id=gid))
        return g

    def course(self, name, code, term, teachers, created_at, *, cid=None, sections=1,
               enrollment_state="active", **kw) -> Course:
        c = Course(id=cid or self.nid("course"), name=name, course_code=code, uuid=self.rng.alnum(40),
                   term=term, created_at=created_at, account_id=self.account_id,
                   root_account_id=self.root_account_id, time_zone=self.tz, teachers=teachers,
                   enrollments=[Enrollment(id=self.nid("enrollment"), section_id=self.nid("section"),
                                           workflow_state=enrollment_state) for _ in range(sections)],
                   **kw)
        return c

    def group(self, c: Course, name, weight=0.0, **rules) -> Group:
        g = Group(id=self.nid("group"), name=name, position=len(c.groups) + 1, group_weight=float(weight),
                  rules={k: v for k, v in rules.items() if v})
        c.groups.append(g)
        return g

    def assignment(self, c: Course, g: Group, name, points, due, *, created=None, types=("online_upload",),
                   quiz=False, description=None, **kw) -> Assignment:
        aid = self.nid("assignment")
        if quiz:
            types = ("online_quiz",)
            kw.setdefault("quiz_id", self.nid("quiz"))
        created = created or (c.term.start_at - timedelta(days=self.rng.randint(3, 12), minutes=self.rng.randint(0, 600),
                                                           seconds=self.rng.randint(0, 59))
                              if c.term.start_at else c.created_at)
        pos = 1 + sum(1 for a in c.assignments if a.group_id == g.id)
        if description is None:
            description = f"<p>{name}. See the course page for instructions and rubric.</p>"
        elif description == "":
            description = None
        lti = self.rng.uuid4()
        a = Assignment(id=aid, course_id=c.id, name=name, group_id=g.id,
                       points_possible=(None if points is None else float(points)), due_at=due,
                       position=pos, created_at=created, submission_types=tuple(types),
                       description=description, lti_context_id=lti, secure_params=fake_jwt(lti), **kw)
        c.assignments.append(a)
        c.submissions[a.id] = Submission(id=self.nid("submission"), assignment_id=a.id, user_id=0)
        return a

    def attach(self, name: str, created: datetime) -> Attachment:
        ext = name.rsplit(".", 1)[-1]
        ctype, mclass = MIME.get(ext, ("application/octet-stream", "file"))
        return Attachment(id=self.nid("attachment"), uuid=self.rng.alnum(40), folder_id=self._next["folder"],
                          display_name=name, filename=name.replace(" ", "+"), content_type=ctype,
                          size=self.rng.randint(38_000, 2_400_000), created_at=created, mime_class=mclass)

    def grade(self, c: Course, a: Assignment, score=None, *, submitted=None, graded=None, posted="auto",
              letter=None, excused=False, deducted=None, late_policy_status=None, seconds_late_override=None,
              comment=None, viewed="auto", body=None, file=None, grader=None, pending_review=False):
        """Record a submission timeline. ``submitted``/``graded`` are UTC
        datetimes (or None). ``posted='auto'`` posts at grading time unless the
        assignment uses a manual post policy."""
        s = c.submissions[a.id]
        s.user_id = 0
        if submitted is not None:
            s.submitted_at = submitted
            if a.is_quiz():
                s.submission_type = "online_quiz"
                s.body = None
            elif "online_text_entry" in a.submission_types:
                s.submission_type = "online_text_entry"
                s.body = body or f"<p>{a.name} response.</p>"
            elif "discussion_topic" in a.submission_types:
                s.submission_type = "discussion_topic"
            else:
                s.submission_type = "online_upload"
                fname = file or f"{a.name.split(':')[0].replace(' ', '_')}.pdf"
                s.attachments = [self.attach(fname, submitted)]
        if a.grading_type == "letter_grade" and letter and score is None:
            score = letter_score(a, letter)
        if a.grading_type == "pass_fail" and letter:
            score = a.points_possible if letter == "complete" else 0.0
        if graded is not None:
            s.graded_at = graded
            s.excused = excused
            s.entered_score = None if score is None else float(score)
            s.points_deducted = deducted
            s.letter = letter
            s.late_policy_status = late_policy_status
            s.seconds_late_override = seconds_late_override
            s.pending_review = pending_review
            if a.is_quiz() and not pending_review:
                s.grader_id = -a.quiz_id
                s.body = (f"user: {{uid}}, quiz: {a.quiz_id}, score: {float(score) if score is not None else 0.0}, "
                          f"time: {(submitted or graded).astimezone(UTC).strftime('%Y-%m-%d %H:%M:%S')} +0000")
            else:
                s.grader_id = (grader or c.teachers[0]).id
            if posted == "auto":
                s.posted_at = None if a.post_manually else graded
            else:
                s.posted_at = posted
            if comment:
                s.teacher_comment = comment
                s.comment_author = grader or c.teachers[0]
            s.viewed_at = (graded + timedelta(hours=self.rng.randint(2, 30))) if viewed == "auto" else viewed
        elif late_policy_status:
            s.late_policy_status = late_policy_status
            s.seconds_late_override = seconds_late_override
        return s

    def event(self, c: Course, title, start, end, *, location=None, address=None, description=None,
              created=None, all_day=False, series=None, rrule=None, head=None, important=False) -> Event:
        e = Event(id=self.nid("event"), course_id=c.id, title=title, start_at=start, end_at=end,
                  created_at=created or (c.term.start_at - timedelta(days=5)), location_name=location,
                  location_address=address, description=description, all_day=all_day,
                  all_day_date=(start.astimezone(UTC).date().isoformat() if all_day else None),
                  series_uuid=series, rrule=rrule, series_head=head, important_dates=important)
        c.events.append(e)
        return e

    def series(self, c: Course, title, byday: list[str], hh, mm, minutes, first: date, count: int,
               location, address=None, created=None):
        uuid = self.rng.uuid4()
        rrule = f"FREQ=WEEKLY;INTERVAL=1;BYDAY={','.join(byday)};COUNT={count}"
        wd = sorted(WEEKDAYS[d] for d in byday)
        d = first
        n = 0
        while n < count:
            if d.weekday() in wd:
                start = self.on(d, hh, mm)
                self.event(c, title, start, start + timedelta(minutes=minutes), location=location,
                           address=address, created=created, series=uuid, rrule=rrule, head=(n == 0))
                n += 1
            d += timedelta(days=1)

    def announce(self, c: Course, title, message, posted, *, read=None, author=None, comments_disabled=True,
                 replies=0) -> Announcement:
        an = Announcement(id=self.nid("topic"), course_id=c.id, title=title, message=message,
                          posted_at=posted, author=author or c.teachers[0], read_at=read,
                          comments_disabled=comments_disabled, replies=replies)
        c.announcements.append(an)
        return an

    def note(self, title, details, todo, created, course_id=None) -> PlannerNote:
        return PlannerNote(id=self.nid("note"), title=title, details=details, todo_date=todo,
                           created_at=created, course_id=course_id)

    def override(self, cls, pid, marked_complete, dismissed, created) -> PlannerOverride:
        return PlannerOverride(id=self.nid("override"), plannable_type=cls, plannable_id=pid,
                               marked_complete=marked_complete, dismissed=dismissed, created_at=created)


def finalize(p: Persona):
    for c in p.courses:
        for s in c.submissions.values():
            s.user_id = p.user.id
            if s.body and "{uid}" in s.body:
                s.body = s.body.replace("{uid}", str(p.user.id))


def tune_to_target(c: Course, now: datetime, knobs: list, span: float = 6.0, steps=(0.5, 0.25, 0.1)):
    """Adjust up to three graded submissions (their entered score) within
    +/- ``span`` of the authored value, trying coarse score increments first
    (0.5, then 0.25, then 0.1 points), until Canvas's current score -- rounded
    exactly as Canvas rounds it -- equals ``c.target_current_score``.
    Raises if no combination hits the target exactly."""
    target = c.target_current_score
    if target is None:
        return None
    base = [s.entered_score for s in knobs]
    amap = {a.id: a for a in c.assignments}
    for step in steps:
        n = int(round(2 * span / step))
        offsets = sorted((round(-span + i * step, 4) for i in range(n + 1)), key=lambda x: (abs(x), x))
        combos = sorted(product(offsets, repeat=len(knobs)), key=lambda t: (sum(abs(x) for x in t), t))
        for combo in combos:
            ok = True
            for s, b0, off in zip(knobs, base, combo):
                v = round(b0 + off, 4)
                a = amap[s.assignment_id]
                if v < 0 or (a.points_possible and v > a.points_possible):
                    ok = False
                    break
                s.entered_score = v
            if not ok:
                continue
            res = gradecalc.compute_enrollment_scores(calc_input(c, now), now=now)
            if res["current_score"] is not None and abs(res["current_score"] - target) < 1e-9:
                return {"step": step, "offsets": combo}
    for s, b0 in zip(knobs, base):
        s.entered_score = b0
    raise RuntimeError(f"could not tune {c.course_code} to {target}")
