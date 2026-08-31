#!/usr/bin/env bash

set -u
set -o pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename -- "$0")"

usage() {
  cat <<'EOF'
Usage:
  loop.sh start <interval> [options] [--] <prompt>
  loop.sh status [--cwd <directory>]
  loop.sh stop [--cwd <directory>]

Intervals use s, m, or h suffixes, for example 30s, 1m, or 2h.

Start options:
  --max-rounds <number>  Stop after this many rounds (default: 20)
  --forever              Keep starting rounds until stopped
  --until-success        Stop when a codex exec exits successfully
  --cwd <directory>      Project directory for every round (default: current directory)
  --model <model>        Model passed to codex exec
  --sandbox <policy>     Sandbox passed to codex exec
  --approve-for-me       Route exec approvals through automatic review
EOF
}

fail() {
  echo "codex-loop: $*" >&2
  exit 2
}

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

resolve_directory() {
  local directory="$1"
  [[ -d "$directory" ]] || fail "directory does not exist: $directory"
  CDPATH= cd -- "$directory" && pwd
}

parse_interval() {
  local value="$1"
  local number
  local suffix

  [[ "$value" =~ ^[0-9]+[smh]$ ]] || return 1
  number="${value%?}"
  suffix="${value: -1}"
  (( number > 0 )) || return 1

  case "$suffix" in
    s) echo "$number" ;;
    m) echo $((number * 60)) ;;
    h) echo $((number * 3600)) ;;
  esac
}

state_directory() {
  local directory="$1"
  local root="${CODEX_LOOP_STATE_DIR:-${TMPDIR:-/tmp}/codex-loop}"
  local key
  key="$(printf '%s' "$directory" | cksum | awk '{print $1}')"
  printf '%s/%s' "$root" "$key"
}

pid_is_running() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

pid_command() {
  ps -p "$1" -o command= 2>/dev/null || true
}

pid_is_loop() {
  local command_line
  command_line="$(pid_command "$1")"
  [[ "$command_line" == *"loop.sh"*" run"* ]]
}

read_option_value() {
  [[ $# -ge 2 && -n "$2" ]] || fail "missing value for $1"
  echo "$2"
}

start_loop() {
  local interval="${1:-}"
  [[ -n "$interval" ]] || fail "start requires an interval"
  shift

  local interval_seconds
  interval_seconds="$(parse_interval "$interval")" || fail "invalid interval '$interval'; use a positive value ending in s, m, or h"

  local max_rounds=20
  local until_success=0
  local cwd="$PWD"
  local model=""
  local sandbox=""
  local approve_for_me=0
  local prompt=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-rounds)
        [[ $# -ge 2 && "$2" =~ ^[0-9]+$ && "$2" -gt 0 ]] || fail "--max-rounds must be a positive integer"
        max_rounds="$2"
        shift 2
        ;;
      --forever)
        max_rounds=0
        shift
        ;;
      --until-success)
        until_success=1
        shift
        ;;
      --cwd)
        cwd="$(read_option_value "$1" "${2:-}")"
        shift 2
        ;;
      --model)
        model="$(read_option_value "$1" "${2:-}")"
        shift 2
        ;;
      --sandbox)
        sandbox="$(read_option_value "$1" "${2:-}")"
        shift 2
        ;;
      --approve-for-me)
        approve_for_me=1
        shift
        ;;
      --)
        shift
        prompt="$*"
        break
        ;;
      -*)
        fail "unknown start option: $1"
        ;;
      *)
        prompt="$*"
        break
        ;;
    esac
  done

  [[ -n "$prompt" ]] || fail "start requires a prompt"
  cwd="$(resolve_directory "$cwd")"

  local state_dir
  state_dir="$(state_directory "$cwd")"
  mkdir -p "$state_dir" || fail "cannot create state directory: $state_dir"

  local pid_file="$state_dir/pid"
  if [[ -f "$pid_file" ]]; then
    local existing_pid
    existing_pid="$(sed -n '1p' "$pid_file")"
    if pid_is_running "$existing_pid" && pid_is_loop "$existing_pid"; then
      fail "a loop is already running for $cwd (PID $existing_pid)"
    fi
    rm -f "$pid_file"
  fi

  umask 077
  printf '%s\n' "$cwd" > "$state_dir/cwd"
  printf '%s\n' "$interval" > "$state_dir/interval"
  printf '%s\n' "$max_rounds" > "$state_dir/max-rounds"
  printf '%s\n' "$until_success" > "$state_dir/until-success"
  printf '%s\n' "$prompt" > "$state_dir/prompt"
  printf '%s\n' "$(timestamp)" > "$state_dir/started-at"
  : > "$state_dir/log"

  local run_args=(run --state-dir "$state_dir" --interval-seconds "$interval_seconds" --cwd "$cwd" --max-rounds "$max_rounds" --until-success "$until_success" --prompt "$prompt")
  [[ -n "$model" ]] && run_args+=(--model "$model")
  [[ -n "$sandbox" ]] && run_args+=(--sandbox "$sandbox")
  (( approve_for_me == 1 )) && run_args+=(--approve-for-me)

  nohup "$SCRIPT_PATH" "${run_args[@]}" >> "$state_dir/log" 2>&1 < /dev/null &
  local pid=$!
  printf '%s\n' "$pid" > "$pid_file"

  echo "Started Codex loop (PID $pid)."
  echo "Project: $cwd"
  echo "Interval: $interval"
  if (( max_rounds == 0 )); then
    echo "Rounds: forever"
  else
    echo "Rounds: $max_rounds"
  fi
  echo "Log: $state_dir/log"
}

run_loop() {
  local state_dir=""
  local interval_seconds=""
  local cwd=""
  local max_rounds=20
  local until_success=0
  local model=""
  local sandbox=""
  local approve_for_me=0
  local prompt=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --state-dir) state_dir="${2:-}"; shift 2 ;;
      --interval-seconds) interval_seconds="${2:-}"; shift 2 ;;
      --cwd) cwd="${2:-}"; shift 2 ;;
      --max-rounds) max_rounds="${2:-}"; shift 2 ;;
      --until-success) until_success="${2:-}"; shift 2 ;;
      --model) model="${2:-}"; shift 2 ;;
      --sandbox) sandbox="${2:-}"; shift 2 ;;
      --approve-for-me) approve_for_me=1; shift ;;
      --prompt) prompt="${2:-}"; shift 2 ;;
      *) fail "unknown run option: $1" ;;
    esac
  done

  [[ -n "$state_dir" && -n "$interval_seconds" && -n "$cwd" && -n "$prompt" ]] || fail "run is missing loop configuration"
  command -v "${CODEX_BIN:-codex}" >/dev/null 2>&1 || fail "codex executable not found; set CODEX_BIN or install Codex CLI"

  local child_pid=""
  cleanup() {
    if [[ -n "$child_pid" ]] && pid_is_running "$child_pid"; then
      kill "$child_pid" 2>/dev/null || true
    fi
    rm -f "$state_dir/pid" "$state_dir/current-round"
  }
  trap cleanup EXIT
  trap 'exit 130' INT TERM

  local round=0
  local exit_code=0
  local round_label
  local codex_args
  local codex_bin="${CODEX_BIN:-codex}"

  while :; do
    if (( max_rounds > 0 && round >= max_rounds )); then
      echo "[$(timestamp)] Reached max rounds ($max_rounds)."
      break
    fi

    round=$((round + 1))
    printf '%s\n' "$round" > "$state_dir/current-round"
    if (( max_rounds == 0 )); then
      round_label="$round"
    else
      round_label="$round/$max_rounds"
    fi
    echo "[$(timestamp)] Starting round $round_label."

    codex_args=(exec -C "$cwd")
    [[ -n "$model" ]] && codex_args+=(--model "$model")
    [[ -n "$sandbox" ]] && codex_args+=(--sandbox "$sandbox")
    (( approve_for_me == 1 )) && codex_args+=(--approve-for-me)

    "$codex_bin" "${codex_args[@]}" "$prompt" &
    child_pid=$!
    wait "$child_pid"
    exit_code=$?
    child_pid=""
    echo "[$(timestamp)] Round $round exited with status $exit_code."

    if (( until_success == 1 && exit_code == 0 )); then
      echo "[$(timestamp)] Stopping after successful round."
      break
    fi

    if (( max_rounds > 0 && round >= max_rounds )); then
      echo "[$(timestamp)] Reached max rounds ($max_rounds)."
      break
    fi

    echo "[$(timestamp)] Sleeping for ${interval_seconds}s."
    sleep "$interval_seconds" &
    child_pid=$!
    wait "$child_pid"
    child_pid=""
  done
}

status_loop() {
  local cwd="$PWD"
  if [[ "${1:-}" == "--cwd" ]]; then
    [[ $# -ge 2 ]] || fail "--cwd requires a directory"
    cwd="$2"
  elif [[ $# -gt 0 ]]; then
    fail "unknown status option: $1"
  fi
  cwd="$(resolve_directory "$cwd")"

  local state_dir
  state_dir="$(state_directory "$cwd")"
  local pid_file="$state_dir/pid"
  local pid=""
  [[ -f "$pid_file" ]] && pid="$(sed -n '1p' "$pid_file")"

  if pid_is_running "$pid" && pid_is_loop "$pid"; then
    echo "Status: running"
    echo "PID: $pid"
  else
    echo "Status: stopped"
    [[ -n "$pid" ]] && rm -f "$pid_file"
  fi
  echo "Project: $cwd"
  [[ -f "$state_dir/interval" ]] && echo "Interval: $(sed -n '1p' "$state_dir/interval")"
  if [[ -f "$state_dir/max-rounds" ]]; then
    local max_rounds
    max_rounds="$(sed -n '1p' "$state_dir/max-rounds")"
    [[ "$max_rounds" == "0" ]] && echo "Rounds: forever" || echo "Rounds: $max_rounds"
  fi
  [[ -f "$state_dir/current-round" ]] && echo "Current round: $(sed -n '1p' "$state_dir/current-round")"
  [[ -f "$state_dir/log" ]] && echo "Log: $state_dir/log"
}

stop_loop() {
  local cwd="$PWD"
  if [[ "${1:-}" == "--cwd" ]]; then
    [[ $# -ge 2 ]] || fail "--cwd requires a directory"
    cwd="$2"
  elif [[ $# -gt 0 ]]; then
    fail "unknown stop option: $1"
  fi
  cwd="$(resolve_directory "$cwd")"

  local state_dir
  state_dir="$(state_directory "$cwd")"
  local pid_file="$state_dir/pid"
  [[ -f "$pid_file" ]] || { echo "No active Codex loop for $cwd."; return 0; }

  local pid
  pid="$(sed -n '1p' "$pid_file")"
  if ! pid_is_running "$pid" || ! pid_is_loop "$pid"; then
    rm -f "$pid_file"
    echo "No active Codex loop for $cwd."
    return 0
  fi

  kill "$pid" 2>/dev/null || fail "could not stop loop PID $pid"
  echo "Stop requested for Codex loop PID $pid."
}

command_name="${1:-help}"
shift || true
case "$command_name" in
  start) start_loop "$@" ;;
  run) run_loop "$@" ;;
  status) status_loop "$@" ;;
  stop) stop_loop "$@" ;;
  help|-h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
