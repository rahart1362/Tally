"""Schemas for Tally's own fixture metadata (not Canvas objects)."""
from __future__ import annotations

BASE = "https://schemas.tally.example/canvas/tally/"
N = lambda s: {"anyOf": [s, {"type": "null"}]}  # noqa: E731
NUM = {"type": "number"}
STR = {"type": "string"}
ID = {"type": "string", "pattern": "^-?[0-9]+$"}
TS = {"type": "string", "pattern": r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"}


def _s(name, body):
    out = {"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": BASE + f"{name}.schema.json",
           "title": name, "$comment": "Tally fixture metadata (tools/canvas-synth); not a Canvas object."}
    out.update(body)
    return out


GROUP_SIDE = {"type": "object", "additionalProperties": False, "required": ["score", "possible", "grade", "dropped_submission_ids"],
              "properties": {"score": NUM, "possible": NUM, "grade": N(NUM),
                             "dropped_submission_ids": {"type": "array", "items": ID}}}

COURSE = {
    "type": "object", "additionalProperties": False,
    "required": ["course_id", "course_code", "name", "apply_assignment_group_weights", "weighted_grading_periods",
                 "hide_final_grades", "visible_in_api", "grading_standard_id", "grading_scheme", "current_score",
                 "final_score", "current_grade", "final_grade", "unposted_current_score", "unposted_final_score",
                 "current_grading_period_id", "grading_periods", "assignment_groups",
                 "design_target_current_score", "notes"],
    "properties": {
        "course_id": ID, "course_code": STR, "name": STR, "apply_assignment_group_weights": {"type": "boolean"},
        "weighted_grading_periods": {"type": "boolean"}, "hide_final_grades": {"type": "boolean"},
        "visible_in_api": {"type": "boolean"}, "grading_standard_id": N(ID),
        "grading_scheme": N({"type": "array", "items": {"type": "array", "prefixItems": [STR, NUM],
                                                        "minItems": 2, "maxItems": 2}}),
        "current_score": N(NUM), "final_score": N(NUM), "current_grade": N(STR), "final_grade": N(STR),
        "unposted_current_score": N(NUM), "unposted_final_score": N(NUM), "current_grading_period_id": N(ID),
        "grading_periods": {"type": "array", "items": {"type": "object", "additionalProperties": False,
                                                       "required": ["id", "title", "weight", "current_score",
                                                                    "final_score", "current_grade", "final_grade"],
                                                       "properties": {"id": ID, "title": STR, "weight": N(NUM),
                                                                      "current_score": N(NUM), "final_score": N(NUM),
                                                                      "current_grade": N(STR), "final_grade": N(STR)}}},
        "assignment_groups": {"type": "array", "items": {
            "type": "object", "additionalProperties": False,
            "required": ["id", "name", "group_weight", "current", "final"],
            "properties": {"id": ID, "name": STR, "group_weight": NUM, "current": GROUP_SIDE, "final": GROUP_SIDE}}},
        "design_target_current_score": N(NUM), "notes": N(STR)}}


def tool_schemas() -> dict:
    S = {}
    S["ExpectedGrades"] = _s("ExpectedGrades", {
        "type": "object", "additionalProperties": False,
        "required": ["persona", "synthetic", "captured_at", "tolerance", "calculator", "parity_rule", "caveat",
                     "courses", "tally_overall"],
        "properties": {"persona": STR, "synthetic": {"const": True}, "captured_at": TS, "tolerance": NUM,
                       "calculator": STR, "parity_rule": STR, "caveat": STR,
                       "courses": {"type": "array", "items": COURSE},
                       "tally_overall": {"type": "object", "required": ["definition", "courses_counted",
                                                                        "mean_current_score"],
                                         "additionalProperties": False,
                                         "properties": {"definition": STR, "courses_counted": {"type": "integer"},
                                                        "mean_current_score": N(NUM)}}}})
    S["ExpectedScenarioGrades"] = _s("ExpectedScenarioGrades", {
        "type": "object", "additionalProperties": False,
        "required": ["synthetic", "tolerance", "captured_at", "calculator", "scenarios"],
        "properties": {"synthetic": {"const": True}, "tolerance": NUM, "captured_at": TS, "calculator": STR,
                       "scenarios": {"type": "object", "additionalProperties": COURSE}}})
    S["Digest"] = _s("Digest", {
        "type": "object", "additionalProperties": False,
        "required": ["synthetic", "previous", "current", "note", "changes"],
        "properties": {"synthetic": {"const": True}, "note": STR,
                       "previous": {"type": "object", "required": ["persona", "captured_at"]},
                       "current": {"type": "object", "required": ["persona", "captured_at"]},
                       "changes": {"type": "array", "minItems": 1, "items": {
                           "type": "object", "required": ["kind", "course_id"],
                           "properties": {"kind": {"enum": ["course_score_changed", "new_assignment",
                                                            "due_date_changed", "newly_graded", "score_changed",
                                                            "submitted", "new_announcement"]},
                                          "course_id": ID}}}}})
    route = {"type": "object", "additionalProperties": False,
             "required": ["endpoint", "method", "host", "path", "query", "query_match", "status", "body", "headers"],
             "properties": {"endpoint": STR, "method": {"const": "GET"}, "host": STR, "path": {"type": "string", "pattern": "^/api/v1/"},
                            "query": STR, "query_match": STR, "status": {"type": "integer"}, "body": STR,
                            "headers": STR, "note": STR, "body_shared_with": STR}}
    S["Manifest"] = _s("Manifest", {
        "type": "object",
        "required": ["synthetic", "provenance", "anchor", "rebasing", "request_headers", "route_matching",
                     "personas", "scenarios", "expected"],
        "properties": {
            "synthetic": {"const": True}, "anchor": TS,
            "personas": {"type": "object", "additionalProperties": {
                "type": "object", "required": ["key", "title", "description", "synthetic"],
                "properties": {"synthetic": {"const": True}, "routes": {"type": "array", "items": route},
                               "accounts": {"type": "array", "items": {
                                   "type": "object", "required": ["host", "routes"],
                                   "properties": {"routes": {"type": "array", "items": route}}}}}}},
            "scenarios": {"type": "array", "items": {
                "type": "object", "required": ["id", "description", "covers", "canvas_emits", "routes"],
                "properties": {"routes": {"type": "array", "items": route}, "canvas_emits": {"type": "boolean"}}}}}})
    S["ErrorsIndex"] = _s("ErrorsIndex", {
        "type": "object", "required": ["synthetic", "errors"],
        "properties": {"synthetic": {"const": True}, "errors": {"type": "array", "items": {
            "type": "object", "additionalProperties": False, "required": ["file", "status", "description", "source"],
            "properties": {"file": STR, "status": {"type": "integer"}, "description": STR, "source": STR}}}}})
    S["DateVariants"] = _s("DateVariants", {
        "type": "object", "required": ["synthetic", "instant_utc", "note", "values"],
        "properties": {"synthetic": {"const": True}, "values": {"type": "array", "items": {
            "type": "object", "required": ["form", "value", "canvas_emits"],
            "properties": {"form": STR, "value": STR, "canvas_emits": {"type": "boolean"}, "source": STR}}}}})
    return S
