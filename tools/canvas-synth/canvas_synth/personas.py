"""Persona worlds. Every name, school, course and domain is fictional.

Fixed instant: ANCHOR = 2026-09-28T13:00:00Z (Monday). The flagship persona
reproduces the Tally dashboard mockup / first-run prototype (courses, grades,
alerts, due-soon list, today's schedule) translated to that date.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

from .builder import Builder, finalize, tune_to_target
from .gradecalc import DEFAULT_GRADING_SCHEME
from .model import Persona

ANCHOR = datetime(2026, 9, 28, 13, 0, 0, tzinfo=timezone.utc)
SEED = 20260928

CANVAS_PALETTE = ["#1770AB", "#009606", "#65499D", "#D97900", "#4554A4", "#BD3C14", "#E71F63",
                  "#8F3E97", "#0B9BE3", "#06A3B7", "#009688", "#8D9900", "#FD5D10", "#F06291"]

BIO_SCALE = [("A", 0.93), ("A-", 0.90), ("B+", 0.87), ("B", 0.83), ("B-", 0.80), ("C+", 0.77),
             ("C", 0.73), ("C-", 0.70), ("D+", 0.67), ("D", 0.63), ("D-", 0.60), ("F", 0.0)]
STRAIGHT_SCALE = [("A", 0.90), ("B", 0.80), ("C", 0.70), ("D", 0.60), ("F", 0.0)]
COMP_SCALE = [("A", 0.93), ("A-", 0.88), ("B+", 0.85), ("B", 0.82), ("B-", 0.80), ("C+", 0.77),
              ("C", 0.73), ("C-", 0.70), ("D", 0.60), ("F", 0.0)]
PASS_FAIL_SCALE = [("Pass", 0.60), ("Fail", 0.0)]


def _ids(**over):
    base = dict(user=4820117, teacher=300110, term=231, course=51840, group=188200, assignment=1204400,
                quiz=88100, submission=903114000, enrollment=7310400, section=61200, event=3310000,
                topic=2551000, attachment=51200000, folder=774120, note=1200, override=9900,
                gpgroup=812, gp=2201)
    base.update(over)
    return base


# ============================================================================
# (a)/(b) flagship: Alex Sample, Northfield State University
# ============================================================================

def flagship_world() -> Persona:
    b = Builder("flagship", SEED, "canvas.northfield.example", "America/Chicago",
                root_account_id=10, account_id=145, id_base=_ids())
    at = b.at
    user = b.user("Alex Sample", "Sample, Alex", "asample", "alex.sample@students.northfield.example",
                  at(2025, 8, 11, 9, 14, 52), uid=4820117)
    term = b.term("Fall 2026", at(2026, 8, 24), at(2026, 12, 19), at(2026, 2, 17, 10, 3, 41))
    t_math = b.teacher("Casey Linden")
    t_psy = b.teacher("Morgan Fernhill", pronouns="she/her")
    t_bio = b.teacher("Robin Ashgrove")
    t_hist = b.teacher("Taylor Birchwood", pronouns="he/him")
    t_eng = b.teacher("Jamie Quarry")
    t_ta = b.teacher("Quinn Harlow")
    created = at(2026, 4, 2, 11, 20, 5)

    # --- MATH 122 Calculus II (weighted, drop lowest problem set) ----------
    math = b.course("Calculus II", "MATH 122", term, [t_math, t_ta], created, cid=51842, apply_weights=True,
                    grading_standard_id=0, course_format="on_campus", default_view="modules")
    ps = b.group(math, "Problem Sets", 30, drop_lowest=1)
    qz = b.group(math, "Quizzes", 20)
    ex = b.group(math, "Exams", 50)
    ps_due = [(2026, 8, 27), (2026, 9, 3), (2026, 9, 10), (2026, 9, 15), (2026, 9, 17), (2026, 9, 22),
              (2026, 10, 1), (2026, 10, 8), (2026, 10, 15), (2026, 10, 29), (2026, 11, 12)]
    ps_scores = [93, 90, 86, 94, 90, 92]
    ps_items = []
    for i, d in enumerate(ps_due, start=1):
        a = b.assignment(math, ps, f"Problem Set {i}", 100, at(*d, 23, 59, 59))
        ps_items.append(a)
        if i <= len(ps_scores):
            sub = at(*d, 21, 5) - timedelta(hours=b.rng.randint(1, 30))
            if i == 6:
                b.grade(math, a, ps_scores[i - 1], submitted=at(2026, 9, 22, 22, 41, 7),
                        graded=at(2026, 9, 27, 19, 40, 12),
                        comment="Nice work on #4. Watch the sign when you integrate by parts in #7.",
                        viewed=None)
            else:
                b.grade(math, a, ps_scores[i - 1], submitted=sub,
                        graded=at(*d, 12, 0) + timedelta(days=4, minutes=b.rng.randint(0, 300)))
    ws3 = b.assignment(math, ps, "Worksheet 3: Integration by Parts", 50, at(2026, 9, 25, 23, 59, 59))
    # (missing: never submitted)
    q_due = [(2026, 8, 28), (2026, 9, 4), (2026, 9, 11), (2026, 9, 17), (2026, 10, 2), (2026, 10, 16),
             (2026, 11, 6), (2026, 11, 20)]
    q_scores = [96, 92, 97, 85]
    q_items = []
    for i, d in enumerate(q_due, start=1):
        a = b.assignment(math, qz, f"Quiz {i}", 100, at(*d, 10, 50), quiz=True, allowed_attempts=1,
                         unlock_at=at(*d, 10, 0), lock_at=at(*d, 10, 50))
        q_items.append(a)
        if i <= len(q_scores):
            b.grade(math, a, q_scores[i - 1], submitted=at(*d, 10, 38, b.rng.randint(0, 59)),
                    graded=at(*d, 10, 38, 30))
    mid = b.assignment(math, ex, "Midterm Exam", 100, at(2026, 9, 10, 10, 50), types=("on_paper",))
    b.grade(math, mid, 88, graded=at(2026, 9, 14, 16, 2, 44), comment="Solid work. See me about #5.")
    b.assignment(math, ex, "Midterm 2", 100, at(2026, 10, 22, 10, 50), types=("on_paper",))
    b.assignment(math, ex, "Final Exam", 200, at(2026, 12, 15, 10, 0), types=("on_paper",))
    math.target_current_score = 90.1
    math.notes = "Mockup: 90.1% A-; Problem Set 6 92/100 posted Sep 27; Quiz 4 85/100; Midterm 88/100."

    # --- PSY 101 Introduction to Psychology (points) ---------------------------
    psy = b.course("Introduction to Psychology", "PSY 101", term, [t_psy], created, cid=51843,
                   grading_standard_id=0, course_format="on_campus", default_view="syllabus")
    cq = b.group(psy, "Chapter Quizzes")
    rr = b.group(psy, "Reading Responses")
    pex = b.group(psy, "Exams")
    rp = b.group(psy, "Research Participation")
    cq_due = [(2026, 8, 28), (2026, 9, 4), (2026, 9, 11), (2026, 9, 18), (2026, 9, 25), (2026, 10, 2),
              (2026, 10, 9), (2026, 10, 16), (2026, 10, 30), (2026, 11, 13)]
    cq_scores = [18, 17, 19, 16.5, 18]
    for i, d in enumerate(cq_due, start=1):
        a = b.assignment(psy, cq, f"Chapter {i} Quiz", 20, at(*d, 8, 0), quiz=True, allowed_attempts=2)
        if i <= len(cq_scores):
            t = at(*d, 7, 20) - timedelta(days=1, minutes=b.rng.randint(0, 400))
            b.grade(psy, a, cq_scores[i - 1], submitted=t, graded=t + timedelta(minutes=14))
    rr_due = [(2026, 8, 31), (2026, 9, 7), (2026, 9, 14), (2026, 9, 21), (2026, 9, 28), (2026, 10, 5)]
    rr_scores = [9, 8.5, None, 9.5]
    rr_items = []
    for i, d in enumerate(rr_due, start=1):
        a = b.assignment(psy, rr, f"Reading Response {i}", 10, at(*d, 8, 0), types=("online_text_entry",))
        rr_items.append(a)
        if i == 3:
            b.grade(psy, a, None, graded=at(2026, 9, 12, 9, 30), excused=True)
        elif i <= 4:
            t = at(*d, 7, 0) - timedelta(hours=b.rng.randint(4, 40))
            b.grade(psy, a, rr_scores[i - 1], submitted=t, graded=at(*d, 15, 0) + timedelta(days=2))
        elif i == 5:
            b.grade(psy, a, submitted=at(2026, 9, 27, 21, 12, 40))
    rr7 = b.assignment(psy, rr, "Chapter 7 Reading Response", 10, at(2026, 10, 12, 8, 0),
                       types=("online_text_entry",), created=at(2026, 9, 27, 20, 2, 11))
    ex1 = b.assignment(psy, pex, "Exam 1", 100, at(2026, 9, 24, 8, 50), types=("on_paper",))
    b.grade(psy, ex1, 84, graded=at(2026, 9, 25, 15, 44, 9))
    b.assignment(psy, pex, "Exam 2", 100, at(2026, 10, 29, 8, 50), types=("on_paper",))
    b.assignment(psy, pex, "Final Exam", 150, at(2026, 12, 14, 8, 0), types=("on_paper",))
    b.assignment(psy, rp, "Research Participation (SONA credits)", 10, at(2026, 12, 4, 23, 59, 59),
                 types=("none",))
    act = b.assignment(psy, rr, "In-class Activity: Memory Demo", 20, at(2026, 9, 9, 8, 50), types=("on_paper",))
    b.grade(psy, act, 18, graded=at(2026, 9, 11, 10, 0))
    prac = b.assignment(psy, cq, "Syllabus Quiz (practice, not counted)", 5, at(2026, 8, 26, 23, 59, 59),
                        quiz=True, omit_from_final_grade=True)
    b.grade(psy, prac, 5, submitted=at(2026, 8, 25, 19, 2), graded=at(2026, 8, 25, 19, 2, 30))
    psy.target_current_score = 87.2

    # --- BIO 101 Biology 101 (weighted, custom scale, late lab, locked quiz) ---
    bio = b.course("Biology 101", "BIO 101", term, [t_bio], created, cid=51845, apply_weights=True,
                   grading_standard_id=4412, scheme=BIO_SCALE, course_format="on_campus")
    lab = b.group(bio, "Lab Reports", 30)
    bq = b.group(bio, "Quizzes", 20)
    bex = b.group(bio, "Exams", 40)
    part = b.group(bio, "Participation", 10)
    lab_due = [(2026, 9, 6), (2026, 9, 13), (2026, 9, 20), (2026, 10, 4), (2026, 10, 18), (2026, 11, 1),
               (2026, 11, 15), (2026, 12, 6)]
    lab_items = []
    for i, d in enumerate(lab_due, start=1):
        a = b.assignment(bio, lab, f"Lab Report {i}", 50, at(*d, 23, 59, 59), allowed_extensions=["docx", "pdf"])
        lab_items.append(a)
    b.grade(bio, lab_items[0], 47, submitted=at(2026, 9, 6, 20, 13), graded=at(2026, 9, 9, 14, 0), file="Lab1_Microscopy.docx")
    b.grade(bio, lab_items[1], 46, submitted=at(2026, 9, 13, 22, 48), graded=at(2026, 9, 16, 13, 30), file="Lab2_Osmosis.docx")
    b.grade(bio, lab_items[2], 48, submitted=at(2026, 9, 21, 2, 10, 33), graded=at(2026, 9, 23, 11, 5),
            deducted=4.8, file="Lab3_Enzymes.docx", comment="Late by ~2 hours: 10% late penalty applied.")
    b.grade(bio, lab_items[3], submitted=at(2026, 9, 27, 16, 20, 5), file="Lab4_Photosynthesis.docx")
    bq_due = [(2026, 9, 1), (2026, 9, 8), (2026, 9, 15), (2026, 9, 22)]
    bq_scores = [24, 23.5, 25, 22]
    for i, d in enumerate(bq_due, start=1):
        a = b.assignment(bio, bq, f"Quiz {i}", 25, at(*d, 8, 0), quiz=True)
        b.grade(bio, a, bq_scores[i - 1], submitted=at(*d, 7, 31, b.rng.randint(0, 59)) - timedelta(days=1),
                graded=at(*d, 7, 45) - timedelta(days=1))
    quiz5 = b.assignment(bio, bq, "Quiz 5: Cellular Respiration", 25, at(2026, 9, 29, 8, 0), quiz=True,
                         unlock_at=at(2026, 9, 29, 7, 0), lock_at=at(2026, 9, 29, 8, 30), allowed_attempts=1)
    for i, d in enumerate([(2026, 10, 13), (2026, 10, 27), (2026, 11, 10)], start=6):
        b.assignment(bio, bq, f"Quiz {i}", 25, at(*d, 8, 0), quiz=True)
    bex1 = b.assignment(bio, bex, "Exam 1", 100, at(2026, 9, 17, 12, 50), types=("on_paper",))
    b.grade(bio, bex1, 94, graded=at(2026, 9, 21, 9, 12))
    b.assignment(bio, bex, "Lab Practical", 100, at(2026, 10, 15, 13, 50), types=("on_paper",))
    b.assignment(bio, bex, "Final Exam", 150, at(2026, 12, 16, 12, 0), types=("on_paper",))
    p1 = b.assignment(bio, part, "Participation: Weeks 1-4", 20, at(2026, 9, 18, 23, 59), types=("none",))
    b.grade(bio, p1, 20, graded=at(2026, 9, 21, 9, 30))
    b.assignment(bio, part, "Participation: Weeks 5-8", 20, at(2026, 10, 16, 23, 59), types=("none",))
    bio.target_current_score = 93.4

    # --- HIST 210 World History (points, straight scale, missing + late) -------
    hist = b.course("World History", "HIST 210", term, [t_hist], created, cid=51846,
                    grading_standard_id=4413, scheme=STRAIGHT_SCALE, course_format="on_campus")
    psa = b.group(hist, "Primary Source Analyses")
    ess = b.group(hist, "Essays")
    mq = b.group(hist, "Map Quizzes")
    hp = b.group(hist, "Participation")
    psa_due = [(2026, 9, 4), (2026, 9, 11), (2026, 9, 25), (2026, 10, 9), (2026, 10, 23), (2026, 11, 6)]
    psa_items = [b.assignment(hist, psa, f"Primary Source Analysis {i}", 25, at(*d, 23, 59, 59),
                              types=("online_text_entry",)) for i, d in enumerate(psa_due, start=1)]
    b.grade(hist, psa_items[0], 22, submitted=at(2026, 9, 4, 18, 22), graded=at(2026, 9, 8, 10, 0))
    b.grade(hist, psa_items[1], 21, submitted=at(2026, 9, 12, 2, 31, 6), graded=at(2026, 9, 15, 10, 0),
            deducted=1.25)
    essay1 = b.assignment(hist, ess, "Essay 1: Empires and Exchange", 100, at(2026, 9, 18, 23, 59, 59),
                          allowed_extensions=["docx", "pdf"])
    b.grade(hist, essay1, 81, submitted=at(2026, 9, 18, 21, 40), graded=at(2026, 9, 24, 17, 5),
            file="Essay1_Empires.docx", comment="Clear thesis; strengthen the evidence in section 2.")
    essay2 = b.assignment(hist, ess, "Essay 2", 100, at(2026, 10, 3, 23, 59, 59), allowed_extensions=["docx", "pdf"])
    essay2.due_changes.append((at(2026, 9, 27, 11, 30), at(2026, 10, 5, 23, 59, 59)))
    b.assignment(hist, ess, "Essay 3", 100, at(2026, 11, 13, 23, 59, 59), allowed_extensions=["docx", "pdf"])
    mqs = [b.assignment(hist, mq, f"Map Quiz {i}", 10, at(*d, 14, 50), quiz=True)
           for i, d in enumerate([(2026, 9, 2), (2026, 9, 16), (2026, 9, 30), (2026, 10, 14)], start=1)]
    b.grade(hist, mqs[0], 9, submitted=at(2026, 9, 2, 14, 40), graded=at(2026, 9, 2, 14, 40, 30))
    b.grade(hist, mqs[1], 8, submitted=at(2026, 9, 16, 14, 42), graded=at(2026, 9, 16, 14, 42, 30))
    ori = b.assignment(hist, hp, "Library Orientation", 30, at(2026, 8, 31, 23, 59, 59), types=("online_text_entry",))
    b.grade(hist, ori, 30, submitted=at(2026, 8, 30, 15, 12), graded=at(2026, 9, 1, 9, 0))
    b.assignment(hist, hp, "Participation: September", 20, at(2026, 9, 30, 23, 59), types=("none",))
    hist.target_current_score = 82.0

    # --- ENG 101 English Composition (weighted, unposted draft, manual late) ----
    eng = b.course("English Composition", "ENG 101", term, [t_eng], created, cid=51847, apply_weights=True,
                   grading_standard_id=4414, scheme=COMP_SCALE, course_format="blended")
    es = b.group(eng, "Essays", 50)
    dr = b.group(eng, "Drafts & Peer Review", 20)
    jn = b.group(eng, "Journals", 20)
    ep = b.group(eng, "Participation", 10)
    fd = b.assignment(eng, es, "Final Draft", 100, at(2026, 10, 12, 23, 59, 59), allowed_extensions=["docx"])
    b.assignment(eng, es, "Essay 2: Final Draft", 100, at(2026, 11, 16, 23, 59, 59), allowed_extensions=["docx"])
    b.assignment(eng, es, "Portfolio", 100, at(2026, 12, 10, 23, 59, 59), allowed_extensions=["docx", "pdf"])
    diag = b.assignment(eng, dr, "Diagnostic Essay", 20, at(2026, 8, 28, 23, 59, 59), types=("online_text_entry",))
    b.grade(eng, diag, 18, submitted=at(2026, 8, 28, 20, 5), graded=at(2026, 9, 2, 9, 0))
    prw = b.assignment(eng, dr, "Peer Review Worksheet 1", 10, at(2026, 9, 18, 23, 59, 59),
                       types=("online_text_entry",))
    b.grade(eng, prw, 9, submitted=at(2026, 9, 19, 23, 15), graded=at(2026, 9, 22, 10, 0),
            late_policy_status="late", seconds_late_override=86400)
    rough = b.assignment(eng, dr, "Rough Draft", 20, at(2026, 9, 25, 23, 59, 59), allowed_extensions=["docx"],
                         post_manually=True)
    b.grade(eng, rough, 17, submitted=at(2026, 9, 25, 22, 2), graded=at(2026, 9, 27, 15, 30), posted=None,
            file="RoughDraft_Sample.docx")
    j_due = [(2026, 9, 2), (2026, 9, 9), (2026, 9, 16), (2026, 9, 23), (2026, 9, 30), (2026, 10, 7),
             (2026, 10, 14), (2026, 10, 21)]
    j_scores = [5, 4.5, 5, 4]
    j_items = []
    for i, d in enumerate(j_due, start=1):
        a = b.assignment(eng, jn, f"Journal {i}", 5, at(*d, 23, 59, 59), types=("online_text_entry",))
        j_items.append(a)
        if i <= len(j_scores):
            b.grade(eng, a, j_scores[i - 1], submitted=at(*d, 21, 30), graded=at(*d, 12, 0) + timedelta(days=2))
    pw = b.assignment(eng, ep, "Participation: Weeks 1-5", 10, at(2026, 9, 25, 23, 59), types=("none",))
    b.grade(eng, pw, 9.5, graded=at(2026, 9, 26, 10, 0))
    b.assignment(eng, ep, "Writing Center Visit (optional)", None, None, types=("not_graded",))
    eng.target_current_score = 89.0

    # --- calendar: class meetings (the mockup's schedule) and exams -------------
    first = date(2026, 8, 24)
    b.series(psy, "PSY 101 Lecture", ["MO", "WE", "FR"], 8, 0, 50, first, 48, "Sage Hall 101")
    b.series(math, "Calculus II Lecture", ["MO", "WE", "FR"], 10, 0, 50, first, 48, "Sage Hall 210")
    b.series(bio, "Biology 101 Lab", ["MO"], 12, 0, 50, first, 16, "Science Building 204")
    b.series(hist, "World History Lecture", ["MO"], 14, 0, 110, first, 16, "Humanities 205")
    b.series(eng, "English Composition Seminar", ["MO"], 16, 0, 75, first, 16, "Liberal Arts 103")
    b.event(math, "Midterm 2 (in class)", at(2026, 10, 22, 10, 0), at(2026, 10, 22, 10, 50),
            location="Sage Hall 210", important=True, created=at(2026, 8, 20, 9, 0))
    b.event(math, "Midterm 2 review session", at(2026, 10, 1, 17, 0), at(2026, 10, 1, 18, 30),
            location="Sage Hall 118", created=at(2026, 9, 25, 15, 5),
            description="<p>Optional review. Bring your questions from Problem Sets 5-7.</p>")
    b.event(bio, "Lab Practical", at(2026, 10, 15, 12, 0), at(2026, 10, 15, 13, 50), location="Science Building 204",
            important=True, created=at(2026, 8, 20, 9, 0))
    b.event(psy, "Exam 2", at(2026, 10, 29, 8, 0), at(2026, 10, 29, 8, 50), location="Sage Hall 101",
            important=True, created=at(2026, 8, 20, 9, 0))
    b.event(hist, "Fall Break (no class)", at(2026, 10, 19), at(2026, 10, 19), all_day=True,
            created=at(2026, 8, 20, 9, 0))

    # --- announcements ---------------------------------------------------------
    b.announce(psy, "Guest lecture this Friday", "<p>Our guest on Friday will talk about sleep and memory. "
               "Attendance counts toward participation.</p>", at(2026, 9, 16, 9, 0), read=at(2026, 9, 16, 12, 0))
    b.announce(eng, "Writing Center drop-in hours", "<p>The Writing Center is open for drop-ins Mon-Thu "
               "2-6 pm in Liberal Arts 110.</p>", at(2026, 9, 21, 10, 0), read=at(2026, 9, 21, 18, 0))
    b.announce(psy, "Exam 1 scores posted", "<p>Exam 1 scores are posted. The class average was 78%.</p>",
               at(2026, 9, 25, 16, 0), read=at(2026, 9, 25, 19, 0))
    b.announce(math, "Midterm 2 review session Thursday", "<p>Review session Thursday Oct 1, 5:00-6:30 pm "
               "in Sage Hall 118.</p>", at(2026, 9, 25, 15, 10), read=at(2026, 9, 25, 20, 0), author=t_math)
    b.announce(hist, "Essay 2 now due Monday, Oct 5", "<p>Essay 2 is now due <strong>Monday, Oct 5 at "
               "11:59 pm</strong>. The prompt is unchanged.</p>", at(2026, 9, 27, 11, 30))
    b.announce(math, "Problem Set 6 graded & solutions posted", "<p>Problem Set 6 is graded. Solutions "
               "are in Files > Solutions.</p>", at(2026, 9, 27, 19, 45), author=t_math)
    b.announce(bio, "Quiz 5 tomorrow: Chapters 4-5", "<p>Quiz 5 opens at 7:00 am and closes at 8:30 am "
               "Tuesday. It covers Chapters 4-5.</p>", at(2026, 9, 27, 20, 5))
    b.announce(bio, "Welcome to Biology 101", "<p>Welcome! Lab sections start in week 2.</p>",
               at(2026, 8, 21, 9, 0), read=at(2026, 8, 22, 9, 0))

    persona = Persona(
        key="flagship", title="Flagship undergrad (dashboard mockup)",
        description="Alex Sample, 5 courses at Northfield State University reproducing the Tally mockup: "
                    "Calculus II 90.1% A-, Introduction to Psychology 87.2% B+, Biology 101 93.4% A, "
                    "World History 82.0% B, English Composition 89.0% A-.",
        host="canvas.northfield.example", school="Northfield State University", user=user,
        courses=[math, psy, bio, hist, eng], captured_at=ANCHOR, anchor=ANCHOR, role_id_student=19,
        custom_colors={"course_51842": "#1770AB", "course_51843": "#009606", "course_51845": "#65499D",
                       "course_51846": "#D97900", "course_51847": "#4554A4", "user_4820117": "#8F3E97"},
        covers=["weighted groups", "unweighted groups", "drop lowest", "custom grading schemes",
                "missing (unsubmitted)", "late with deduction", "late (manual status)", "excused",
                "unposted grade (manual post policy)", "omit_from_final_grade", "not_graded assignment",
                "locked quiz (unlock_at in future)", "due-date change", "recurring class events",
                "multi-page planner and calendar events", "planner note", "planner override",
                "new_activity on newly posted grade", "graded quiz with negative grader_id"],
    )
    persona.planner_notes.append(b.note("Study group: Calc II", "Library 3rd floor, bring PS7",
                                        at(2026, 9, 29, 18, 0), at(2026, 9, 26, 21, 4), course_id=51842))
    persona.planner_overrides.append(b.override("Assignment", j_items[4].id, True, False, at(2026, 9, 26, 8, 3)))
    finalize(persona)

    knobs = {51842: [math.submissions[ps_items[4].id], math.submissions[q_items[2].id]],
             51843: [psy.submissions[ex1.id], psy.submissions[rr_items[3].id]],
             51845: [bio.submissions[bex1.id], bio.submissions[lab_items[1].id]],
             51846: [hist.submissions[essay1.id], hist.submissions[psa_items[0].id]],
             51847: [eng.submissions[j_items[3].id], eng.submissions[diag.id]]}
    for c in persona.courses:
        tune_to_target(c, ANCHOR, knobs[c.id])
    persona.extra["mockup"] = {"calendar_today": "Mon Sep 28 (mockup: Mon May 6)",
                               "missing": ["Worksheet 3: Integration by Parts (MATH 122)",
                                           "Primary Source Analysis 3 (HIST 210)"],
                               "upcoming_quiz": "Quiz 5: Cellular Respiration (BIO 101), Tue Sep 29 8:00 AM",
                               "recent_grade": "Problem Set 6 (MATH 122) 92/100, posted Sun Sep 27"}
    return persona


def flagship() -> Persona:
    return flagship_world()


def flagship_previous() -> Persona:
    p = flagship_world()
    p.key = "flagship-previous"
    p.title = "Flagship undergrad, one day earlier"
    p.description = ("The same world as 'flagship' observed 24 hours earlier (2026-09-27T13:00:00Z), so "
                     "diffing the two snapshots yields a real change digest.")
    p.captured_at = ANCHOR - timedelta(days=1)
    p.covers = ["change digest baseline"]
    return p


# ============================================================================
# (c) finals-week overload: Riley Sample, Harbor City College (8-week session)
# ============================================================================

def finals() -> Persona:
    b = Builder("finals", SEED, "harborcity.instructure.example", "America/Los_Angeles",
                root_account_id=22, account_id=301,
                id_base=_ids(user=5561204, teacher=410220, term=77, course=70310, group=240100,
                             assignment=2300100, quiz=120300, submission=611020000, enrollment=8100200,
                             section=90110, event=4410000, topic=3301000, attachment=66100000, folder=880200))
    at = b.at
    user = b.user("Riley Sample", "Sample, Riley", "rsample", "riley.sample@mail.harborcity.example",
                  at(2024, 6, 3, 13, 2, 11), uid=5561204)
    term = b.term("Fall 2026 - Session 1 (8 weeks)", at(2026, 8, 10), at(2026, 10, 4, 23, 59, 59),
                  at(2026, 3, 1, 12, 0))
    created = at(2026, 5, 12, 9, 30)
    t1, t2, t3, t4 = (b.teacher("Avery Cloudmere"), b.teacher("Rowan Tidewell"), b.teacher("Emerson Vale"),
                      b.teacher("Kai Larkspur"))
    weeks = [date(2026, 8, 10) + timedelta(days=7 * i) for i in range(8)]

    acct = b.course("Principles of Accounting I", "ACCT 201", term, [t1], created, cid=70311, apply_weights=True,
                    grading_standard_id=0, course_format="online")
    hw = b.group(acct, "Homework", 25)
    aq = b.group(acct, "Quizzes", 15)
    am = b.group(acct, "Midterm", 25)
    af = b.group(acct, "Final Exam", 35)
    acct_hw = []
    for i in range(7):
        d = weeks[i] + timedelta(days=6)
        a = b.assignment(acct, hw, f"Homework {i + 1}", 20, b.on(d, 23, 59, 59))
        acct_hw.append(a)
        if i < 6:
            b.grade(acct, a, [18, 17, 19, 16, 18, 17.5][i], submitted=b.on(d, 19, 10), graded=b.on(d, 12) + timedelta(days=2))
    for i in range(5):
        d = weeks[i] + timedelta(days=3)
        a = b.assignment(acct, aq, f"Quiz {i + 1}", 10, b.on(d, 23, 59), quiz=True)
        b.grade(acct, a, [9, 8, 8.5, 9, 7.5][i], submitted=b.on(d, 20, 5), graded=b.on(d, 20, 5, 40))
    amid = b.assignment(acct, am, "Midterm Exam", 100, at(2026, 9, 3, 11, 0), types=("on_paper",))
    b.grade(acct, amid, 84, graded=at(2026, 9, 5, 10, 0))
    b.assignment(acct, af, "Final Exam", 100, at(2026, 9, 29, 11, 0), types=("on_paper",))
    acct.target_current_score = 85.3

    chem = b.course("Introductory Chemistry", "CHEM 110", term, [t2], created, cid=70312, apply_weights=True,
                    grading_standard_id=0, course_format="on_campus")
    cl = b.group(chem, "Labs", 25)
    ch = b.group(chem, "Homework", 15)
    ce = b.group(chem, "Exams", 30)
    cf = b.group(chem, "Final Exam", 30)
    chem_labs = []
    for i in range(8):
        d = weeks[i] + timedelta(days=2) if i < 7 else date(2026, 9, 30)
        a = b.assignment(chem, cl, f"Lab {i + 1} Report", 25, b.on(d, 23, 59, 59))
        chem_labs.append(a)
        if i < 7:
            b.grade(chem, a, [20, 18, 17, 19, 16, 18, 17][i], submitted=b.on(d, 21, 0), graded=b.on(d, 12) + timedelta(days=3))
    chw = []
    for i in range(7):
        d = weeks[i] + timedelta(days=6) if i < 6 else date(2026, 9, 28)
        a = b.assignment(chem, ch, f"Problem Set {i + 1}", 15, b.on(d, 23, 59, 59))
        chw.append(a)
        if i < 6:
            b.grade(chem, a, [12, 11, 10.5, 12, 9, 11][i], submitted=b.on(d, 22, 0), graded=b.on(d, 12) + timedelta(days=2))
    e1 = b.assignment(chem, ce, "Exam 1", 100, at(2026, 8, 27, 12, 0), types=("on_paper",))
    b.grade(chem, e1, 68, graded=at(2026, 8, 31, 9, 0))
    e2 = b.assignment(chem, ce, "Exam 2", 100, at(2026, 9, 17, 12, 0), types=("on_paper",))
    b.grade(chem, e2, 71, graded=at(2026, 9, 21, 9, 0))
    b.assignment(chem, cf, "Final Exam", 100, at(2026, 9, 29, 12, 30), types=("on_paper",))
    chem.target_current_score = 70.04

    stat = b.course("Elementary Statistics", "STAT 150", term, [t3], created, cid=70313,
                    grading_standard_id=0, course_format="online")
    sh = b.group(stat, "Homework")
    sq = b.group(stat, "Quizzes")
    se = b.group(stat, "Exams")
    sp = b.group(stat, "Final Project")
    stat_hw = []
    for i in range(7):
        d = weeks[i] + timedelta(days=6) if i < 6 else date(2026, 9, 28)
        a = b.assignment(stat, sh, f"Homework {i + 1}", 10, b.on(d, 23, 59, 59), types=("online_text_entry",))
        stat_hw.append(a)
        if i < 6:
            b.grade(stat, a, [9.5, 9, 10, 8.5, 9, 9.5][i], submitted=b.on(d, 20, 0), graded=b.on(d, 12) + timedelta(days=1))
    for i in range(4):
        d = weeks[2 * i] + timedelta(days=4)
        a = b.assignment(stat, sq, f"Quiz {i + 1}", 10, b.on(d, 23, 59), quiz=True)
        b.grade(stat, a, [9, 8.5, 9.5, 9][i], submitted=b.on(d, 19, 0), graded=b.on(d, 19, 0, 30))
    smid = b.assignment(stat, se, "Midterm", 100, at(2026, 9, 3, 13, 0), types=("on_paper",))
    b.grade(stat, smid, 88, graded=at(2026, 9, 8, 9, 0))
    b.assignment(stat, se, "Final Exam", 100, at(2026, 9, 30, 15, 0), types=("on_paper",))
    b.assignment(stat, sp, "Final Project", 50, at(2026, 9, 30, 23, 59, 59), allowed_extensions=["pdf", "xlsx"])
    stat.target_current_score = 89.95

    comm = b.course("Public Speaking", "COMM 105", term, [t4], created, cid=70314, apply_weights=True,
                    grading_standard_id=0, course_format="on_campus")
    csp = b.group(comm, "Speeches", 60)
    cou = b.group(comm, "Outlines", 20)
    cpa = b.group(comm, "Participation", 20)
    s1 = b.assignment(comm, csp, "Informative Speech", 100, at(2026, 8, 27, 9, 0), types=("on_paper",))
    b.grade(comm, s1, 86, graded=at(2026, 8, 28, 16, 0))
    s2 = b.assignment(comm, csp, "Demonstration Speech", 100, at(2026, 9, 15, 9, 0), types=("on_paper",))
    b.grade(comm, s2, 90, graded=at(2026, 9, 16, 16, 0))
    b.assignment(comm, csp, "Final Persuasive Speech", 100, at(2026, 10, 1, 9, 0), types=("on_paper",))
    o1 = b.assignment(comm, cou, "Outline: Informative", 20, at(2026, 8, 25, 23, 59, 59))
    b.grade(comm, o1, 18, submitted=at(2026, 8, 25, 20, 0), graded=at(2026, 8, 27, 10, 0))
    o2 = b.assignment(comm, cou, "Outline: Demonstration", 20, at(2026, 9, 13, 23, 59, 59))
    b.grade(comm, o2, 17, submitted=at(2026, 9, 13, 22, 0), graded=at(2026, 9, 15, 10, 0))
    b.assignment(comm, cou, "Outline: Persuasive", 20, at(2026, 9, 30, 23, 59, 59))
    pa = b.assignment(comm, cpa, "Participation", 50, at(2026, 10, 2, 17, 0), types=("none",))
    b.grade(comm, pa, 45, graded=at(2026, 9, 25, 12, 0), posted=at(2026, 9, 25, 12, 0))
    b.assignment(comm, cpa, "Speech Self-Evaluation", 10, at(2026, 10, 1, 23, 59, 59), types=("online_text_entry",))
    b.assignment(comm, cpa, "Peer Feedback Forms", 10, at(2026, 10, 2, 12, 0), types=("online_text_entry",))
    comm.target_current_score = 88.4

    b.event(acct, "ACCT 201 Final Exam", at(2026, 9, 29, 9, 0), at(2026, 9, 29, 11, 0), location="Business 140",
            important=True, created=at(2026, 8, 5, 10, 0))
    b.event(chem, "CHEM 110 Final Exam", at(2026, 9, 29, 10, 30), at(2026, 9, 29, 12, 30), location="Science 301",
            important=True, created=at(2026, 8, 5, 10, 0),
            description="<p>Room changed from Science 214 to Science 301.</p>")
    b.event(chem, "Final review session", at(2026, 9, 28, 16, 0), at(2026, 9, 28, 17, 30), location="Science 214",
            created=at(2026, 9, 21, 10, 0))
    b.event(stat, "STAT 150 Final Exam", at(2026, 9, 30, 13, 0), at(2026, 9, 30, 15, 0), location="Online (proctored)",
            important=True, created=at(2026, 8, 5, 10, 0))
    b.event(stat, "Office hours (final project)", at(2026, 9, 29, 15, 0), at(2026, 9, 29, 16, 0),
            location="Library 2B", created=at(2026, 9, 22, 10, 0))
    b.event(comm, "Final Persuasive Speeches", at(2026, 10, 1, 9, 0), at(2026, 10, 1, 11, 30),
            location="Fine Arts 12", important=True, created=at(2026, 8, 5, 10, 0))
    b.event(acct, "Session 1 grades due", at(2026, 10, 6), at(2026, 10, 6), all_day=True, created=at(2026, 8, 5, 10, 0))
    b.announce(chem, "Final exam room change", "<p>The final is now in <strong>Science 301</strong>.</p>",
               at(2026, 9, 26, 12, 0), read=at(2026, 9, 26, 18, 0))
    b.announce(stat, "Final project rubric", "<p>The rubric for the final project is posted.</p>",
               at(2026, 9, 24, 9, 0), read=at(2026, 9, 24, 20, 0))
    b.announce(comm, "Speech order posted", "<p>Speaking order for Thursday is posted in Files.</p>",
               at(2026, 9, 27, 18, 0))
    b.announce(acct, "Final exam: bring a calculator", "<p>Non-programmable calculators only.</p>",
               at(2026, 9, 27, 9, 0))

    persona = Persona(
        key="finals", title="Finals-week overload",
        description="Riley Sample, last week of an 8-week session at Harbor City College: 4 exams in 3 days, "
                    "two overlapping finals on Tuesday, 12 items due in 5 days, CHEM 110 at 70.04% (C-, just "
                    "above D+) and STAT 150 at 89.95% (B+, 0.05 below A-).",
        host="harborcity.instructure.example", school="Harbor City College", user=user,
        courses=[acct, chem, stat, comm], captured_at=ANCHOR, anchor=ANCHOR, role_id_student=34,
        custom_colors={"course_70311": CANVAS_PALETTE[5], "course_70312": CANVAS_PALETTE[9],
                       "course_70313": CANVAS_PALETTE[7], "course_70314": CANVAS_PALETTE[11]},
        covers=["clustered deadlines", "overlapping exam events", "score just above a threshold",
                "score just below a threshold", "term ending this week"])
    finalize(persona)
    knobs = {70311: [acct.submissions[amid.id], acct.submissions[acct_hw[2].id]],
             70312: [chem.submissions[e2.id], chem.submissions[chem_labs[3].id], chem.submissions[chw[1].id]],
             70313: [stat.submissions[smid.id], stat.submissions[stat_hw[3].id]],
             70314: [comm.submissions[s2.id], comm.submissions[o2.id]]}
    for c in persona.courses:
        tune_to_target(c, ANCHOR, knobs[c.id])
    return persona


# ============================================================================
# (d) grading periods, hidden final grades, pass/fail, letter-only
# ============================================================================

def grading_periods() -> Persona:
    b = Builder("grading-periods", SEED, "northgate.instructure.example", "America/New_York",
                root_account_id=31, account_id=31,
                id_base=_ids(user=6603318, teacher=520330, term=610, course=90410, group=310400,
                             assignment=3400100, quiz=150400, submission=720330000, enrollment=9200300,
                             section=99100, event=5510000, topic=4401000, attachment=77100000, folder=990300,
                             gpgroup=812, gp=2201))
    at = b.at
    user = b.user("Jordan Sample", "Sample, Jordan", "jsample", "jordan.sample@learners.northgate.example",
                  at(2023, 8, 14, 8, 0, 3), uid=6603318)
    gpg = b.gp_group(True, True, [
        ("Quarter 1", at(2026, 8, 17), at(2026, 10, 16, 23, 59, 59), at(2026, 10, 23, 23, 59, 59), 40.0),
        ("Quarter 2", at(2026, 10, 17), at(2026, 12, 18, 23, 59, 59), at(2026, 12, 23, 23, 59, 59), 40.0),
        ("Semester Exam", at(2026, 12, 19), at(2027, 1, 22, 23, 59, 59), at(2027, 1, 29, 23, 59, 59), 20.0),
    ])
    term = b.term("Fall Semester 2026", at(2026, 8, 17), at(2027, 1, 22, 23, 59, 59), at(2026, 1, 30, 9, 0),
                  gpg_id=gpg.id)
    created = at(2026, 6, 1, 8, 0)
    t1, t2, t3, t4 = (b.teacher("Sasha Brightwater"), b.teacher("Devon Marsh"), b.teacher("Parker Hollis"),
                      b.teacher("Reese Calder"))
    wk = [date(2026, 8, 17) + timedelta(days=7 * i) for i in range(20)]

    alg = b.course("Algebra II", "ALG2-B", term, [t1], created, cid=90411, apply_weights=True, grading_standard_id=0,
                   gp_group=gpg, course_format="online")
    hw = b.group(alg, "Homework", 20, drop_lowest=2)
    aq = b.group(alg, "Quizzes", 30)
    ts = b.group(alg, "Tests", 50)
    hw_items = []
    hw_scores = [6, 10, 9, 8, 10, 9.5, 7, 10]
    for i in range(16):
        d = wk[i] + timedelta(days=3)
        a = b.assignment(alg, hw, "Homework 1: Syllabus & Calculator Check" if i == 0 else f"Homework {i + 1}",
                         10, b.on(d, 23, 59, 59), types=("online_text_entry",))
        hw_items.append(a)
        if i < len(hw_scores):
            b.grade(alg, a, hw_scores[i], submitted=b.on(d, 19, 0), graded=b.on(d, 12) + timedelta(days=2))
    hw.rules["never_drop"] = [hw_items[0].id]
    q_items = []
    for i in range(6):
        d = wk[2 * i + 1] + timedelta(days=4)
        a = b.assignment(alg, aq, f"Quiz {i + 1}", 25, b.on(d, 15, 0), quiz=True)
        q_items.append(a)
        if i < 3:
            b.grade(alg, a, [21, 23, 19.5][i], submitted=b.on(d, 14, 30), graded=b.on(d, 14, 30, 30))
    t_1 = b.assignment(alg, ts, "Unit 1 Test", 100, at(2026, 9, 11, 15, 0), types=("on_paper",))
    b.grade(alg, t_1, 88, graded=at(2026, 9, 15, 16, 0))
    t_2 = b.assignment(alg, ts, "Unit 2 Test", 100, at(2026, 10, 9, 15, 0), types=("on_paper",))
    b.assignment(alg, ts, "Unit 3 Test", 100, at(2026, 11, 13, 15, 0), types=("on_paper",))
    b.assignment(alg, ts, "Semester Exam", 150, at(2027, 1, 14, 10, 0), types=("on_paper",))
    b.assignment(alg, hw, "Math Portfolio (ongoing, no due date)", 20, None, types=("online_upload",))
    alg.target_current_score = 88.6

    chm = b.course("Chemistry Honors", "CHEM-H", term, [t2], created, cid=90412, hide_final_grades=True,
                   grading_standard_id=0, gp_group=gpg, course_format="online")
    cl = b.group(chm, "Labs")
    ct = b.group(chm, "Tests")
    for i in range(6):
        d = wk[i + 1] + timedelta(days=4)
        a = b.assignment(chm, cl, f"Lab {i + 1}", 20, b.on(d, 23, 59, 59))
        if i == 2:
            b.grade(chm, a, None, graded=b.on(d, 9) + timedelta(days=3), excused=True,
                    comment="Excused (school trip).")
        elif i < 5:
            b.grade(chm, a, [18, 17, None, 19, 16][i], submitted=b.on(d, 20, 0), graded=b.on(d, 9) + timedelta(days=3))
    ct1 = b.assignment(chm, ct, "Unit 1 Test", 100, at(2026, 9, 18, 14, 0), types=("on_paper",))
    b.grade(chm, ct1, 91, graded=at(2026, 9, 22, 15, 0))
    b.assignment(chm, ct, "Unit 2 Test", 100, at(2026, 10, 30, 14, 0), types=("on_paper",))

    pe = b.course("Physical Education", "PE-9", term, [t3], created, cid=90413, grading_standard_id=5510,
                  scheme=PASS_FAIL_SCALE, gp_group=gpg, course_format="online")
    pl = b.group(pe, "Activity Logs")
    for i in range(10):
        d = wk[i] + timedelta(days=4)
        a = b.assignment(pe, pl, f"Weekly Activity Log {i + 1}", 10, b.on(d, 23, 59, 59), grading_type="pass_fail",
                         types=("online_text_entry",))
        if i < 6:
            b.grade(pe, a, letter="incomplete" if i == 3 else "complete", submitted=b.on(d, 18, 0),
                    graded=b.on(d, 9) + timedelta(days=2))

    art = b.course("Studio Art", "ART-1", term, [t4], created, cid=90414, grading_standard_id=0,
                   gp_group=gpg, course_format="online")
    ap = b.group(art, "Projects")
    asb = b.group(art, "Sketchbook")
    letters = ["A-", "B+", "A"]
    for i in range(5):
        d = wk[2 * i + 1] + timedelta(days=4)
        a = b.assignment(art, ap, f"Project {i + 1}", 50, b.on(d, 23, 59, 59), grading_type="letter_grade",
                         allowed_extensions=["jpg", "png", "pdf"])
        if i < 3:
            b.grade(art, a, letter=letters[i], submitted=b.on(d, 20, 0), graded=b.on(d, 9) + timedelta(days=3),
                    file=f"Project{i + 1}.pdf")
    for i in range(6):
        d = wk[i + 1] + timedelta(days=4)
        a = b.assignment(art, asb, f"Sketchbook Check {i + 1}", 10, b.on(d, 23, 59, 59), grading_type="letter_grade",
                         types=("on_paper",))
        if i < 5:
            b.grade(art, a, letter=["A", "B", "A-", "B+", "A"][i], graded=b.on(d, 9) + timedelta(days=2))

    b.announce(alg, "Unit 2 Test moved to Oct 9", "<p>The Unit 2 Test is Friday Oct 9.</p>", at(2026, 9, 21, 8, 0),
               read=at(2026, 9, 21, 15, 0))
    b.announce(chm, "Lab safety reminder", "<p>Goggles on for every lab, including virtual demos.</p>",
               at(2026, 9, 24, 8, 0))
    b.event(alg, "Quarter 1 ends", at(2026, 10, 16), at(2026, 10, 16), all_day=True, created=at(2026, 8, 1, 9, 0))
    b.event(chm, "Live lab session", at(2026, 10, 1, 13, 0), at(2026, 10, 1, 14, 0), location="Online",
            created=at(2026, 9, 20, 9, 0),
            description="<p>Join from the Live Sessions page in the course.</p>")

    persona = Persona(
        key="grading-periods", title="Grading periods, hidden totals, pass/fail, letter-only",
        description="Jordan Sample at Northgate Online Academy. The term uses a weighted grading-period set "
                    "(Quarter 1 40%, Quarter 2 40%, Semester Exam 20%). Chemistry Honors hides final grades; "
                    "Physical Education is pass/fail; Studio Art is letter-graded only.",
        host="northgate.instructure.example", school="Northgate Online Academy", user=user,
        courses=[alg, chm, pe, art], captured_at=ANCHOR, anchor=ANCHOR, role_id_student=45,
        custom_colors={"course_90411": CANVAS_PALETTE[0], "course_90412": CANVAS_PALETTE[6]},
        covers=["weighted grading periods", "current grading period scores", "no-due-date assignment in last period",
                "hide_final_grades (no computed_* fields)", "pass_fail assignments", "letter_grade assignments",
                "course pass/fail scheme", "never_drop + drop_lowest", "excused lab"])
    finalize(persona)
    tune_to_target(alg, ANCHOR, [alg.submissions[t_1.id], alg.submissions[q_items[1].id]])
    return persona


# ============================================================================
# (e) brand-new / summer student with no active courses
# ============================================================================

def empty() -> Persona:
    b = Builder("empty", SEED, "canvas.lakeshore.example", "America/Chicago", root_account_id=5, account_id=5,
                id_base=_ids(user=7710042))
    user = b.user("Morgan Sample", "Sample, Morgan", "msample", "morgan.sample@lakeshore.example",
                  b.at(2026, 9, 21, 14, 3, 9), uid=7710042)
    p = Persona(key="empty", title="New student, no active courses",
                description="Morgan Sample, a brand-new Lakeshore University account between terms: no active "
                            "enrollments, no planner items, no custom colors.",
                host="canvas.lakeshore.example", school="Lakeshore University", user=user, courses=[],
                captured_at=ANCHOR, anchor=ANCHOR, role_id_student=7,
                covers=["empty course list", "empty planner", "empty custom colors"])
    return p


# ============================================================================
# (f) large account: 12 courses, 150+ assignments, multi-page everything
# ============================================================================

LARGE_COURSES = [
    ("Organic Chemistry I", "CHEM 231", True, [("Problem Sets", 25, 1), ("Quizzes", 15, 0), ("Exams", 60, 0)]),
    ("Organic Chemistry Lab", "CHEM 233", False, [("Lab Notebooks", 0, 0), ("Lab Reports", 0, 0)]),
    ("Microeconomics", "ECON 201", True, [("Homework", 20, 2), ("Quizzes", 20, 1), ("Exams", 60, 0)]),
    ("Linear Algebra", "MATH 240", True, [("Homework", 30, 1), ("Exams", 70, 0)]),
    ("Data Structures", "CS 250", True, [("Programming Assignments", 50, 0), ("Labs", 20, 1), ("Exams", 30, 0)]),
    ("Spanish III", "SPAN 201", False, [("Tareas", 0, 0), ("Pruebas", 0, 0), ("Composiciones", 0, 0)]),
    ("Ethics in Technology", "PHIL 215", False, [("Reading Responses", 0, 1), ("Papers", 0, 0)]),
    ("Honors Program Community", "HON 100", False, [("Check-ins", 0, 0)]),
    ("Undergraduate Research Seminar", "URS 190", False, [("Seminar Reflections", 0, 0)]),
    ("Residence Life: Maple Hall", "RL-MAPLE", False, [("Floor Meetings", 0, 0)]),
    ("Library Research Skills", "LIB 101", False, [("Modules", 0, 0)]),
    ("Career Readiness Bootcamp", "CAR 100", False, [("Milestones", 0, 0)]),
]


def large() -> Persona:
    b = Builder("large", SEED, "canvas.northfield.example", "America/Chicago", root_account_id=10, account_id=146,
                id_base=_ids(user=4833390, teacher=300400, term=231, course=52100, group=189000,
                             assignment=1210000, quiz=89000, submission=904200000, enrollment=7330000,
                             section=62000, event=3320000, topic=2560000, attachment=51300000, folder=775000))
    at = b.at
    user = b.user("Taylor Sample", "Sample, Taylor", "tsample", "taylor.sample@students.northfield.example",
                  at(2024, 8, 12, 10, 1, 1), uid=4833390)
    term = b.term("Fall 2026", at(2026, 8, 24), at(2026, 12, 19), at(2026, 2, 17, 10, 3, 41), )
    term.id = 231
    created = at(2026, 4, 2, 11, 20, 5)
    rng = b.rng
    courses = []
    colors = {}
    first_monday = date(2026, 8, 24)
    for ci, (name, code, weighted, groups) in enumerate(LARGE_COURSES):
        t = b.teacher(["Sky", "Harper", "Rowe", "Blair", "Ellis", "Morgan", "Sage", "Tatum", "Lane", "Remy",
                       "Arden", "Briar"][ci] + " " + ["Fenwick", "Ashby", "Colter", "Dunmore", "Everly", "Foxglove",
                                                      "Greyson", "Holloway", "Ivers", "Juniper", "Kestrel",
                                                      "Lowell"][ci])
        c = b.course(name, code, term, [t], created, apply_weights=weighted,
                     grading_standard_id=(0 if ci % 3 != 2 else None),
                     course_format=("on_campus" if ci < 7 else "online"))
        colors[f"course_{c.id}"] = CANVAS_PALETTE[ci % len(CANVAS_PALETTE)]
        gobjs = [b.group(c, gname, w, drop_lowest=dl) for gname, w, dl in groups]
        n_assign = 14 if ci < 7 else 11
        weekday = ci % 5
        for k in range(n_assign):
            g = gobjs[k % len(gobjs)]
            pts = [10, 20, 25, 50, 100][(k + ci) % 5] if "Exam" not in g.name else 100
            d = first_monday + timedelta(days=weekday + 7 * k + (ci % 2))
            due = b.on(d, 23, 59, 59) if k % 4 else b.on(d, 9, 0)
            quiz = g.name in ("Quizzes", "Pruebas") and k % 2 == 0
            types = ("on_paper",) if "Exam" in g.name else (("online_upload",) if k % 5 == 4 else ("online_text_entry",))
            title = f"{g.name.rstrip('s')} {k // len(gobjs) + 1}" if ci < 7 else f"{g.name} {k + 1}"
            if "Exam" in g.name:
                title = f"Exam {k // len(gobjs) + 1}"
            a = b.assignment(c, g, title, pts, due, quiz=quiz, types=types, description=("" if k % 3 else None))
            if d < date(2026, 9, 27):
                r = rng.random()
                if r < 0.05:
                    continue  # missing
                sc = round(pts * (0.72 + 0.28 * rng.random()) * 2) / 2
                sub = None if types == ("on_paper",) else due - timedelta(hours=rng.randint(1, 50))
                late = r > 0.93 and sub is not None
                if late:
                    sub = due + timedelta(hours=rng.randint(1, 20))
                b.grade(c, a, sc, submitted=sub, graded=due + timedelta(days=rng.randint(1, 4)),
                        deducted=(round(pts * 0.1, 2) if late else None))
        meet = [["MO", "WE"], None, None, None, None, None, None, None, None, None, None, ["WE"]][ci]
        if meet:
            b.series(c, f"{code} {'Lab' if 'Lab' in name else 'Class'}", meet, 8 + ci % 9, 0, 50, first_monday,
                     len(meet) * 16, f"Commons {100 + 10 * ci}")
        for j in range(6 if ci < 7 else 5):
            posted = at(2026, 9, 14, 9, 0) + timedelta(days=2 * j + (ci % 2), hours=ci)
            if posted <= ANCHOR:
                b.announce(c, f"{code} update {j + 1}", f"<p>Weekly note {j + 1} for {name}.</p>", posted,
                           read=(posted + timedelta(hours=6)) if j < 3 else None)
        courses.append(c)
    persona = Persona(
        key="large", title="Large account (12 courses)",
        description=f"Taylor Sample at Northfield State: 7 academic courses plus 5 community/program courses, "
                    f"{sum(len(c.assignments) for c in courses)} assignments, forcing multi-page planner and "
                    f"announcement responses and two context-code chunks (10 + 2).",
        host="canvas.northfield.example", school="Northfield State University", user=user, courses=courses,
        captured_at=ANCHOR, anchor=ANCHOR, role_id_student=19, custom_colors=colors,
        covers=["12 courses", "context_codes chunking (10 + 2)", "multi-page planner (bookmark pagination)",
                "multi-page announcements (numbered pagination)",
                "courses without a grading scheme (null letter grades)"])
    finalize(persona)
    return persona


ALL = {
    "flagship": flagship,
    "flagship-previous": flagship_previous,
    "finals": finals,
    "grading-periods": grading_periods,
    "empty": empty,
    "large": large,
}
