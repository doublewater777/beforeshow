#!/usr/bin/env bash
# Sequential wave runner for UX plans (Claude Code workers).
# Usage:
#   ./orchestrate.sh              # run all waves
#   ./orchestrate.sh --from 03    # start at plan 03
#   ./orchestrate.sh --only 01,02 # only these plan ids
#   ./orchestrate.sh --dry-run    # print order only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONF="$ROOT/scripts/ux-agents/waves.conf"
STATUS_DIR="$ROOT/scripts/ux-agents/status"
LOG_DIR="$ROOT/scripts/ux-agents/logs"
WORKER="$ROOT/scripts/ux-agents/worker.sh"

FROM=""
ONLY=""
DRY=0
STOP_ON_FAIL=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) FROM="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --continue-on-fail) STOP_ON_FAIL=0; shift ;;
    -h|--help)
      sed -n '2,10p' "$0"
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$STATUS_DIR" "$LOG_DIR"
chmod +x "$WORKER"

# Parse waves.conf into ordered plan ids
PLANS=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"
  line="$(echo "$line" | tr -d '[:space:]')"
  [[ -z "$line" ]] && continue
  [[ "$line" == WAVE:* ]] && continue
  PLANS+=("$line")
done <"$CONF"

# Filter
FILTERED=()
SKIP=1
if [[ -z "$FROM" ]]; then SKIP=0; fi
for p in "${PLANS[@]}"; do
  if [[ -n "$ONLY" ]]; then
    if [[ ",$ONLY," == *",$p,"* ]]; then
      FILTERED+=("$p")
    fi
    continue
  fi
  if [[ $SKIP -eq 1 ]]; then
    if [[ "$p" == "$FROM" ]]; then
      SKIP=0
      FILTERED+=("$p")
    fi
    continue
  fi
  FILTERED+=("$p")
done

if [[ ${#FILTERED[@]} -eq 0 ]]; then
  echo "no plans to run" >&2
  exit 1
fi

echo "=== UX orchestrator ==="
echo "root: $ROOT"
echo "queue: ${FILTERED[*]}"
echo "stop_on_fail: $STOP_ON_FAIL"
echo

if [[ $DRY -eq 1 ]]; then
  exit 0
fi

FAILED=()
for p in "${FILTERED[@]}"; do
  echo "-------- $(date -Iseconds) starting plan $p --------"
  if "$WORKER" "$p"; then
    echo "-------- plan $p OK --------"
  else
    echo "-------- plan $p FAILED --------"
    FAILED+=("$p")
    if [[ $STOP_ON_FAIL -eq 1 ]]; then
      echo "stopping queue (use --continue-on-fail to keep going)"
      break
    fi
  fi
done

echo
echo "=== summary ==="
for p in "${FILTERED[@]}"; do
  st="$STATUS_DIR/${p}.json"
  if [[ -f "$st" ]]; then
    state="$(python3 -c "import json;print(json.load(open('$st'))['state'])" 2>/dev/null || echo '?')"
    echo "  $p: $state"
  else
    echo "  $p: (no status)"
  fi
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "failed: ${FAILED[*]}"
  exit 1
fi
echo "all requested plans finished OK"
