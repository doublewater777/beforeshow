#!/usr/bin/env bash
# Poll plan status JSON every 5s.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STATUS_DIR="$ROOT/scripts/ux-agents/status"
PLANS_DIR="$ROOT/docs/agents/ux-plans"

while true; do
  clear 2>/dev/null || true
  echo "BeforeShow UX agents — $(date '+%H:%M:%S')"
  echo "status dir: $STATUS_DIR"
  echo
  printf "%-6s %-12s %-20s %s\n" "ID" "STATE" "UPDATED" "PLAN"
  printf "%-6s %-12s %-20s %s\n" "----" "-----" "-------" "----"
  for f in "$PLANS_DIR"/[0-9][0-9]-*.md; do
    base="$(basename "$f")"
    id="${base:0:2}"
    st="$STATUS_DIR/${id}.json"
    if [[ -f "$st" ]]; then
      python3 - "$st" "$base" <<'PY'
import json, sys
p=json.load(open(sys.argv[1]))
print(f"{p.get('plan_id','?'):<6} {p.get('state','?'):<12} {p.get('updated_at','')[:19]:<20} {sys.argv[2]}")
PY
    else
      printf "%-6s %-12s %-20s %s\n" "$id" "pending" "-" "$base"
    fi
  done
  echo
  echo "logs: $ROOT/scripts/ux-agents/logs/"
  echo "refresh 5s · Ctrl-C to stop watch (orch keeps running in other window)"
  sleep 5
done
