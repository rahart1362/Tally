"""fixtures/canvas/README.md builder (generated, so it always matches the tree)."""
from __future__ import annotations


def _size(out, prefix):
    files = [k for k in out.files if k.startswith(prefix)]
    return len(files), sum(len(out.files[k]) for k in files)


UNVERIFIED = [
    ("Key order of api_json `only:` prefixes (Course, Assignment, Submission, Term, CalendarEvent, Announcement)",
     "Rails serializes in table-column order; the order used matches the serializers' field lists and remembered "
     "real responses, not a live capture. JSON key order is not semantically significant."),
    ("`GET /api/v1/accounts/search`", "Not in the REST docs or open-source controllers. Shape observed live, "
     "unauthenticated, on 2026-09-26 (id int without the string-ids header, name, domain, distance, "
     "authentication_provider)."),
    ("Grading-period scope string `url:GET|/api/v1/courses/:course_id/grading_periods`",
     "Inherited UNVERIFIED from architecture section 3.3; the docs page lists it, but no scoped key was tested."),
    ("Announcement `ungraded_discussion_overrides` value (emitted as `[]`) and topic `permissions` values",
     "Field present in lib/api/v1/discussion_topics.rb; value shape for announcements not proven."),
    ("GradingPeriod `permissions` values for a student", "PermissionsSerializer -> rights_status; values assumed."),
    ("Submission `excused: null` on never-graded rows; negative `grader_id` (= -quiz_id) for auto-graded classic "
     "quizzes; quiz submission `body` text", "Recalled from real responses; not provable from the checked-out source."),
    ("Assignment `can_duplicate` and `muted` for a student caller", "Model methods not in the sparse checkout; "
     "values chosen conservatively (false for quizzes; muted only for unposted manual-post work)."),
    ("Planner `plannable` field sets for calendar events, announcements and quizzes",
     "Derived from the API_PLANNABLE_FIELDS / CALENDAR_PLANNABLE_FIELDS / GRADABLE_FIELDS slices."),
    ("Link header for an empty numbered collection (`last` = page 1)", "Folio edge case not traced."),
    ("Letter-grade assignment score rounding (points x grade_to_score, rounded to 2 dp)",
     "GradingStandard#grade_to_score is ported; the Assignment-level rounding is assumed."),
    ("`lock_explanation` wording and attachment `preview_url: null`", "Presentation strings; Canvadocs availability varies."),
    ("X-Request-Cost / X-Rate-Limit-Remaining values", "Synthetic, seeded; start at the 700.0 observed on "
     "2026-09-26 and decrease by each cost; no refill modelled."),
    ("Observer persona (g): enrollment row order and `observation_link_root_account_ids` content",
     "Derived from courses_controller.rb#courses_for_user / ObserverEnrollment.observed_enrollments_for_enrollments "
     "and user_observees_controller.rb; no live observer account was available."),
]

AMBIGUITIES = [
    ("Fractional seconds and non-UTC offsets", "canvas-lms config/initializers/json.rb (time_precision = 0) and "
     "config/initializers/time.rb (JsonTimeInUTC) make every Time in these REST responses UTC `Z` with no "
     "fraction; spec/apis/v1/courses_api_spec.rb asserts e.g. \"2011-01-01T07:00:00Z\". Persona data therefore "
     "uses only that form; offsets/fractions live in `scenarios/dates/iso8601-variants.json`, marked "
     "`canvas_emits: false`, for parser robustness (WP-B05)."),
    ("Mockup letters vs Canvas's default scheme", "93.4 is A- and 82.0 is B- on Canvas's default scheme, and 89.0 "
     "is B+. BIO 101, HIST 210 and ENG 101 therefore use course grading schemes (A >= 93; straight A/B/C/D; "
     "A- >= 88) so Canvas itself returns the mockup's A / B / A-. The schemes are listed per course in "
     "expected/grades/flagship.json."),
    ("Mockup overall 87.2%", "The mean of the five mockup course scores is 88.34, not 87.2. "
     "expected/grades/flagship.json reports the computed mean; the 87.2 in the mockup is not reproducible from "
     "its own course grades."),
    ("Mockup dates", "The mockup is dated Mon May 6; the prototype maps it to Mon Sep 28. Due dates follow the "
     "prototype (Problem Set 7 Thu, Chapter 6 Quiz Fri 8:00 AM, Lab Report 4 Sun, Essay 2 Oct 5) and the rest "
     "of the mockup by day offset (Final Draft +14 d, Problem Set 6 -6 d, Quiz 4 -11 d, Midterm -18 d)."),
    ("Mockup 'Upcoming Quiz Biology 101' vs 'Chapter 6 Quiz' (Psychology)", "Both exist: BIO 101 Quiz 5 is "
     "tomorrow 8:00 AM (locked until 7:00 AM); PSY 101 Chapter 6 Quiz is Fri 8:00 AM."),
    ("Total scores with grading periods", "Canvas returns computed_current_score even when "
     "totals_for_all_grading_periods_option is false; the fixture keeps Canvas's values and the client decides "
     "whether to show the all-periods total."),
    ("Parent observing two students at different schools", "Observation links are per root account, and the two "
     "observees' schools are separate Canvas instances, so persona (g) is one person with two logins (one "
     "observee each), not one login with two observees."),
    ("Calendar-event window", "TallyConfig defines no separate event window; the planner window (-14...+60 d) "
     "is used for calendar events too."),
    ("Class meetings as Canvas events", "O9 notes Canvas rarely has meeting times; the flagship still has weekly "
     "recurring events so the mockup's schedule and calendar screenshots are reproducible."),
    ("Ruby Array#sort instability in drop rules", "Exact ties are arbitrary in Canvas; the port breaks ties "
     "stably (ascending assignment id), matching canvas-lms JS specs; persona data avoids ties."),
    ("JS vs Ruby calculators", "The student grades page uses the JS calculator; the enrollment fields come from "
     "the Ruby one. They can differ by 0.01 (Ruby combines rounded grading-period scores: 60.84 vs 60.83 in "
     "tests/test_gradecalc.py). Parity targets the Ruby values within +/-0.01."),
    ("Architecture path `Tests/Fixtures/canvas/<endpoint>/<scenario>.json`", "This tree follows the owner's "
     "requested root `fixtures/canvas/` with the same `scenarios/<endpoint>/<scenario>.json` shape."),
]


def readme(manifest: dict, out) -> str:
    L = []
    w = L.append
    w("# Synthetic Canvas fixtures\n")
    w("> **Synthetic data.** Every person, school, course, domain (`*.example`) and grade here is fictional and "
      "generated by `tools/canvas-synth`. Nothing was recorded from a real Canvas account. "
      "`manifest.json` carries `\"synthetic\": true`.\n")
    w("These files are what Canvas's REST API returns to a **student** (and, in persona `parent-observer`, an "
      "observer) for the requests in architecture section 3.3, sent with "
      "`Accept: application/json+canvas-string-ids` (every id is a string). One file per request; each body has a "
      "`.headers.json` sidecar (`status`, `Content-Type`, `Link`, `X-Request-Cost`, `X-Rate-Limit-Remaining`). "
      "Bodies are compact JSON with Canvas's `\\u003c`/`\\u003e`/`\\u0026` escaping, byte for byte as Canvas "
      "would send them.\n")
    w("Regenerate (byte-identical):\n\n```sh\ncd tools/canvas-synth\npython3 -m canvas_synth generate --out "
      "../../fixtures/canvas\n```\n")
    w("Validation evidence: `tools/canvas-synth/VALIDATION.md`.\n")
    w("## Layout\n")
    w("| Path | Contents |\n|---|---|")
    for p, d in [("manifest.json", "route table (method + host + path + normalized query -> body + headers), "
                  "personas, scenarios, rebasing rule, provenance"),
                 ("personas/<key>/", "complete account per persona: profile, courses, assignment_groups/<course>, "
                  "grading_periods/<course>, planner_items[.pageN], calendar_events.chunkN[.pageN], "
                  "announcements.chunkN[.pageN], colors (+ observees for the observer)"),
                 ("scenarios/<endpoint>/<scenario>.json", "edge cases (section 3.3); grade scenarios have matching "
                  "courses/ and assignment_groups/ (and grading_periods/) files"),
                 ("errors/", "Canvas-shaped error bodies + index.json with sources"),
                 ("expected/grades/<persona>.json", "reference-calculator scores for the Swift grade-parity test"),
                 ("expected/digest/flagship.json", "ground-truth change digest, flagship-previous -> flagship"),
                 ("schemas/", "one JSON Schema per Canvas object ($comment cites the doc URL and canvas-lms file); "
                  "schemas/tally/ covers this tree's own metadata")]:
        w(f"| `{p}` | {d} |")
    w("")
    w("## Personas\n")
    w("All anchored at **2026-09-28T13:00:00Z** (Monday). `captured_at` is the instant each snapshot shows.\n")
    w("| Key | Who / what | Requests | Files | Bytes |\n|---|---|---|---|---|")
    for key, p in manifest["personas"].items():
        n, b = _size(out, f"personas/{key}/")
        w(f"| `{key}` | {p['description']} | {p['request_count']} | {n} | {b:,} |")
    n, b = _size(out, "scenarios/")
    w(f"\nScenarios: {len(manifest['scenarios'])} route sets, {n} files, {b:,} bytes.\n")
    w("## Using the route table\n")
    rm = manifest["route_matching"]
    w(f"- Key: {rm['key']}.\n- Query normalization: {rm['query_normalization']}\n"
      f"- Unmatched request: {rm['unmatched_request']}.\n"
      "- Pagination: follow `Link` `rel=\"next\"` verbatim until absent. Numbered collections (courses, "
      "assignment groups, announcements, grading periods, account search) also send `rel=\"last\"`; bookmarked "
      "ones (planner, calendar events) never do.\n")
    w("## Rebasing for demo mode\n")
    w(manifest["rebasing"]["rule"] + "\n")
    w("Reference implementation and tests: `tools/canvas-synth/canvas_synth/rebase.py`, "
      "`tools/canvas-synth/tests/test_rebase.py`.\n")
    w("## Grades\n")
    w("Every enrollment score (`computed_current_score`, `computed_final_score`, `current_period_computed_*`, "
      "letter grades) is produced by `tools/canvas-synth/canvas_synth/gradecalc.py`, a standalone port of "
      "canvas-lms `lib/grade_calculator.rb` (group sums, Kane-and-Kane drop-rule bisection, never_drop, weighted "
      "groups with scaling, weighted grading periods from stored rounded period scores, Ruby `Float#round` and "
      "`BigDecimal#round` semantics), `lib/effective_due_dates.rb` (period membership), and "
      "`app/models/grading_standard.rb` (letters). A second path recomputes every course from the fixture "
      "responses alone, as a client would, and must match (tests/test_fixture_parity.py).\n")
    w("**Caveat:** synthetic parity proves consistency with *our port* of Canvas's algorithm. It does not replace "
      "an owner-run recording against real Canvas (WP-B07).\n")
    w("## Provenance\n")
    w(f"- Docs: {manifest['provenance']['canvas_sources']['docs']}.\n"
      f"- Code: {manifest['provenance']['canvas_sources']['code']}. The public repository has had no commits "
      "since 2026-04-30; that is the newest source available.\n"
      "- Each `schemas/*.schema.json` `$comment` names its doc URL and serializer file.\n")
    w("## UNVERIFIED\n")
    w("| Item | Why |\n|---|---|")
    for a, b in UNVERIFIED:
        w(f"| {a} | {b} |")
    w("\n## Ambiguities and how they were resolved\n")
    w("| Question | Resolution |\n|---|---|")
    for a, b in AMBIGUITIES:
        w(f"| {a} | {b} |")
    w("")
    return "\n".join(L)
