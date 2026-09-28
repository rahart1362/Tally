"""Deterministic time helpers (stdlib only, no tz database dependency).

Only the US zones the personas use are supported. US DST rules since 2007:
DST starts the second Sunday of March at 02:00 local standard time and ends
the first Sunday of November at 02:00 local daylight time.

Canvas REST serializes every Time/TimeWithZone as UTC with zero fractional
digits ("2026-09-28T13:00:00Z"): canvas-lms config/initializers/json.rb sets
``ActiveSupport::JSON::Encoding.time_precision = 0`` and
config/initializers/time.rb prepends ``JsonTimeInUTC`` to Time,
DateTime and ActiveSupport::TimeWithZone. :func:`iso_z` reproduces that.
"""
from __future__ import annotations

import re
from datetime import date, datetime, timedelta, timezone

UTC = timezone.utc

STANDARD_OFFSET_HOURS = {
    "America/New_York": -5,
    "America/Chicago": -6,
    "America/Denver": -7,
    "America/Los_Angeles": -8,
}


def _nth_weekday(year: int, month: int, weekday: int, n: int) -> date:
    d = date(year, month, 1)
    shift = (weekday - d.weekday()) % 7
    return d + timedelta(days=shift + 7 * (n - 1))


def _dst_bounds_utc(tzname: str, year: int):
    std = STANDARD_OFFSET_HOURS[tzname]
    start_local = datetime.combine(_nth_weekday(year, 3, 6, 2), datetime.min.time()).replace(hour=2)
    end_local = datetime.combine(_nth_weekday(year, 11, 6, 1), datetime.min.time()).replace(hour=2)
    start_utc = (start_local - timedelta(hours=std)).replace(tzinfo=UTC)
    end_utc = (end_local - timedelta(hours=std + 1)).replace(tzinfo=UTC)
    return start_utc, end_utc


def utc_offset(tzname: str, when_utc: datetime) -> timedelta:
    std = STANDARD_OFFSET_HOURS[tzname]
    start, end = _dst_bounds_utc(tzname, when_utc.year)
    if start <= when_utc < end:
        return timedelta(hours=std + 1)
    return timedelta(hours=std)


def local_to_utc(tzname: str, y: int, mo: int, d: int, h: int = 0, mi: int = 0, s: int = 0) -> datetime:
    naive = datetime(y, mo, d, h, mi, s)
    std = STANDARD_OFFSET_HOURS[tzname]
    # Try daylight first, then standard; pick the one that round-trips.
    for off in (std + 1, std):
        cand = (naive - timedelta(hours=off)).replace(tzinfo=UTC)
        if utc_offset(tzname, cand) == timedelta(hours=off):
            return cand
    return (naive - timedelta(hours=std)).replace(tzinfo=UTC)


def utc_to_local(tzname: str, when_utc: datetime) -> datetime:
    return (when_utc + utc_offset(tzname, when_utc)).replace(tzinfo=None)


def iso_z(dt: datetime | None) -> str | None:
    if dt is None:
        return None
    dt = dt.astimezone(UTC)
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def iso_offset(dt: datetime, tzname: str, fraction_digits: int = 0) -> str:
    """ISO 8601 with a numeric offset (used only by the parser-robustness
    scenario; Canvas REST does not emit this form for the endpoints Tally
    calls)."""
    local = utc_to_local(tzname, dt)
    off = utc_offset(tzname, dt)
    sign = "-" if off < timedelta(0) else "+"
    mins = abs(int(off.total_seconds())) // 60
    frac = ""
    if fraction_digits:
        frac = "." + f"{dt.microsecond:06d}"[:fraction_digits].ljust(fraction_digits, "0")
    return local.strftime("%Y-%m-%dT%H:%M:%S") + frac + f"{sign}{mins // 60:02d}:{mins % 60:02d}"


_ISO_RE = re.compile(
    r"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|[+-]\d{2}:?\d{2})$")


def parse_iso(s: str) -> datetime:
    m = _ISO_RE.match(s)
    if not m:
        raise ValueError(f"not an ISO 8601 timestamp: {s!r}")
    y, mo, d, h, mi, sec, frac, zone = m.groups()
    micro = int((frac or "0").ljust(6, "0")[:6])
    dt = datetime(int(y), int(mo), int(d), int(h), int(mi), int(sec), micro)
    if zone == "Z":
        off = timedelta(0)
    else:
        sign = -1 if zone[0] == "-" else 1
        zz = zone[1:].replace(":", "")
        off = sign * timedelta(hours=int(zz[:2]), minutes=int(zz[2:]))
    return (dt - off).replace(tzinfo=UTC)


def is_iso_timestamp(s) -> bool:
    return isinstance(s, str) and bool(_ISO_RE.match(s))


def local_midnight_utc(tzname: str, d: date) -> datetime:
    return local_to_utc(tzname, d.year, d.month, d.day)
