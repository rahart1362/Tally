"""Reference implementation of the demo-mode rebasing rule.

Rule (also in fixtures/canvas/README.md and manifest.json "rebasing"):

1. ``days = local_date(now, tz) - local_date(ANCHOR, tz)`` where ``tz`` is the
   persona's time zone (manifest ``personas.<key>.time_zone``) and ANCHOR is
   2026-09-28T13:00:00Z. Only whole days are shifted, so "today" in demo
   mode shows the anchor day's content and every class meeting keeps its
   local wall-clock time.
2. Every JSON string value that is a full ISO 8601 UTC timestamp
   (``YYYY-MM-DDTHH:MM:SSZ``) is converted to local wall-clock time in
   ``tz``, its date moved by ``days``, and converted back to UTC (so 11:59 pm
   stays 11:59 pm across a DST change).
3. Every value that is exactly a date (``YYYY-MM-DD``, e.g. ``all_day_date``)
   moves by ``days``.
4. Nothing else changes: ids, URLs (including ``Link`` headers and bookmark
   tokens), durations such as ``seconds_late`` and all scores stay as they
   are. Route matching treats start_date/end_date as wildcards, so rebased
   request windows still match.
Durations derived from "now" (``seconds_late``, ``missing``, ``locked_for_user``)
stay frozen at the anchor; they remain consistent because every timestamp
moves by the same local-day offset.
"""
from __future__ import annotations

import re
from datetime import date, datetime, timedelta

from .tz import UTC, iso_z, local_to_utc, parse_iso, utc_to_local

TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
ANCHOR = datetime(2026, 9, 28, 13, 0, 0, tzinfo=UTC)


def day_offset(now: datetime, tz: str, anchor: datetime = ANCHOR) -> int:
    return (utc_to_local(tz, now).date() - utc_to_local(tz, anchor).date()).days


def shift_timestamp(s: str, days: int, tz: str) -> str:
    local = utc_to_local(tz, parse_iso(s)) + timedelta(days=days)
    return iso_z(local_to_utc(tz, local.year, local.month, local.day, local.hour, local.minute, local.second))


def rebase(value, days: int, tz: str):
    if isinstance(value, str):
        if TS_RE.match(value):
            return shift_timestamp(value, days, tz)
        if DATE_RE.match(value):
            return (date.fromisoformat(value) + timedelta(days=days)).isoformat()
        return value
    if isinstance(value, list):
        return [rebase(v, days, tz) for v in value]
    if isinstance(value, dict):
        return {k: rebase(v, days, tz) for k, v in value.items()}
    return value
