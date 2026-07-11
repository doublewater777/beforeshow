#!/usr/bin/env bash
# Run one UX plan with Claude Code (non-interactive).
# Usage: worker.sh <plan_id>   e.g. worker.sh 05
set -euo pipefail

PLAN_ID="${1:-}"
if [[ -z "$PLAN_ID" ]]; then
  echo "usage: worker.sh <plan_id>" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLANS_DIR="$ROOT/docs/agents/ux-plans"
STATUS_DIR="$ROOT/scripts/ux-agents/status"
LOG_DIR="$ROOT/scripts/ux-agents/logs"
AGENTS_MD="$ROOT/Agents.md"
if [[ ! -f "$AGENTS_MD" ]]; then
  AGENTS_MD="$ROOT/AGENTS.md"
fi

PLAN_FILE="$(ls "$PLANS_DIR"/"${PLAN_ID}"-*.md 2>/dev/null | head -1 || true)"
if [[ -z "$PLAN_FILE" || ! -f "$PLAN_FILE" ]]; then
  echo "plan not found for id=$PLAN_ID in $PLANS_DIR" >&2
  exit 2
fi

mkdir -p "$STATUS_DIR" "$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$LOG_DIR/${PLAN_ID}-${STAMP}.log"
STATUS="$STATUS_DIR/${PLAN_ID}.json"
PLAN_BASENAME="$(basename "$PLAN_FILE")"
PROMPT_FILE="$LOG_DIR/${PLAN_ID}-${STAMP}.prompt.txt"

write_status() {
  local state="$1"
  local started="${2:-}"
  local finished="${3:-}"
  local exit_code="${4:-}"
  python3 - "$STATUS" "$PLAN_ID" "$PLAN_BASENAME" "$state" "$LOG" "$started" "$finished" "$exit_code" <<'PY'
import json, sys
path, plan_id, plan_file, state, log, started, finished, exit_code = sys.argv[1:]
obj = {
    "plan_id": plan_id,
    "plan_file": plan_file,
    "state": state,
    "updated_at": __import__("datetime").datetime.now().isoformat(timespec="seconds"),
    "log": log,
}
if started:
    obj["started_at"] = started
if finished:
    obj["finished_at"] = finished
if exit_code != "":
    obj["exit_code"] = int(exit_code)
open(path, "w").write(json.dumps(obj, indent=2) + "\n")
PY
}

STARTED="$(date -Iseconds)"
write_status "running" "$STARTED" "" ""

# Write prompt to a file to avoid shell-quoting landmines.
cat >"$PROMPT_FILE" <<PROMPT_EOF
You are a junior implementation agent for the BeforeShow iOS app.

## Hard rules
1. Read and follow ONLY this plan file end-to-end:
   ${PLAN_FILE}
2. Also obey project rules in:
   ${AGENTS_MD}
3. Surgical changes only. No drive-by refactors. No extra features.
4. Stay inside the plan file whitelist.
5. App is not shipped - no backward-compat concerns.
6. When the plan requires build, run:
   cd ${ROOT}/apps/ios && xcodebuild -scheme BeforeShow -destination platform=iOS Simulator,name=iPhone 17 build
7. Do NOT git commit unless the plan explicitly asks (it does not).
8. Do NOT push, force-push, or change git config.
9. When done, print a short REPORT covering: files changed, acceptance checklist pass/fail, residual risks.

## Task
Implement the plan completely. Work in repo root:
${ROOT}

Start by reading the plan file with your file tools, then implement step by step, then build if required, then write the REPORT.
PROMPT_EOF

{
  echo "=== worker plan=${PLAN_ID} file=${PLAN_BASENAME} ==="
  echo "log=${LOG}"
  echo "prompt=${PROMPT_FILE}"
} | tee "$LOG"

cd "$ROOT"

set +e
claude -p "$(cat "$PROMPT_FILE")" \
  --dangerously-skip-permissions \
  --output-format text \
  >>"$LOG" 2>&1
CODE=$?
set -e

FINISHED="$(date -Iseconds)"
if [[ $CODE -eq 0 ]]; then
  write_status "done" "$STARTED" "$FINISHED" "0"
  echo "=== DONE plan=${PLAN_ID} ===" | tee -a "$LOG"
else
  write_status "failed" "$STARTED" "$FINISHED" "$CODE"
  echo "=== FAILED plan=${PLAN_ID} code=${CODE} ===" | tee -a "$LOG"
fi

exit "$CODE"
