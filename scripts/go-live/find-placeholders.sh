#!/usr/bin/env bash
# Lists every go-live placeholder still in the app source, as file:line.
# GO-LIVE blocker GL-02 (docs/GO-LIVE.md): the release gate runs this and
# fails while anything is listed.
#
#   scripts/go-live/find-placeholders.sh          # list; exit 1 if any remain
#
# Scope: shipping code and config only. Docs, the build kit and the synthetic
# Canvas fixtures (which use fictional *.example school domains on purpose)
# are excluded.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

excludes=(
  --exclude-dir=.git --exclude-dir=docs --exclude-dir=fixtures
  --exclude-dir=tools --exclude-dir=Tally_Antigravity_Build_Kit_Scaffold
  --exclude-dir=.build --exclude-dir=build --exclude-dir=DerivedData
  --exclude=find-placeholders.sh --exclude='*.md'
)

# label | extended regex
checks=(
  "Tagged placeholder (set the real value)|GO-LIVE-PLACEHOLDER|__TEAM_ID__|__SUPPORT_EMAIL__|__EFFECTIVE_DATE__"
  "Legal draft not yet reviewed (GL-03)|DRAFT-PENDING-LEGAL-REVIEW"
  "Placeholder domain / bundle prefix|tally\.example\.com|com\.example([^A-Za-z0-9]|$)"
  "Legacy hard-coded identifier (replace with a value derived from the bundle ID)|com\.tally|callbackURLScheme: \"tally\""
)

total=0
for check in "${checks[@]}"; do
  label="${check%%|*}"
  pattern="${check#*|}"
  hits="$(grep -rnE "${excludes[@]}" -e "$pattern" . 2>/dev/null | sed 's|^\./||' || true)"
  if [[ -n "$hits" ]]; then
    count="$(printf '%s\n' "$hits" | wc -l | tr -d ' ')"
    total=$((total + count))
    printf '\n== %s (%s)\n%s\n' "$label" "$count" "$hits"
  fi
done

if [[ "$total" -eq 0 ]]; then
  echo "No go-live placeholders remain."
  exit 0
fi
printf '\n%s placeholder line(s) remain. Set real values in apps/TallyiOS/Config/Identity.xcconfig; see docs/GO-LIVE.md GL-02.\n' "$total"
exit 1
