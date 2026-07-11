#!/usr/bin/env bash
# Launch tmux session that runs the UX orchestrator + a status pane.
# Usage:
#   ./tmux-launch.sh                 # all plans sequential
#   ./tmux-launch.sh --from 01
#   ./tmux-launch.sh --only 01,02
#   ./tmux-launch.sh --attach        # attach after start
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SESSION="${UX_TMUX_SESSION:-bs-ux}"
ORCH="$ROOT/scripts/ux-agents/orchestrate.sh"
STATUS_WATCH="$ROOT/scripts/ux-agents/status-watch.sh"
ATTACH=0
ORCH_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --attach) ATTACH=1; shift ;;
    --session) SESSION="$2"; shift 2 ;;
    *) ORCH_ARGS+=("$1"); shift ;;
  esac
done

chmod +x "$ORCH" "$ROOT/scripts/ux-agents/worker.sh" "$STATUS_WATCH" 2>/dev/null || true

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "session '$SESSION' already exists"
  echo "  attach: tmux attach -t $SESSION"
  echo "  kill:   tmux kill-session -t $SESSION"
  exit 1
fi

# Window 0: orchestrator (bash 3.2–safe arg join)
ORCH_CMD="cd '$ROOT' && '$ORCH'"
if [[ ${#ORCH_ARGS[@]} -gt 0 ]]; then
  for a in "${ORCH_ARGS[@]}"; do
    ORCH_CMD+=" $(printf '%q' "$a")"
  done
fi
ORCH_CMD+="; echo; echo '[orch exited]'; bash"

tmux new-session -d -s "$SESSION" -n orch -c "$ROOT"
tmux send-keys -t "$SESSION:orch" "$ORCH_CMD" C-m

# Window 1: live status
tmux new-window -t "$SESSION" -n status -c "$ROOT"
tmux send-keys -t "$SESSION:status" \
  "cd '$ROOT' && '$STATUS_WATCH'" \
  C-m

# Window 2: logs tail helper
tmux new-window -t "$SESSION" -n logs -c "$ROOT/scripts/ux-agents/logs"
tmux send-keys -t "$SESSION:logs" \
  "cd '$ROOT/scripts/ux-agents/logs' && ls -lt | head -20; echo; echo 'tail -f newest:'; echo '  ls -t | head -1 | xargs tail -f'" \
  C-m

tmux select-window -t "$SESSION:orch"

echo "started tmux session: $SESSION"
echo "  attach:  tmux attach -t $SESSION"
echo "  status:  tmux select-window -t $SESSION:status"
echo "  kill:    tmux kill-session -t $SESSION"
echo "  args:    ${ORCH_ARGS[*]:-(all waves)}"

if [[ $ATTACH -eq 1 ]]; then
  tmux attach -t "$SESSION"
fi
