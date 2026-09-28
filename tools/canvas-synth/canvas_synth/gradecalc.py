"""Reference grade calculator: a standalone Python port of Canvas's server-side
grade calculation, i.e. the code that produces the enrollment fields
``computed_current_score`` / ``computed_final_score`` and the grading-period
scores returned by ``GET /api/v1/courses?include[]=total_scores``.

Ported from instructure/canvas-lms @ 1c9f0bb8013ed69c4f2efe11fd483025469b7e6c
(master, 2026-04-30; the latest public commit on 2026-09-26):

* ``lib/grade_calculator.rb``           -- create_group_sums, drop_assignments,
  keep_helper, big_f, estimate_q_high, calculate_total_from_group_scores,
  calculate_total_from_weighted_grading_periods, scale_and_round_scores,
  ignore_submission?
* ``lib/effective_due_dates.rb``        -- grading-period membership
  (``start_date < due_at <= end_date``; no due date -> last period)
* ``app/models/grading_period.rb``      -- in_date_range? / current?
* ``app/models/grading_standard.rb``    -- score_to_grade, grade_to_score,
  default_grading_scheme
* ``app/models/assignment_group.rb``    -- rules_hash

Numeric semantics follow the Ruby code, because they decide the last digit:

* group grade and the points-weighted course grade use BigDecimal and
  ``BigDecimal#round(2)`` (ROUND_HALF_UP on the decimal value);
* the percent-weighted course grade and weighted-grading-period totals use
  ``Float#round(2)``, which is **not** Python's ``round`` (see
  :func:`ruby_float_round`; canvas-lms spec "calculates the grade without
  floating point calculation errors" expects 93.825 -> 93.83);
* weighted grading periods combine the *stored, already rounded* period
  scores, exactly like ``apply_grading_period_weights_to_scores``.

Deliberate deviation: Ruby's ``Array#sort`` is not stable, so exact ties in
the drop-rule bisection are resolved arbitrarily by Canvas. This port uses a
stable sort (ties keep ascending assignment-id order), which matches the
canvas-lms JS calculator specs for tied cases. Synthetic personas avoid ties.

Input is plain dicts so the Swift parity test and the unit tests can reuse the
same data shape. Stdlib only.
"""
from __future__ import annotations

import math
from decimal import Decimal, ROUND_HALF_UP, localcontext
from fractions import Fraction
from typing import Any, Iterable

# ----------------------------------------------------------------------------
# Numeric helpers (Ruby semantics)
# ----------------------------------------------------------------------------

_DBL_DIG = 15


def _c_trunc_div(a: int, b: int) -> int:
    """C integer division (truncates toward zero)."""
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


def _c_round(x: float) -> float:
    """C ``round()``: half away from zero."""
    ax = abs(x)
    f = math.floor(ax)
    if ax - f >= 0.5:
        f += 1.0
    return math.copysign(f, x)


def ruby_float_round(number: float, ndigits: int = 2) -> float:
    """Port of Ruby's ``Float#round(ndigits)`` for ndigits in 1..14
    (numeric.c: flo_round -> rb_float_round -> round_half_up)."""
    number = float(number)
    if number == 0.0:
        return number
    _, binexp = math.frexp(number)
    float_dig = _DBL_DIG + 2
    # float_round_overflow
    if ndigits >= float_dig - (_c_trunc_div(binexp, 4) if binexp > 0 else _c_trunc_div(binexp, 3) - 1):
        return number
    # float_round_underflow
    if number > 0.0 and ndigits < -(_c_trunc_div(binexp, 3) + 1 if binexp > 0 else _c_trunc_div(binexp, 4)):
        return 0.0
    s = 10.0 ** ndigits
    f = _c_round(number * s)
    if number > 0:
        if (f + 0.5) / s <= number:
            f += 1
    else:
        if (f - 0.5) / s >= number:
            f -= 1
    return f / s


def to_d(x: Any) -> Decimal:
    """Ruby ``Numeric#to_d`` / ``BigDecimal(x)`` for the values Canvas stores:
    floats convert via their shortest round-trip representation."""
    if isinstance(x, Decimal):
        return x
    if isinstance(x, bool):
        raise TypeError("bool is not a number")
    if isinstance(x, int):
        return Decimal(x)
    if isinstance(x, Fraction):
        return Decimal(x.numerator) / Decimal(x.denominator)
    return Decimal(repr(float(x)))


def bigdecimal_round2(x: Decimal) -> Decimal:
    return x.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def _frac(x: Any) -> Fraction:
    if isinstance(x, Fraction):
        return x
    if isinstance(x, Decimal):
        return Fraction(x)
    if isinstance(x, int):
        return Fraction(x)
    return Fraction(to_d(x))


# ----------------------------------------------------------------------------
# Grading standards (app/models/grading_standard.rb)
# ----------------------------------------------------------------------------

DEFAULT_GRADING_SCHEME = [
    ("A", 0.94), ("A-", 0.90), ("B+", 0.87), ("B", 0.84), ("B-", 0.80),
    ("C+", 0.77), ("C", 0.74), ("C-", 0.70), ("D+", 0.67), ("D", 0.64),
    ("D-", 0.61), ("F", 0.0),
]


def _ordered_scheme(scheme):
    return sorted(scheme, key=lambda e: e[1], reverse=True)


def score_to_grade(score: float | None, scheme=None) -> str | None:
    """GradingStandard#score_to_grade (percentage-based schemes)."""
    if score is None:
        return None
    scheme = _ordered_scheme(scheme or DEFAULT_GRADING_SCHEME)
    s = to_d(0 if score < 0 else score)
    best = None
    best_val = None
    for name, lower in scheme:
        lb = to_d(lower)
        val = lb if s >= lb * 100 else -lb
        if best_val is None or val > best_val:  # max_by keeps the first max
            best, best_val = name, val
    return best


def grade_to_score(grade: str, scheme=None) -> float | None:
    """GradingStandard#grade_to_score -> percentage (0-100)."""
    scheme = _ordered_scheme(scheme or DEFAULT_GRADING_SCHEME)
    names = [n for n, _ in scheme]
    if grade not in names:
        return None
    idx = names.index(grade)
    if idx == 0:
        return 100.0
    prev = to_d(scheme[idx - 1][1])
    cur = to_d(scheme[idx][1])
    step = Decimal("1.0") if abs(cur - prev) >= Decimal("0.01") else Decimal("0.1")
    return float(prev * Decimal("100.0") - step)


# ----------------------------------------------------------------------------
# Grading periods (lib/effective_due_dates.rb, app/models/grading_period.rb)
# ----------------------------------------------------------------------------

def _minute(ts):
    return ts.replace(second=0, microsecond=0)


def grading_period_for_due_at(due_at, periods):
    """Return the id of the period an assignment belongs to, or None.

    ``periods``: iterable of dicts with ``id``, ``start_date``, ``end_date``
    (aware datetimes). Due dates are truncated to the minute; membership is
    ``start < due <= end``; an assignment without a due date belongs to the
    period with the latest end date."""
    periods = list(periods)
    if not periods:
        return None
    if due_at is None:
        return max(periods, key=lambda p: p["end_date"])["id"]
    d = _minute(due_at)
    for p in periods:
        if _minute(p["start_date"]) < d <= _minute(p["end_date"]):
            return p["id"]
    return None


def current_grading_period(periods, now):
    for p in periods:
        if _minute(p["start_date"]) < _minute(now) <= _minute(p["end_date"]):
            return p
    return None


# ----------------------------------------------------------------------------
# Drop rules (GradeCalculator#drop_assignments and helpers)
# ----------------------------------------------------------------------------

def _int_id(x) -> int:
    return int(x)


def drop_assignments(subs: list[dict], rules: dict) -> list[dict]:
    """``subs``: list of {'aid', 'score', 'total', ...}; returns kept items."""
    drop_lowest = int(rules.get("drop_lowest") or 0)
    drop_highest = int(rules.get("drop_highest") or 0)
    never_drop = {_int_id(i) for i in (rules.get("never_drop") or [])}
    if drop_lowest == 0 and drop_highest == 0:
        return subs

    cant_drop: list[dict] = []
    if never_drop:
        cant_drop = [s for s in subs if _int_id(s["aid"]) in never_drop]
        subs = [s for s in subs if _int_id(s["aid"]) not in never_drop]

    if not subs:
        return cant_drop

    if drop_lowest >= len(subs):
        drop_lowest = len(subs) - 1
    if drop_lowest + drop_highest >= len(subs):
        drop_highest = 0

    keep_highest_n = len(subs) - drop_lowest
    keep_lowest_n = keep_highest_n - drop_highest

    subs = sorted(subs, key=lambda s: _int_id(s["aid"]))

    if any(s["total"] > 0 for s in cant_drop + subs):
        kept = _drop_pointed(subs, cant_drop, keep_highest_n, keep_lowest_n)
    else:
        kept = _drop_unpointed(subs, keep_highest_n, keep_lowest_n)
    return kept + cant_drop


def _drop_unpointed(subs, keep_highest_n, keep_lowest_n):
    ordered = sorted(subs, key=lambda s: s["score"])
    kept = ordered[-keep_highest_n:] if keep_highest_n else []
    return kept[:keep_lowest_n]


def _drop_pointed(subs, cant_drop, n_highest, n_lowest):
    max_total = max(s["total"] for s in subs + cant_drop)
    kept = _keep_helper(subs, cant_drop, n_highest, max_total, "highest")
    return _keep_helper(kept, cant_drop, n_lowest, max_total, "lowest")


def _big_f(q, subs, cant_drop, keep, best: bool):
    rated = [(_frac(s["score"]) - q * _frac(s["total"]), s) for s in subs]
    # Stable sort; Ruby uses an unstable sort (ties are arbitrary in Canvas).
    rated.sort(key=lambda t: t[0], reverse=best)
    kept = rated[:keep]
    q_kept = sum((r for r, _ in kept), Fraction(0))
    q_cant = sum((_frac(s["score"]) - q * _frac(s["total"]) for s in cant_drop), Fraction(0))
    return q_kept + q_cant, [s for _, s in kept]


def _estimate_q_high(pointed, unpointed, grades):
    if unpointed:
        points_possible = sum((_frac(s["total"]) for s in pointed), Fraction(0))
        best_pointed = max(points_possible, sum((_frac(s["score"]) for s in pointed), Fraction(0)))
        unpointed_score = sum((_frac(s["score"]) for s in unpointed), Fraction(0))
        return (best_pointed + unpointed_score) / points_possible
    return grades[-1]


def _keep_helper(subs, cant_drop, keep, max_total, mode):
    if len(subs) <= keep:
        return subs
    both = subs + cant_drop
    unpointed = [s for s in both if s["total"] == 0]
    pointed = [s for s in both if s["total"] != 0]
    if not pointed and mode == "lowest":
        ordered = sorted(unpointed, key=lambda s: float(s["score"]))
        return ordered[-keep:] if keep else []
    grades = sorted(_frac(s["score"]) / _frac(s["total"]) for s in pointed)
    q_high = _estimate_q_high(pointed, unpointed, grades)
    q_low = grades[0]
    q_mid = (q_low + q_high) / 2
    best = mode == "highest"
    x, kept = _big_f(q_mid, subs, cant_drop, keep, best)
    threshold = Fraction(1) / (2 * keep * (_frac(max_total) ** 2))
    while not (q_high - q_low < threshold):
        if x < 0:
            q_high = q_mid
        else:
            q_low = q_mid
        q_mid = (q_low + q_high) / 2
        if q_mid == q_high or q_mid == q_low:
            break
        x, kept = _big_f(q_mid, subs, cant_drop, keep, best)
    return kept


# ----------------------------------------------------------------------------
# Group sums and totals
# ----------------------------------------------------------------------------

def _submission_counts(sub: dict | None, ignore_unposted: bool) -> dict | None:
    """GradeCalculator#ignore_submission?: with ignore_muted (posted scores),
    a missing or unposted submission is treated as absent."""
    if sub is None:
        return None
    if ignore_unposted and not sub.get("posted", False):
        return None
    return sub


def create_group_sums(course: dict, *, ignore_ungraded: bool, ignore_unposted: bool = True,
                      grading_period_id=None) -> list[dict]:
    assignments = [a for a in course["assignments"] if a.get("gradeable", True) and a.get("published", True)]
    if grading_period_id is not None:
        assignments = [a for a in assignments if str(a.get("grading_period_id")) == str(grading_period_id)]
    by_group: dict[str, list[dict]] = {}
    for a in assignments:
        by_group.setdefault(str(a["assignment_group_id"]), []).append(a)
    subs_by_aid = {str(s["assignment_id"]): s for s in course.get("submissions", [])}
    enrollment_completed = course.get("enrollment_completed", False)

    out = []
    for g in course["groups"]:
        items = []
        for a in by_group.get(str(g["id"]), []):
            s = _submission_counts(subs_by_aid.get(str(a["id"])), ignore_unposted)
            if ignore_ungraded and s is not None and s.get("workflow_state") == "pending_review":
                s = None
            items.append({
                "aid": a["id"],
                "sid": s["id"] if s else None,
                "has_submission": s is not None,
                "score": (s.get("score") if s else None),
                "total": to_d(a.get("points_possible") or 0),
                "excused": (bool(s.get("excused")) if s else None),
                "omit": bool(a.get("omit_from_final_grade", False)),
            })
        if enrollment_completed:
            items = [i for i in items if i["has_submission"]]
        if ignore_ungraded:
            items = [i for i in items if i["score"] is not None]
        items = [i for i in items if not i["excused"]]
        items = [i for i in items if not i["omit"]]
        for i in items:
            if i["score"] is None:
                i["score"] = 0
        kept = drop_assignments(items, g.get("rules") or {})
        kept_ids = {id(i) for i in kept}
        dropped = [i["sid"] for i in items if id(i) not in kept_ids and i["sid"] is not None]
        score = Decimal(0)
        possible = Decimal(0)
        for i in kept:
            score += to_d(i["score"])
            possible += to_d(i["total"])
        grade = None
        if possible > 0:
            with localcontext() as ctx:
                ctx.prec = 50
                grade = float(bigdecimal_round2(to_d(float(score)) / possible * 100))
        out.append({
            "id": g["id"],
            "score": score,
            "possible": possible,
            "weight": float(g.get("group_weight") or 0.0),
            "grade": grade,
            "dropped": dropped,
            "kept_assignment_ids": [i["aid"] for i in kept],
        })
    return out


def total_from_group_sums(group_sums: list[dict], weighting: str) -> dict:
    """GradeCalculator#calculate_total_from_group_scores."""
    dropped = []
    for gs in group_sums:
        for d in gs["dropped"]:
            if d not in dropped:
                dropped.append(d)
    with localcontext() as ctx:
        ctx.prec = 50
        if weighting == "percent":
            relevant = [gs for gs in group_sums if gs["possible"] != 0]
            final = Decimal(0)
            for gs in relevant:
                final += (gs["score"] / gs["possible"]) * to_d(gs["weight"])
            full_weight = 0.0
            for gs in relevant:
                full_weight += gs["weight"]
            if full_weight == 0:
                final_grade = None
            elif full_weight < 100:
                final_grade = final / to_d(full_weight) * Decimal(100)
            else:
                final_grade = final
            rounded = None if final_grade is None else ruby_float_round(float(final_grade), 2)
            return {"grade": rounded, "total": rounded, "dropped": dropped}
        total = Decimal(0)
        possible = Decimal(0)
        for gs in group_sums:
            total += gs["score"]
            possible += gs["possible"]
        if possible > 0:
            final_grade = to_d(float(total)) / possible * 100
            return {"grade": float(bigdecimal_round2(final_grade)), "total": float(total),
                    "possible": float(possible), "dropped": dropped}
        return {"grade": None, "total": float(total), "dropped": dropped}


def compute_scores(course: dict, *, grading_period_id=None, ignore_unposted: bool = True) -> dict:
    """Scores for one branch (course or one grading period; posted or
    unposted) *without* weighted-grading-period combination."""
    weighting = "percent" if course.get("apply_assignment_group_weights") else "points"
    cur = create_group_sums(course, ignore_ungraded=True, ignore_unposted=ignore_unposted,
                            grading_period_id=grading_period_id)
    fin = create_group_sums(course, ignore_ungraded=False, ignore_unposted=ignore_unposted,
                            grading_period_id=grading_period_id)
    return {
        "current": total_from_group_sums(cur, weighting),
        "final": total_from_group_sums(fin, weighting),
        "groups": {"current": cur, "final": fin},
    }


def combine_weighted_grading_periods(period_scores: list[dict], weights: dict) -> dict:
    """GradeCalculator#calculate_total_from_weighted_grading_periods.
    ``period_scores``: [{'id','current','final'}] with the stored (rounded)
    period scores; ``weights``: {period_id: weight or None}."""
    acc = {"current": {"full_weight": 0.0, "grade": 0.0}, "final": {"full_weight": 0.0, "grade": 0.0}}
    for ps in period_scores:
        w = weights.get(str(ps["id"]))
        w = 0.0 if w is None else float(w)
        acc["final"]["full_weight"] += w
        if ps["current"] is not None:
            acc["current"]["full_weight"] += w
        acc["current"]["grade"] += (ps["current"] if ps["current"] is not None else 0.0) * (w / 100.0)
        acc["final"]["grade"] += (ps["final"] if ps["final"] is not None else 0.0) * (w / 100.0)
    out = {}
    for kind in ("current", "final"):
        score = acc[kind]["grade"]
        full_weight = acc[kind]["full_weight"]
        if full_weight < 100:
            score = 0.0 if full_weight == 0 else (score * 100.0) / full_weight
        if abs(score) < 2.220446049250313e-16 and kind == "current" and all(ps["current"] is None for ps in period_scores):
            score = None
        out[kind] = None if score is None else ruby_float_round(score, 2)
    return out


def compute_enrollment_scores(course: dict, now=None) -> dict:
    """Everything GradeCalculator#compute_and_save_scores stores for one
    student enrollment: course scores (posted + unposted) and one score per
    grading period. ``course['grading_periods']`` is None or
    {'weighted': bool, 'periods': [{'id','weight','start_date','end_date', ...}]}.
    """
    gp = course.get("grading_periods")
    periods = (gp or {}).get("periods") or []
    result: dict[str, Any] = {"grading_periods": {}}
    for p in periods:
        posted = compute_scores(course, grading_period_id=p["id"], ignore_unposted=True)
        unposted = compute_scores(course, grading_period_id=p["id"], ignore_unposted=False)
        result["grading_periods"][str(p["id"])] = {
            "current_score": posted["current"]["grade"],
            "final_score": posted["final"]["grade"],
            "unposted_current_score": unposted["current"]["grade"],
            "unposted_final_score": unposted["final"]["grade"],
            "groups": posted["groups"],
        }
    weighted = bool(gp and gp.get("weighted") and periods)
    posted = compute_scores(course, ignore_unposted=True)
    unposted = compute_scores(course, ignore_unposted=False)
    if weighted:
        weights = {str(p["id"]): p.get("weight") for p in periods}
        rows = [{"id": pid, "current": v["current_score"], "final": v["final_score"]}
                for pid, v in result["grading_periods"].items()]
        combined = combine_weighted_grading_periods(rows, weights)
        # The hidden-scores branch also reads the *posted* period columns
        # (apply_grading_period_weights_to_scores uses score.current_score).
        result.update({
            "current_score": combined["current"], "final_score": combined["final"],
            "unposted_current_score": combined["current"], "unposted_final_score": combined["final"],
        })
    else:
        result.update({
            "current_score": posted["current"]["grade"], "final_score": posted["final"]["grade"],
            "unposted_current_score": unposted["current"]["grade"],
            "unposted_final_score": unposted["final"]["grade"],
        })
    result["weighted_grading_periods"] = weighted
    result["groups"] = posted["groups"]
    result["dropped"] = {"current": posted["current"]["dropped"], "final": posted["final"]["dropped"]}
    if now is not None and periods:
        cur = current_grading_period(periods, now)
        result["current_grading_period_id"] = None if cur is None else str(cur["id"])
    return result


def course_input_from_api(course_json: dict, assignment_groups_json: list[dict],
                          grading_periods_json: dict | None = None, student_id: str | None = None) -> dict:
    """Build calculator input from what a *client* receives (the fixtures),
    i.e. the path the Swift GradeEngine takes. For an observer response
    (``submission`` is an array) pass the observed ``student_id``."""
    assignments, submissions, groups = [], [], []
    for g in assignment_groups_json:
        groups.append({"id": g["id"], "group_weight": g.get("group_weight") or 0.0, "rules": g.get("rules") or {}})
        for a in g.get("assignments", []):
            sub_types = a.get("submission_types") or []
            gradeable = not ("not_graded" in sub_types or "wiki_page" in sub_types)
            s = a.get("submission")
            if isinstance(s, list):
                s = next((x for x in s if student_id is None or x.get("user_id") == student_id), None)
            gp_id = s.get("grading_period_id") if s else None
            assignments.append({
                "id": a["id"], "assignment_group_id": a["assignment_group_id"],
                "points_possible": a.get("points_possible"),
                "omit_from_final_grade": a.get("omit_from_final_grade", False),
                "gradeable": gradeable, "published": a.get("published", True),
                "grading_period_id": gp_id,
            })
            if s:
                submissions.append({
                    "id": s["id"], "assignment_id": a["id"],
                    "score": s.get("score"),
                    "excused": bool(s.get("excused")),
                    "posted": s.get("posted_at") is not None,
                    "workflow_state": s.get("workflow_state"),
                })
    gp = None
    if grading_periods_json and grading_periods_json.get("grading_periods"):
        from .tz import parse_iso
        gp = {"weighted": bool(course_json.get("has_weighted_grading_periods")),
              "periods": [{"id": p["id"], "weight": p.get("weight"),
                           "start_date": parse_iso(p["start_date"]), "end_date": parse_iso(p["end_date"])}
                          for p in grading_periods_json["grading_periods"]]}
    student_rows = [e for e in course_json.get("enrollments", []) if e.get("type") == "student"
                    and (student_id is None or e.get("user_id") == student_id)]
    return {
        "apply_assignment_group_weights": bool(course_json.get("apply_assignment_group_weights")),
        "groups": groups, "assignments": assignments, "submissions": submissions,
        "grading_periods": gp,
        "enrollment_completed": bool(student_rows) and all(e.get("enrollment_state") == "completed"
                                                           for e in student_rows),
    }


def iter_nonnull(values: Iterable):
    return [v for v in values if v is not None]
