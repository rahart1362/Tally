#!/usr/bin/env bash
# Reproducible validation run in a pinned container (rootless Podman).
# Usage: tools/canvas-synth/validate.sh   (from anywhere)
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
IMAGE="docker.io/library/python:3.12-slim@sha256:44ff437bba879d4941b710a369a8f19266aea34b29002807f0c487fabc9eec9b"
podman run --rm --network=host -v "$REPO/tools/canvas-synth:/work/tools/canvas-synth:ro,Z" \
  -v "$REPO/fixtures/canvas:/work/fixtures/canvas:ro,Z" -w /work/tools/canvas-synth "$IMAGE" bash -euo pipefail -c '
echo "== environment"; python3 --version; echo "image: '"$IMAGE"'"
pip install --quiet --disable-pip-version-check --root-user-action=ignore jsonschema==4.23.0 2>&1 | tail -1 || true
pip freeze | grep -E "^(jsonschema|referencing|rpds-py|attrs|jsonschema-specifications)=="
echo; echo "== 1. unit tests (calculator, rebase, determinism, client-side parity)"
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests 2>&1 | tail -4
echo; echo "== 2. schema validation of every file under fixtures/canvas"
PYTHONDONTWRITEBYTECODE=1 python3 validate.py /work/fixtures/canvas
echo; echo "== 3. double generation inside the container vs the committed tree"
cp -r /work/tools/canvas-synth /tmp/gen && cd /tmp/gen
PYTHONDONTWRITEBYTECODE=1 PYTHONHASHSEED=11 python3 -m canvas_synth generate --out /tmp/run1
PYTHONDONTWRITEBYTECODE=1 PYTHONHASHSEED=4242 python3 -m canvas_synth generate --out /tmp/run2
python3 -m canvas_synth digest /work/fixtures/canvas | sed "s/^/committed: /"
diff -r /tmp/run1 /tmp/run2 && echo "run1 == run2: byte-identical"
diff -r /tmp/run1 /work/fixtures/canvas && echo "run1 == committed fixtures/canvas: byte-identical"
echo; echo "== 4. negative control: three deliberate defects must be caught"
cp -r /work/fixtures/canvas /tmp/neg && python3 - <<'"'"'PY'"'"'
import json
def edit(rel, fn):
    p = "/tmp/neg/" + rel; d = json.load(open(p)); fn(d); open(p, "w").write(json.dumps(d, separators=(",", ":")))
edit("personas/flagship/courses.json", lambda d: d[0].__setitem__("id", 51845))                                   # numeric id
edit("personas/flagship/assignment_groups/51842.json", lambda d: d[0]["assignments"][0].__setitem__("grade_letter", "A"))  # invented field
edit("personas/flagship/planner_items.page1.json", lambda d: d[0].__setitem__("plannable_date", "2026-09-14T13:00:00.000Z"))  # fractional seconds
PY
PYTHONDONTWRITEBYTECODE=1 python3 validate.py /tmp/neg | tail -4 || echo "(validator exited non-zero as expected)"
echo; echo "== 5. size"; du -sb /work/fixtures/canvas | cut -f1 | sed "s/^/total bytes: /"
tar -C /work/fixtures -cf - canvas | gzip -9 | wc -c | sed "s/^/gzip -9 tar bytes: /"
'
