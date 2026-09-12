#!/usr/bin/env bash
# CI wrapper for verify-pr.sh.
# Resets CoreSimulator on the self-hosted runner, creates a fresh dedicated
# simulator, and adds hard timeouts around simulator/test operations so a dead
# CoreSimulatorService cannot wedge the runner for the entire job timeout.
set -euo pipefail

BASE_SIM_NAME="iPhone 17"
RUN_SCOPE="${GITHUB_RUN_ID:-local-$$}-${GITHUB_RUN_ATTEMPT:-1}-${GITHUB_JOB:-verify}"
SIM_NAME="BeforeShow Verify ${RUN_SCOPE}"
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

cleanup() {
  rm -f "$TEMP_VERIFY"
  if [ -n "$SIM_UDID" ]; then
    run_with_timeout 30 xcrun simctl shutdown "$SIM_UDID" >/dev/null 2>&1 || true
    run_with_timeout 30 xcrun simctl delete "$SIM_UDID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "==> Resetting CoreSimulatorService before CI verification"
# The self-hosted Mac is also used interactively. Multiple booted simulators can
# leave CoreSimulatorService in a state where test launch hangs with Mach -308.
# Stop the service first so simctl talks to a fresh server, then shut down every
# still-registered booted device. We only delete stale CI-owned devices; local
# simulator data is preserved.
killall -9 com.apple.CoreSimulator.CoreSimulatorService >/dev/null 2>&1 || true
sleep 2
if ! run_with_timeout 30 xcrun simctl list devices >/dev/null; then
  echo "CoreSimulatorService did not recover after restart." >&2
  exit 2
fi
run_with_timeout 60 xcrun simctl shutdown all >/dev/null 2>&1 || true

STALE_UDIDS=$(
  xcrun simctl list devices -j | python3 -c '
import json, sys
for runtime in json.load(sys.stdin).get("devices", {}).values():
    for device in runtime:
        if device.get("name", "").startswith("BeforeShow Verify "):
            print(device.get("udid", ""))
'
)
if [ -n "$STALE_UDIDS" ]; then
  while IFS= read -r stale_udid; do
    [ -n "$stale_udid" ] || continue
    run_with_timeout 30 xcrun simctl shutdown "$stale_udid" >/dev/null 2>&1 || true
    run_with_timeout 30 xcrun simctl delete "$stale_udid" >/dev/null 2>&1 || true
  done <<< "$STALE_UDIDS"
fi

DEVICE_TYPE_ID=$(
  xcrun simctl list devicetypes -j | python3 -c '
import json, sys
for device_type in json.load(sys.stdin).get("devicetypes", []):
    if device_type.get("name") == "iPhone 17":
        print(device_type["identifier"])
        break
'
)

RUNTIME_ID=$(
  xcrun simctl list runtimes -j | python3 -c '
import json, re, sys
runtimes = [
    runtime for runtime in json.load(sys.stdin).get("runtimes", [])
    if runtime.get("isAvailable")
    and ".SimRuntime.iOS-" in runtime.get("identifier", "")
]
def version(runtime):
    value = runtime.get("version", "0")
    return tuple(int(part) for part in re.findall(r"\d+", value))
runtimes.sort(key=version)
if runtimes:
    print(runtimes[-1]["identifier"])
'
)

if [ -z "$DEVICE_TYPE_ID" ] || [ -z "$RUNTIME_ID" ]; then
  echo "Unable to resolve an available iPhone 17 device type/runtime." >&2
  exit 2
fi

SIM_UDID=$(run_with_timeout 60 xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE_ID" "$RUNTIME_ID")
echo "==> Created dedicated simulator: $SIM_NAME ($SIM_UDID)"

# Boot the fresh device explicitly after the CoreSimulator reset. This catches a
# dead simulator service before xcodebuild enters its much longer launch path.
if ! run_with_timeout 60 xcrun simctl boot "$SIM_UDID"; then
  echo "Failed to boot dedicated simulator $SIM_UDID." >&2
  exit 2
fi
if ! run_with_timeout 180 xcrun simctl bootstatus "$SIM_UDID" -b; then
  echo "Dedicated simulator failed to become ready: $SIM_UDID." >&2
  exit 2
fi

# verify-pr.sh is the local verifier and should keep its normal behavior. Patch a
# temporary CI-only copy to use the dedicated simulator and to enforce timeouts
# around xcodebuild test / final boot / launch operations.
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
    | sed "s/^SIM_NAME=\"$BASE_SIM_NAME\"$/SIM_NAME=\"$SIM_NAME\"/" \
    | sed 's/if ! xcodebuild test \\/if ! ci_xcodebuild test \\/g' \
    | sed 's/xcrun simctl bootstatus \"$UDID\" -b/ci_run_with_timeout 180 xcrun simctl bootstatus \"$UDID\" -b/g' \
    | sed 's/xcrun simctl boot \"$UDID\"/ci_run_with_timeout 60 xcrun simctl boot \"$UDID\"/g' \
    | sed 's/LAUNCH_OUT=$(xcrun simctl launch \"$UDID\" \"$BID\")/LAUNCH_OUT=$(ci_run_with_timeout 60 xcrun simctl launch \"$UDID\" \"$BID\")/g'
} > "$TEMP_VERIFY"
chmod +x "$TEMP_VERIFY"

PATCHED_TEST_COUNT=$(grep -c 'if ! ci_xcodebuild test \\' "$TEMP_VERIFY" || true)
if [ "$PATCHED_TEST_COUNT" -ne 6 ]; then
  echo "Expected to wrap 6 xcodebuild test commands, wrapped $PATCHED_TEST_COUNT." >&2
  exit 2
fi

exec_status=0
XCODEBUILD_TEST_TIMEOUT_SECONDS="$XCODEBUILD_TEST_TIMEOUT_SECONDS" "$TEMP_VERIFY" "$@" || exec_status=$?
exit "$exec_status"
