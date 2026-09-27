"""JSON encoders.

``canvas_json`` reproduces Canvas's wire format: compact separators, UTF-8,
and ActiveSupport/Oj(:rails, escape_mode :xss_safe) escaping of ``<``, ``>``
and ``&`` as ``\\u003c``/``\\u003e``/``\\u0026`` plus U+2028/U+2029
(canvas-lms config/initializers/json.rb). Floats use the shortest round-trip
repr, which matches Ruby's Float#to_s for the magnitudes used here.

``StringifyIds`` is a port of canvas-lms gems/stringify_ids/lib/stringify_ids.rb:
with ``Accept: application/json+canvas-string-ids`` every Integer value under
a key matching ``(^|_)id$`` becomes a string, and every Integer inside an
array under a key matching ``(^|_)ids$``. Nothing else is touched.
"""
from __future__ import annotations

import json
import re

_ID_KEY = re.compile(r"(^|_)id$", re.I)
_IDS_KEY = re.compile(r"(^|_)ids$", re.I)


def stringify_id(v):
    if isinstance(v, bool):
        return v
    return str(v) if isinstance(v, int) else v


def stringify_ids(h: dict) -> dict:
    """Non-recursive (Canvas::APISerialization#stringify!)."""
    for k in list(h.keys()):
        if _ID_KEY.search(k):
            h[k] = stringify_id(h[k])
        elif _IDS_KEY.search(k) and isinstance(h[k], list):
            h[k] = [stringify_id(x) for x in h[k]]
    return h


def recursively_stringify_ids(v):
    if isinstance(v, dict):
        stringify_ids(v)
        for x in v.values():
            if isinstance(x, (dict, list)):
                recursively_stringify_ids(x)
    elif isinstance(v, list):
        for x in v:
            if isinstance(x, (dict, list)):
                recursively_stringify_ids(x)
    return v


def canvas_json(obj) -> bytes:
    s = json.dumps(obj, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    s = (s.replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")
          .replace("\u2028", "\\u2028").replace("\u2029", "\\u2029"))
    return s.encode("utf-8")


def pretty_json(obj) -> bytes:
    return (json.dumps(obj, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")
