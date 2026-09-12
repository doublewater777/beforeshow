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
VERIFY_TEST_LANGUAGE="${VERIFY_TEST_LANGUAGE:-zh-Hans}"
VERIFY_TEST_REGION="${VERIFY_TEST_REGION:-CN}"

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
  local attempts="${1:-8}"
  local probe_timeout="${2:-15}"
  local delay="${3:-5}"
  local attempt

  for ((attempt=1; attempt<=attempts; attempt++)); do
    if run_with_timeout "$probe_timeout" xcrun simctl list devices >/dev/null 2>&1; then
      return 0
    fi
    echo "CoreSimulatorService not ready (attempt $attempt/$attempts)." >&2
    sleep "$delay"
  done
  return 1
}

wake_simulator_app() {
  # Simulator.app is a useful bootstrap path for the per-user CoreSimulator XPC
  # stack on a self-hosted interactive Mac. -g keeps it in the background.
  open -gj -a Simulator >/dev/null 2>&1 || true
}

hard_reset_core_simulator_processes() {
  echo "==> Hard-resetting stale simulator processes" >&2
  killall -9 SimulatorTrampoline >/dev/null 2>&1 || true
  killall -9 CoreSimulatorBridge >/dev/null 2>&1 || true
  killall -9 launchd_sim >/dev/null 2>&1 || true
  killall -9 Simulator >/dev/null 2>&1 || true
  sudo -n killall -9 com.apple.CoreSimulator.CoreSimulatorService >/dev/null 2>&1 \
    || killall -9 com.apple.CoreSimulator.CoreSimulatorService >/dev/null 2>&1 \
    || true

  # The service location varies across macOS/Xcode combinations. Try both user
  # launchctl domains, then let Simulator.app/simctl lazily bootstrap it too.
  launchctl kickstart -k "gui/$(id -u)/com.apple.CoreSimulator.CoreSimulatorService" \
    >/dev/null 2>&1 || true
  launchctl kickstart -k "user/$(id -u)/com.apple.CoreSimulator.CoreSimulatorService" \
    >/dev/null 2>&1 || true
  wake_simulator_app
}

recover_core_simulator_service() {
  echo "==> Recovering CoreSimulatorService" >&2

  # Do not hard-kill immediately. The service can be temporarily unavailable
  # while the user-session simulator stack is relaunching; opening Simulator is
  # less destructive and often enough to reconnect simctl.
  wake_simulator_app
  if wait_for_simctl 3 20 4; then
    return 0
  fi

  echo "Graceful CoreSimulator wake did not recover simctl; escalating." >&2
  hard_reset_core_simulator_processes
  wait_for_simctl 8 15 5
}

cleanup() {
  rm -f "$TEMP_VERIFY"
  if [ -n "$SIM_UDID" ]; then
    run_with_timeout 30 xcrun simctl shutdown "$SIM_UDID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# Do not kill CoreSimulatorService unconditionally: doing so while a device is
# migrating/restarting can make simctl itself disappear for minutes. First probe
# it, then use graceful wake-up before escalating to process cleanup.
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
# all xcodebuild test destinations to the exact warmed simulator UDID, enforce a
# deterministic test language/region, apply hard process-group timeouts, and
# retry Phase 1 once only for known simulator/test-runner transport failures.
# The repository's local verifier behavior is not changed.
{
  head -n 1 scripts/verify-pr.sh
  cat <<'PREAMBLE'

VERIFY_XCODEBUILD_TEST_TIMEOUT_SECONDS="${XCODEBUILD_TEST_TIMEOUT_SECONDS:-720}"
VERIFY_TEST_LANGUAGE="${VERIFY_TEST_LANGUAGE:-zh-Hans}"
VERIFY_TEST_REGION="${VERIFY_TEST_REGION:-CN}"
CI_SIM_UDID="${CI_SIM_UDID:-}"
# Preserve the runner's original stderr so retry/diagnostic messages remain
# visible even while verify-pr.sh redirects xcodebuild output to its phase log.
exec 3>&2

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

ci_wait_for_simctl() {
  local attempts="${1:-6}"
  local probe_timeout="${2:-15}"
  local delay="${3:-4}"
  local attempt

  for ((attempt=1; attempt<=attempts; attempt++)); do
    if ci_run_with_timeout "$probe_timeout" xcrun simctl list devices >/dev/null 2>&1; then
      return 0
    fi
    echo "Phase 1 recovery: CoreSimulatorService not ready ($attempt/$attempts)." >&3
    sleep "$delay"
  done
  return 1
}

ci_wake_simulator_app() {
  open -gj -a Simulator >/dev/null 2>&1 || true
}

ci_hard_reset_core_simulator_processes() {
  echo "Phase 1 recovery: hard-resetting stale simulator processes." >&3
  killall -9 SimulatorTrampoline >/dev/null 2>&1 || true
  killall -9 CoreSimulatorBridge >/dev/null 2>&1 || true
  killall -9 launchd_sim >/dev/null 2>&1 || true
  killall -9 Simulator >/dev/null 2>&1 || true
  sudo -n killall -9 com.apple.CoreSimulator.CoreSimulatorService >/dev/null 2>&1 \
    || killall -9 com.apple.CoreSimulator.CoreSimulatorService >/dev/null 2>&1 \
    || true
  launchctl kickstart -k "gui/$(id -u)/com.apple.CoreSimulator.CoreSimulatorService" \
    >/dev/null 2>&1 || true
  launchctl kickstart -k "user/$(id -u)/com.apple.CoreSimulator.CoreSimulatorService" \
    >/dev/null 2>&1 || true
  ci_wake_simulator_app
}

ci_recover_core_simulator_service() {
  ci_wake_simulator_app
  if ci_wait_for_simctl 3 20 4; then
    return 0
  fi
  ci_hard_reset_core_simulator_processes
  ci_wait_for_simctl 8 15 5
}

ci_recover_test_simulator() {
  local attempt

  if [ -z "$CI_SIM_UDID" ]; then
    echo "Phase 1 recovery: CI_SIM_UDID is empty." >&3
    return 1
  fi

  for attempt in 1 2; do
    # Escalate to service recovery only when simctl itself is unavailable.
    if ! ci_run_with_timeout 15 xcrun simctl list devices >/dev/null 2>&1; then
      echo "Phase 1 recovery: simctl is unavailable; recovering CoreSimulatorService." >&3
      if ! ci_recover_core_simulator_service; then
        continue
      fi
    fi

    ci_run_with_timeout 30 xcrun simctl shutdown "$CI_SIM_UDID" >/dev/null 2>&1 || true
    if ci_run_with_timeout 60 xcrun simctl boot "$CI_SIM_UDID" >/dev/null 2>&1 \
      && ci_run_with_timeout 180 xcrun simctl bootstatus "$CI_SIM_UDID" -b >/dev/null 2>&1; then
      echo "Phase 1 recovery: simulator is ready for retry." >&3
      return 0
    fi

    echo "Phase 1 recovery: simulator boot attempt $attempt/2 failed." >&3
  done

  return 1
}

ci_collect_simulator_diagnostics() {
  local label="$1"
  echo "==> Phase 1 simulator diagnostics ($label)" >&3

  if [ -n "$CI_SIM_UDID" ]; then
    ci_run_with_timeout 30 xcrun simctl spawn "$CI_SIM_UDID" log show \
      --style compact --last 8m \
      --predicate '(process == "BeforeShow") OR (process == "xctest") OR (process == "testmanagerd") OR (process == "CoreSimulatorBridge")' \
      2>/dev/null | tail -200 >&3 || true
  fi

  python3 - "$CI_SIM_UDID" <<'PY' >&3 2>&1 || true
import sys
import time
from pathlib import Path

udid = sys.argv[1] if len(sys.argv) > 1 else ""
home = Path.home()
roots = [home / "Library/Logs/DiagnosticReports"]
if udid:
    roots.extend([
        home / "Library/Developer/CoreSimulator/Devices" / udid / "data/Library/Logs/CrashReporter",
        home / "Library/Developer/CoreSimulator/Devices" / udid / "data/Library/Logs/DiagnosticReports",
    ])

needles = ("beforeshow", "xctest", "testmanager", "coresimulator")
cutoff = time.time() - 15 * 60
candidates = []
for root in roots:
    if not root.exists():
        continue
    try:
        entries = list(root.iterdir())
    except OSError:
        continue
    for path in entries:
        try:
            if not path.is_file() or path.stat().st_mtime < cutoff:
                continue
        except OSError:
            continue
        if any(needle in path.name.lower() for needle in needles):
            candidates.append(path)

candidates.sort(key=lambda p: p.stat().st_mtime, reverse=True)
if not candidates:
    print("No recent matching crash reports found.")
else:
    for path in candidates[:4]:
        print(f"--- crash report: {path} ---")
        try:
            text = path.read_text(errors="replace")
        except OSError as exc:
            print(f"unable to read: {exc}")
            continue
        for line in text.splitlines()[-140:]:
            print(line)
PY
}

ci_phase1_failure_is_retryable() {
  local result_bundle="$1"
  local phase_log="${result_bundle%phase1-tests.xcresult}phase1-test.log"

  [ -f "$phase_log" ] || return 1
  grep -Eqi \
    'Failed to establish communication with the test runner|Channel disconnected|CoreSimulatorService connection interrupted|Logging connection interrupted|Early unexpected exit|Mach error|server died' \
    "$phase_log"
}

ci_xcodebuild() {
  local result_bundle=""
  local previous=""
  local arg
  local first_status
  local retry_status

  for arg in "$@"; do
    if [ "$previous" = "-resultBundlePath" ]; then
      result_bundle="$arg"
    fi
    previous="$arg"
  done

  if ci_run_with_timeout "$VERIFY_XCODEBUILD_TEST_TIMEOUT_SECONDS" \
      xcodebuild -testLanguage "$VERIFY_TEST_LANGUAGE" -testRegion "$VERIFY_TEST_REGION" "$@"; then
    return 0
  else
    first_status=$?
  fi

  # Only Phase 1 transport/infrastructure failures get one retry. Assertion or
  # ordinary test failures remain final on the first attempt.
  case "$result_bundle" in
    *phase1-tests.xcresult)
      if ! ci_phase1_failure_is_retryable "$result_bundle"; then
        return "$first_status"
      fi
      ;;
    *)
      return "$first_status"
      ;;
  esac

  echo "==> Phase 1 hit a transient simulator/test-runner failure; retrying once." >&3
  ci_collect_simulator_diagnostics "after first failure"

  if ! ci_recover_test_simulator; then
    echo "Phase 1 retry skipped: simulator recovery failed." >&3
    return "$first_status"
  fi

  # xcodebuild refuses to reuse an existing result bundle path.
  rm -rf "$result_bundle"
  echo "==> Phase 1 retry starting on recovered simulator $CI_SIM_UDID." >&3

  if ci_run_with_timeout "$VERIFY_XCODEBUILD_TEST_TIMEOUT_SECONDS" \
      xcodebuild -testLanguage "$VERIFY_TEST_LANGUAGE" -testRegion "$VERIFY_TEST_REGION" "$@"; then
    echo "==> Phase 1 retry passed." >&3
    return 0
  else
    retry_status=$?
  fi

  ci_collect_simulator_diagnostics "after retry failure"
  return "$retry_status"
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

# `head -1` closes the pipe before Xcode 26.6 finishes writing `xcodebuild
# -version`, which can raise NSFileHandleOperationException/Broken pipe. Make the
# generated report command consume the whole stream with awk instead.
python3 - "$TEMP_VERIFY" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = "xcodebuild -version | head -1 | awk '{print $2}'"
new = "xcodebuild -version | awk 'NR == 1 {print $2}'"
if old not in text:
    raise SystemExit("Expected xcodebuild version pipeline was not found")
path.write_text(text.replace(old, new))
PY

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

echo "==> Test locale: $VERIFY_TEST_LANGUAGE / $VERIFY_TEST_REGION"

exec_status=0
CI_SIM_UDID="$SIM_UDID" \
VERIFY_TEST_LANGUAGE="$VERIFY_TEST_LANGUAGE" \
VERIFY_TEST_REGION="$VERIFY_TEST_REGION" \
XCODEBUILD_TEST_TIMEOUT_SECONDS="$XCODEBUILD_TEST_TIMEOUT_SECONDS" \
  "$TEMP_VERIFY" "$@" || exec_status=$?
exit "$exec_status"
