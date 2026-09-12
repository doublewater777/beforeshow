#!/usr/bin/env bash
# CI wrapper for verify-pr.sh.
# On the self-hosted Mac, keep simulator state deterministic without forcing a
# fresh device through first-boot migrations on every PR. Reuse the already
# warmed iPhone 17, shut down competing simulators, and put hard timeouts around
# simulator/test operations so CoreSimulator failures cannot wedge the runner.
set -euo pipefail

SIM_NAME="iPhone 17"
RUN_SCOPE="${GITHUB_RUN_ID:-local-$$}-${GITHUB_RUN_ATTEMPT:-1}-${GITHUB_JOB:-verify}"
TEMP_VERIFY="${RUNNER_TEMP:-/tmp}/verify-pr-${RUN_SCOPE}.sh"
SIM_UDID=""
XCODEBUILD_TEST_TIMEOUT_SECONDS="${XCODEBUILD_TEST_TIMEOUT_SECONDS:-720}"

run_with_timeout() {
  local seconds="$1"
  shift
  python3 - "$seconds" "$@" <<'PY'
import os
import signal
import subprocess
import sys

seconds = int(sys.argv[1])
command = sys.argv[2:]
process = subprocess.Popen(command, start_new_session=True)
try:
    return_code = process.wait(timeout=seconds)
except subprocess.TimeoutExpired:
    print(
        f"Command timed out after {seconds}s: {' '.join(command)}",
        file=sys.stderr,
        flush=True,
    )
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
    sys.exit(124)

if return_code < 0:
    sys.exit(128 + (-return_code))
sys.exit(return_code)
PY
}

wait_for_simctl() {
  local attempt
  for attempt in 1 2 3 4 5 6 7 8; do
    if run_with_timeout 15 xcrun simctl list devices >/dev/null 2>&1; then
      return 0
    fi
    echo "CoreSimulatorService not ready (attempt $attempt/8)." >&2
    sleep 5
  done
  return 1
}

recover_core_simulator_service() {
  echo "==> Recovering CoreSimulatorService" >&2
  killall -9 com.apple.CoreSimulator.CoreSimulatorService >/dev/null 2>&1 || true
  # On an interactive self-hosted runner the service is a per-user launch agent.
  # kickstart is best-effort; simctl itself will also request the service.
  launchctl kickstart -k "gui/$(id -u)/com.apple.CoreSimulator.CoreSimulatorService" \
    >/dev/null 2>&1 || true
  wait_for_simctl
}

cleanup() {
  rm -f "$TEMP_VERIFY"
  if [ -n "$SIM_UDID" ]; then
    run_with_timeout 30 xcrun simctl shutdown "$SIM_UDID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# Do not kill CoreSimulatorService unconditionally: doing so while a newly
# created device is migrating can make simctl itself disappear for minutes.
# First verify that simctl is healthy, and recover the service only if needed.
echo "==> Preparing warmed simulator for CI verification"
if ! run_with_timeout 20 xcrun simctl list devices >/dev/null 2>&1; then
  if ! recover_core_simulator_service; then
    echo "CoreSimulatorService did not recover." >&2
    exit 2
  fi
fi

# The runner is also used interactively. Never allow another booted simulator
# (for example Listening QA) to compete with the verifier for CoreSimulator.
if ! run_with_timeout 60 xcrun simctl shutdown all >/dev/null 2>&1; then
  if ! recover_core_simulator_service; then
    echo "Unable to recover CoreSimulatorService after shutdown-all failure." >&2
    exit 2
  fi
  run_with_timeout 60 xcrun simctl shutdown all >/dev/null 2>&1 || true
fi

SIM_LIST=$(run_with_timeout 30 xcrun simctl list devices available) || {
  if ! recover_core_simulator_service; then
    echo "Unable to list available simulators." >&2
    exit 2
  fi
  SIM_LIST=$(run_with_timeout 30 xcrun simctl list devices available)
}
SIM_UDID=$(
  printf '%s\n' "$SIM_LIST" | awk -F '[()]' -v name="$SIM_NAME" '
    {
      candidate=$1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", candidate)
      if (candidate == name) {
        print $2
        exit
      }
    }
  '
)

if [ -z "$SIM_UDID" ]; then
  echo "Warmed simulator '$SIM_NAME' was not found; refusing to create a cold CI device." >&2
  exit 2
fi
echo "==> Using warmed simulator: $SIM_NAME ($SIM_UDID)"

boot_warmed_simulator() {
  local attempt

  # Two graceful boot cycles first. A shutdown/boot is enough to recover the
  # failure mode seen on this runner more often than killing the whole service.
  for attempt in 1 2; do
    run_with_timeout 30 xcrun simctl shutdown "$SIM_UDID" >/dev/null 2>&1 || true
    if run_with_timeout 60 xcrun simctl boot "$SIM_UDID" \
      && run_with_timeout 180 xcrun simctl bootstatus "$SIM_UDID" -b; then
      return 0
    fi
    echo "Warmed simulator boot attempt $attempt failed; retrying cleanly." >&2
  done

  # Escalate only after graceful recovery failed twice.
  if ! recover_core_simulator_service; then
    return 1
  fi
  run_with_timeout 60 xcrun simctl shutdown all >/dev/null 2>&1 || true
  run_with_timeout 60 xcrun simctl boot "$SIM_UDID" \
    && run_with_timeout 180 xcrun simctl bootstatus "$SIM_UDID" -b
}

if ! boot_warmed_simulator; then
  echo "Warmed simulator failed to become ready after recovery: $SIM_UDID." >&2
  exit 2
fi

# verify-pr.sh remains the local verifier. Patch a temporary CI-only copy to pin
# all xcodebuild test destinations to the exact warmed simulator UDID and enforce
# hard process-group timeouts. The repository's local verifier behavior is not
# changed.
{
  head -n 1 scripts/verify-pr.sh
  cat <<'PREAMBLE'

VERIFY_XCODEBUILD_TEST_TIMEOUT_SECONDS="${XCODEBUILD_TEST_TIMEOUT_SECONDS:-720}"

ci_run_with_timeout() {
  local seconds="$1"
  shift
  python3 - "$seconds" "$@" <<'PY'
import os
import signal
import subprocess
import sys

seconds = int(sys.argv[1])
command = sys.argv[2:]
process = subprocess.Popen(command, start_new_session=True)
try:
    return_code = process.wait(timeout=seconds)
except subprocess.TimeoutExpired:
    print(
        f"Command timed out after {seconds}s: {' '.join(command)}",
        file=sys.stderr,
        flush=True,
    )
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
    sys.exit(124)

if return_code < 0:
    sys.exit(128 + (-return_code))
sys.exit(return_code)
PY
}

ci_xcodebuild() {
  ci_run_with_timeout "$VERIFY_XCODEBUILD_TEST_TIMEOUT_SECONDS" xcodebuild "$@"
}
PREAMBLE
  tail -n +2 scripts/verify-pr.sh \
    | sed "s|platform=iOS Simulator,name=\$SIM_NAME|platform=iOS Simulator,id=$SIM_UDID|g" \
    | sed 's/if ! xcodebuild test \\/if ! ci_xcodebuild test \\/g' \
    | sed 's/xcrun simctl bootstatus \"$UDID\" -b/ci_run_with_timeout 180 xcrun simctl bootstatus \"$UDID\" -b/g' \
    | sed 's/xcrun simctl boot \"$UDID\"/ci_run_with_timeout 60 xcrun simctl boot \"$UDID\"/g' \
    | sed 's/xcrun simctl shutdown \"$UDID\"/ci_run_with_timeout 30 xcrun simctl shutdown \"$UDID\"/g' \
    | sed 's/LAUNCH_OUT=$(xcrun simctl launch \"$UDID\" \"$BID\")/LAUNCH_OUT=$(ci_run_with_timeout 60 xcrun simctl launch \"$UDID\" \"$BID\")/g'
} > "$TEMP_VERIFY"
chmod +x "$TEMP_VERIFY"

PATCHED_TEST_COUNT=$(grep -c 'if ! ci_xcodebuild test \\' "$TEMP_VERIFY" || true)
PATCHED_DESTINATION_COUNT=$(grep -c "platform=iOS Simulator,id=$SIM_UDID" "$TEMP_VERIFY" || true)
if [ "$PATCHED_TEST_COUNT" -ne 6 ]; then
  echo "Expected to wrap 6 xcodebuild test commands, wrapped $PATCHED_TEST_COUNT." >&2
  exit 2
fi
if [ "$PATCHED_DESTINATION_COUNT" -ne 6 ]; then
  echo "Expected to pin 6 xcodebuild destinations, pinned $PATCHED_DESTINATION_COUNT." >&2
  exit 2
fi

exec_status=0
XCODEBUILD_TEST_TIMEOUT_SECONDS="$XCODEBUILD_TEST_TIMEOUT_SECONDS" "$TEMP_VERIFY" "$@" || exec_status=$?
exit "$exec_status"
