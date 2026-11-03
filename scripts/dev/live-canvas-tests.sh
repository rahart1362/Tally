#!/usr/bin/env bash
# LIVE-1 (docs/pmo/reviews/live1-report.md, canvas-e2e/PLAN-live-testing.md): runs the opt-in
# TallyLiveCanvasTests target against a real, local Canvas LMS (~/canvas-e2e/RUNBOOK.md), in
# the same pinned Swift 6.4 container the Makefile's core-* targets use, but with
# `--network host` (instead of core-test's `--network none`) so it can reach Canvas on
# 127.0.0.1:8790, and with the whole worktree mounted (not just packages/TallyCore) so the
# container's `127.0.0.1` is the host's.
#
# Never prints or commits a token: this script only hands the *path* to each token file to the
# container as an environment variable; TallyLiveCanvasTests (LiveCanvasEnvironment.swift) reads
# the file's contents itself and never logs them. Canvas itself is never started, stopped, or
# reconfigured here -- only read-only API calls happen once the tests run.
#
# Usage: scripts/dev/live-canvas-tests.sh [--refresh-tokens]
#   --refresh-tokens  mint fresh student/observer tokens first (~/canvas-e2e/tools/e2e_oauth.py),
#                      since a public-client Canvas access token lives 120 minutes
#                      (RUNBOOK.md finding 2) and a long edit/CI gap can outlive one.
#
# Item 3 (LIVE-FIX-2/LIVE-3): the conditional-GET cache (`TALLY_LIVE_ETAG_CACHE_FILE`) lives at
# $REPO_ROOT/.build-live-etag-cache/cache.json -- a real file on the host (the whole worktree is
# bind-mounted read-write below), so running this script twice in a row shows real 304s on the
# second run. Plain JSON, never sealed (test-only scratch; the shipping store is sealed,
# `TallyStore`'s `SealedETagStore`). Git-ignored like every other `.build-*/` scratch directory
# (rule 1); delete it to start the cache fresh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CANVAS_E2E_DIR="${CANVAS_E2E_DIR:-$HOME/canvas-e2e}"
CANVAS_BASE_URL="${TALLY_LIVE_CANVAS_URL:-http://127.0.0.1:8790}"
STUDENT_TOKEN_FILE="$CANVAS_E2E_DIR/secrets/student-token"
OBSERVER_TOKEN_FILE="$CANVAS_E2E_DIR/secrets/observer-token"
ETAG_CACHE_DIR="$REPO_ROOT/.build-live-etag-cache"
CONTAINER="${CONTAINER:-podman}"

# Single source of truth for the pinned image: read it out of the Makefile instead of
# duplicating the digest here (it is bumped there, not here).
SWIFT_IMAGE="$(grep -m1 '^SWIFT_IMAGE' "$REPO_ROOT/Makefile" | sed -E 's/^SWIFT_IMAGE\s*\?=\s*//; s/\s*#.*$//')"

if [[ "${1:-}" == "--refresh-tokens" ]]; then
    echo "Refreshing student and observer tokens (e2e_oauth.py) ..." >&2
    python3 "$CANVAS_E2E_DIR/tools/e2e_oauth.py" --persona student
    python3 "$CANVAS_E2E_DIR/tools/e2e_oauth.py" --persona observer
fi

if ! curl -fsS -m 5 "$CANVAS_BASE_URL/health_check" > /dev/null; then
    echo "error: Canvas is not reachable at $CANVAS_BASE_URL/health_check." >&2
    echo "This script never starts/stops Canvas; bring it up yourself (RUNBOOK.md) first." >&2
    exit 1
fi
test -r "$STUDENT_TOKEN_FILE" || { echo "error: no student token at $STUDENT_TOKEN_FILE" >&2; exit 1; }

mkdir -p "$ETAG_CACHE_DIR"

ENV_ARGS=(-e "TALLY_LIVE_CANVAS_URL=$CANVAS_BASE_URL" -e "TALLY_LIVE_TOKEN_FILE=/canvas-e2e-secrets/student-token"
          -e "TALLY_LIVE_ETAG_CACHE_FILE=/repo/.build-live-etag-cache/cache.json")
MOUNT_ARGS=(-v "$STUDENT_TOKEN_FILE:/canvas-e2e-secrets/student-token:ro,Z")
if [[ -r "$OBSERVER_TOKEN_FILE" ]]; then
    ENV_ARGS+=(-e "TALLY_LIVE_OBSERVER_TOKEN_FILE=/canvas-e2e-secrets/observer-token")
    MOUNT_ARGS+=(-v "$OBSERVER_TOKEN_FILE:/canvas-e2e-secrets/observer-token:ro,Z")
else
    echo "note: no observer token at $OBSERVER_TOKEN_FILE -- the observer-path test (assertion 4) will be skipped." >&2
fi

echo "Resolving TallyCore's SwiftPM dependencies ..." >&2
"$CONTAINER" run --rm -v "$REPO_ROOT:/repo:Z" -w /repo/packages/TallyCore "$SWIFT_IMAGE" swift package resolve

echo "Running TallyLiveCanvasTests against $CANVAS_BASE_URL ..." >&2
"$CONTAINER" run --rm --network host \
    "${ENV_ARGS[@]}" "${MOUNT_ARGS[@]}" \
    -v "$REPO_ROOT:/repo:Z" -w /repo/packages/TallyCore \
    "$SWIFT_IMAGE" swift test --filter TallyLiveCanvasTests
