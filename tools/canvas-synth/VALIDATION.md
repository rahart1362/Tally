# canvas-synth validation evidence

Run on 2026-09-26 on `wuzzyfuzzy` with rootless Podman. Everything below is pasted verbatim from the
terminal; nothing is paraphrased. Re-run with:

```sh
tools/canvas-synth/validate.sh                      # sections 1-5 below
podman run --rm -v "$PWD/tools/canvas-synth:/work/tools/canvas-synth:ro,Z" \
  -v "$PWD/fixtures/canvas:/work/fixtures/canvas:ro,Z" -w /work/tools/canvas-synth \
  docker.io/library/python:3.12-slim@sha256:44ff437bba879d4941b710a369a8f19266aea34b29002807f0c487fabc9eec9b \
  bash -c 'PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v'   # verbose test list
```

Pinned image: `docker.io/library/python:3.12-slim@sha256:44ff437bba879d4941b710a369a8f19266aea34b29002807f0c487fabc9eec9b`.
The generator is stdlib-only; `jsonschema==4.23.0` is installed in the container for validation only.

What each check proves:

| Check | Proves |
|---|---|
| Unit tests: `test_gradecalc.py` (33) | The reference calculator reproduces hand-computed results, cases mirrored from canvas-lms JS specs (`ui/shared/grading/__tests__/AssignmentGroupGradeCalculator{1,2}.test.js`, `CourseGradeCalculator{2,4}.test.js`) and Ruby specs (`spec/lib/grade_calculator_spec.rb`), including Ruby `Float#round` semantics and two documented JS-vs-Ruby divergences. |
| `test_fixture_parity.py` (7) | Recomputing every course **from the fixture files alone** (courses + assignment_groups + grading_periods, as the Swift GradeEngine will) reproduces every enrollment's `computed_current_score`, `computed_final_score` and `current_period_computed_current_score` (the test asserts the contract tolerance of 0.01 and, as a stricter self-check, a maximum absolute difference of exactly 0); hidden-total courses carry no `computed_*` keys; every id is a string; every `rel="next"` resolves to a route; every timestamp is Canvas's `...Z` form; the flagship matches the mockup; the digest has real changes. |
| `test_rebase.py` (3) | The demo-mode rebasing rule (local-day shift, DST-safe, ids/URLs untouched). |
| `test_determinism.py` (1) | Two generations with different `PYTHONHASHSEED` are byte-identical, and equal to the committed tree. |
| Schema validation | Every file under `fixtures/canvas` (369 of 370; README.md is prose) validates against its schema; the 27 schemas pass the 2020-12 metaschema. |
| Negative control | The validator is not vacuous: a numeric id, an invented field and a fractional-second timestamp are each rejected. |
| Double generation in container | Byte identity across two runs and against the tree generated on the host. |

**Scope of the parity claim.** Synthetic parity proves consistency with our port of Canvas's algorithm
(canvas-lms @ 1c9f0bb). It does not replace an owner-run recording against real Canvas (WP-B07).

## Full `validate.sh` run

```text
== environment
Python 3.12.14
image: docker.io/library/python:3.12-slim@sha256:44ff437bba879d4941b710a369a8f19266aea34b29002807f0c487fabc9eec9b
attrs==26.1.0
jsonschema==4.23.0
jsonschema-specifications==2025.9.1
referencing==0.37.0
rpds-py==2026.6.3

== 1. unit tests (calculator, rebase, determinism, client-side parity)
----------------------------------------------------------------------
Ran 44 tests in 6.887s

OK

== 2. schema validation of every file under fixtures/canvas
jsonschema 4.23.0; fixtures root: /work/fixtures/canvas
    27  (metaschema) JSON Schema 2020-12
     4  AccountSearchResult[]
     7  Announcement[]
    56  AssignmentGroup[]
     8  CalendarEvent[]
    31  Course[]
     6  CustomColors
     1  DateVariants
     1  Digest
    16  ErrorBody
     1  ErrorsIndex
     6  ExpectedGrades
     1  ExpectedScenarioGrades
     7  GradingPeriodIndex
   169  HeadersSidecar
     1  Manifest
     2  Observee[]
    13  PlannerItem[]
     8  Profile
     4  RateLimitText
validated files: 369; failures: 0; skipped (not JSON fixtures): ['README.md']

== 3. double generation inside the container vs the committed tree
wrote 370 files, 3518910 bytes, tree sha256 cfec83596d526bdb0fdacf59119bf37ee535f08bcf9d2873dee96926966c9828
wrote 370 files, 3518910 bytes, tree sha256 cfec83596d526bdb0fdacf59119bf37ee535f08bcf9d2873dee96926966c9828
committed: 370 files, 3518910 bytes, tree sha256 cfec83596d526bdb0fdacf59119bf37ee535f08bcf9d2873dee96926966c9828
run1 == run2: byte-identical
run1 == committed fixtures/canvas: byte-identical

== 4. negative control: three deliberate defects must be caught
validated files: 366; failures: 3; skipped (not JSON fixtures): ['README.md']
FAIL personas/flagship/courses.json: Course[]: {'id': 51845, 'name': 'Biology 101', 'account_id': '145', 'uuid': 'cuTtQ3JBrB1JYSz4oi6OB1OH7kQevswyDT3RWvJL', 'start_at': None, 'grading_standard_id': '4412', 'is_public': False, 'created_at': '2026-0 at []
FAIL personas/flagship/planner_items.page1.json: PlannerItem[]: '2026-09-14T13:00:00.000Z' does not match '^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$' at ['plannable_date']
FAIL personas/flagship/assignment_groups/51842.json: AssignmentGroup[]: Additional properties are not allowed ('grade_letter' was unexpected) at ['assignments', 0]
(validator exited non-zero as expected)

== 5. size
total bytes: 3518910
gzip -9 tar bytes: 285250
```

## Verbose unit-test list (same container image)

```text
test_two_generations_identical (test_determinism.Determinism.test_two_generations_identical) ... ok
test_every_route_file_exists_and_ids_are_strings (test_fixture_parity.Contract.test_every_route_file_exists_and_ids_are_strings) ... ok
test_link_next_chains_resolve_to_routes (test_fixture_parity.Contract.test_link_next_chains_resolve_to_routes) ... ok
test_timestamps_are_canvas_form (test_fixture_parity.Contract.test_timestamps_are_canvas_form) ... ok
test_client_side_recomputation_matches_enrollment_fields (test_fixture_parity.Parity.test_client_side_recomputation_matches_enrollment_fields)
Contract: +/-0.01. Self-consistency: the generator's fixtures must agree exactly. ... ok
test_digest_has_real_changes (test_fixture_parity.Parity.test_digest_has_real_changes) ... ok
test_expected_files_match_enrollments (test_fixture_parity.Parity.test_expected_files_match_enrollments) ... ok
test_flagship_matches_mockup (test_fixture_parity.Parity.test_flagship_matches_mockup) ... ok
test_hand_boundaries (test_gradecalc.GradingPeriodMembership.test_hand_boundaries) ... ok
test_hand_excused_unposted_counts_as_missing_in_final (test_gradecalc.Hand.test_hand_excused_unposted_counts_as_missing_in_final) ... ok
test_hand_points_two_groups (test_gradecalc.Hand.test_hand_points_two_groups) ... ok
test_hand_unposted_ignored_for_current_zero_for_final (test_gradecalc.Hand.test_hand_unposted_ignored_for_current_zero_for_final) ... ok
test_hand_weighted_grading_periods_scaled_current (test_gradecalc.Hand.test_hand_weighted_grading_periods_scaled_current) ... ok
test_hand_weighted_scaling_with_ungraded_group (test_gradecalc.Hand.test_hand_weighted_scaling_with_ungraded_group) ... ok
test_js_adds_scores_and_possible (test_gradecalc.JsAssignmentGroup.test_js_adds_scores_and_possible) ... ok
test_js_all_unpointed_drop_lowest (test_gradecalc.JsAssignmentGroup.test_js_all_unpointed_drop_lowest) ... ok
test_js_drop_highest (test_gradecalc.JsAssignmentGroup.test_js_drop_highest) ... ok
test_js_drop_lowest_1 (test_gradecalc.JsAssignmentGroup.test_js_drop_lowest_1) ... ok
test_js_drop_lowest_2_and_4 (test_gradecalc.JsAssignmentGroup.test_js_drop_lowest_2_and_4) ... ok
test_js_hidden_and_excused_and_pending (test_gradecalc.JsAssignmentGroup.test_js_hidden_and_excused_and_pending) ... ok
test_js_omit_from_final_grade (test_gradecalc.JsAssignmentGroup.test_js_omit_from_final_grade) ... ok
test_js_ridiculous_circumstances (test_gradecalc.JsAssignmentGroup.test_js_ridiculous_circumstances) ... ok
test_js_tie_drops_highest_id (test_gradecalc.JsAssignmentGroup.test_js_tie_drops_highest_id) ... ok
test_js_unpointed_scores_count (test_gradecalc.JsAssignmentGroup.test_js_unpointed_scores_count) ... ok
test_never_drop (test_gradecalc.JsAssignmentGroup.test_never_drop) ... ok
test_js_points (test_gradecalc.JsCourse.test_js_points) ... ok
test_js_vs_ruby_divergence_points_weighting (test_gradecalc.JsCourse.test_js_vs_ruby_divergence_points_weighting) ... ok
test_js_weighted_grading_periods (test_gradecalc.JsCourse.test_js_weighted_grading_periods) ... ok
test_js_weighted_variants (test_gradecalc.JsCourse.test_js_weighted_variants) ... ok
test_hand_ruby_float_round_differs_from_python (test_gradecalc.RubyRounding.test_hand_ruby_float_round_differs_from_python) ... ok
test_rb_computes_weighted_grade (test_gradecalc.RubySpec.test_rb_computes_weighted_grade) ... ok
test_rb_extra_credit (test_gradecalc.RubySpec.test_rb_extra_credit) ... ok
test_rb_float_error_percent (test_gradecalc.RubySpec.test_rb_float_error_percent) ... ok
test_rb_float_error_points (test_gradecalc.RubySpec.test_rb_float_error_points) ... ok
test_rb_irrational_weights (test_gradecalc.RubySpec.test_rb_irrational_weights) ... ok
test_rb_not_graded_assignment_ignored (test_gradecalc.RubySpec.test_rb_not_graded_assignment_ignored) ... ok
test_rb_total_weight_under_100 (test_gradecalc.RubySpec.test_rb_total_weight_under_100) ... ok
test_rb_weights_under_100_precision (test_gradecalc.RubySpec.test_rb_weights_under_100_precision) ... ok
test_hand_custom_schemes (test_gradecalc.Schemes.test_hand_custom_schemes) ... ok
test_hand_default_scheme_boundaries (test_gradecalc.Schemes.test_hand_default_scheme_boundaries) ... ok
test_hand_grade_to_score (test_gradecalc.Schemes.test_hand_grade_to_score) ... ok
test_dates_ids_urls_untouched_or_shifted (test_rebase.Rebase.test_dates_ids_urls_untouched_or_shifted) ... ok
test_day_offset_uses_local_date (test_rebase.Rebase.test_day_offset_uses_local_date) ... ok
test_wall_clock_preserved_across_dst (test_rebase.Rebase.test_wall_clock_preserved_across_dst) ... ok

----------------------------------------------------------------------
Ran 44 tests in 7.112s

OK
```
