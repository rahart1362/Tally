"""Request/response emission: pagination, Link headers, rate-limit headers,
route table entries. Everything goes into an in-memory ``Out`` first so the
whole tree can be written (or compared) atomically and deterministically.
"""
from __future__ import annotations

import base64
import json
from datetime import datetime, timedelta
from urllib.parse import quote_plus, urlsplit, parse_qsl

from .jsonfmt import canvas_json, pretty_json, recursively_stringify_ids, stringify_ids
from .prng import Rng
from .tz import iso_z, local_to_utc, utc_to_local

JSON_CT = "application/json; charset=utf-8"
VOLATILE_PARAMS = {"start_date", "end_date"}


class Out:
    def __init__(self):
        self.files: dict[str, bytes] = {}

    def put(self, rel: str, data: bytes):
        if rel in self.files and self.files[rel] != data:
            raise RuntimeError(f"conflicting content for {rel}")
        self.files[rel] = data

    def json(self, rel: str, obj):
        self.put(rel, pretty_json(obj))


# ----------------------------------------------------------------------------
# Query helpers
# ----------------------------------------------------------------------------

def rails_to_query(params: list[tuple[str, str]]) -> str:
    """ActiveSupport Hash#to_query as used by Api.build_links_hash: array
    params keep their order inside one piece; pieces are sorted."""
    groups: dict[str, list[str]] = {}
    order = []
    for k, v in params:
        if k not in groups:
            groups[k] = []
            order.append(k)
        groups[k].append(v)
    pieces = []
    for k in order:
        vals = groups[k]
        if k.endswith("[]"):
            pieces.append("&".join(f"{quote_plus(k)}={quote_plus(v)}" for v in vals))
        else:
            pieces.append(f"{quote_plus(k)}={quote_plus(vals[-1])}")
    return "&".join(sorted(pieces))


def normalize_query(params: list[tuple[str, str]]) -> str:
    """Route-table normalization: percent-decoded pairs sorted by (key, value),
    joined as ``k=v`` with ``&``; no re-encoding."""
    return "&".join(f"{k}={v}" for k, v in sorted(params))


def match_query(params: list[tuple[str, str]]) -> str:
    return "&".join(f"{k}={'*' if k in VOLATILE_PARAMS else v}" for k, v in sorted(params))


def parse_url(url: str):
    u = urlsplit(url)
    return u.scheme, u.netloc, u.path, parse_qsl(u.query, keep_blank_values=True)


def link_header(links: list[tuple[str, str]]) -> str:
    order = ["current", "next", "prev", "first", "last"]
    d = dict(links)
    return ",".join(f'<{d[k]}>; rel="{k}"' for k in order if k in d)


def page_url(base: str, params: list[tuple[str, str]], page, per_page: int) -> str:
    q = rails_to_query([(k, v) for k, v in params if k not in ("page", "per_page")])
    return f"{base}?{q + '&' if q else ''}page={page}&per_page={per_page}"


def bookmark(key) -> str:
    raw = json.dumps(key, separators=(",", ":")).encode()
    return "bookmark:" + base64.urlsafe_b64encode(raw).decode().rstrip("=")


# ----------------------------------------------------------------------------
# Paginators -> list of (params, items, link)
# ----------------------------------------------------------------------------

def paginate_ordinal(items: list, base: str, params: list, per_page: int, *, with_last: bool = True):
    total_pages = max(1, -(-len(items) // per_page))
    pages = []
    for n in range(1, total_pages + 1):
        chunk = items[(n - 1) * per_page: n * per_page]
        links = [("current", page_url(base, params, n, per_page))]
        if n < total_pages:
            links.append(("next", page_url(base, params, n + 1, per_page)))
        if n > 1:
            links.append(("prev", page_url(base, params, n - 1, per_page)))
        links.append(("first", page_url(base, params, 1, per_page)))
        if with_last:
            links.append(("last", page_url(base, params, total_pages, per_page)))
        req = list(params) if n == 1 else [p for p in params if p[0] != "page"] + [("page", str(n))]
        pages.append((req, chunk, link_header(links)))
    return pages


def paginate_bookmark(items: list, keys: list, base: str, params: list, per_page: int):
    """BookmarkedCollection: current/next/first, never last."""
    total_pages = max(1, -(-len(items) // per_page))
    pages = []
    cur = "first"
    for n in range(total_pages):
        chunk = items[n * per_page:(n + 1) * per_page]
        links = [("current", page_url(base, params, cur, per_page))]
        nxt = None
        if n + 1 < total_pages:
            nxt = bookmark(keys[(n + 1) * per_page - 1])
            links.append(("next", page_url(base, params, nxt, per_page)))
        links.append(("first", page_url(base, params, "first", per_page)))
        req = list(params) if n == 0 else [p for p in params if p[0] != "page"] + [("page", cur)]
        pages.append((req, chunk, link_header(links)))
        cur = nxt
    return pages


# ----------------------------------------------------------------------------
# Rate-limit accounting (app/middleware/request_throttle.rb)
# ----------------------------------------------------------------------------

class Quota:
    """Leaky-bucket view as the client sees it: X-Request-Cost is charged
    per request and X-Rate-Limit-Remaining reports what is left (starting at
    the 700.0 observed on hosted Canvas on 2026-09-26). Refill over time is
    ignored, which is conservative."""

    COST = {"profile": (0.02, 0.08), "observees": (0.02, 0.08), "courses": (0.4, 1.6),
            "assignment_groups": (0.6, 3.5), "grading_periods": (0.03, 0.2), "planner_items": (1.2, 5.0),
            "calendar_events": (0.2, 1.1), "announcements": (0.2, 0.9), "colors": (0.01, 0.04),
            "accounts_search": (0.01, 0.05)}

    def __init__(self, rng: Rng, start: float = 700.0):
        self.rng = rng
        self.remaining = start

    def charge(self, endpoint: str) -> dict:
        lo, hi = self.COST.get(endpoint, (0.05, 0.5))
        cost = lo + (hi - lo) * self.rng.random()
        self.remaining -= cost
        return {"X-Request-Cost": repr(cost), "X-Rate-Limit-Remaining": repr(self.remaining)}


# ----------------------------------------------------------------------------
# Route recording
# ----------------------------------------------------------------------------

def headers_doc(status: int, headers: dict) -> dict:
    return {"status": status, "headers": headers}


def add_route(out: Out, routes: list, *, endpoint: str, method: str, host: str, path: str, params: list,
              body_rel: str, body: bytes, status: int = 200, headers: dict, note: str | None = None,
              content_type: str = JSON_CT):
    out.put(body_rel, body)
    hdr_rel = body_rel.rsplit(".", 1)[0] + ".headers.json"
    h = {"Content-Type": content_type}
    h.update(headers)
    out.json(hdr_rel, headers_doc(status, h))
    r = {"endpoint": endpoint, "method": method, "host": host, "path": path,
         "query": normalize_query(params), "query_match": match_query(params),
         "status": status, "body": body_rel, "headers": hdr_rel}
    if note:
        r["note"] = note
    routes.append(r)
    return r


def canvas_body(obj, stringify=True) -> bytes:
    if stringify:
        recursively_stringify_ids(obj)
    return canvas_json(obj)
