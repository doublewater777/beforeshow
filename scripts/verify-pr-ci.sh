#!/usr/bin/env bash
# CI wrapper for verify-pr.sh.
# Creates a unique simulator per run so self-hosted CI does not contend with
# developers or another verifier using the shared "iPhone 17" simulator.
set -euo pipefail

BASE_SIM_NAME="iPhone 17"
RUN_SCOPE="${GITHUB_RUN_ID:-local-$$}-${GITHUB_RUN_ATTEMPT:-1}-${GITHUB_JOB:-verify}"
SIM_NAME="BeforeShow Verify ${RUN_SCOPE}"
TEMP_VERIFY="${RUNNER_TEMP:-/tmp}/verify-pr-${RUN_SCOPE}.sh"
SIM_UDID=""

cleanup() {
  rm -f "$TEMP_VERIFY"
  if [ -n "$SIM_UDID" ]; then
    xcrun simctl shutdown "$SIM_UDID" >/dev/null 2>&1 || true
    xcrun simctl delete "$SIM_UDID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

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

SIM_UDID=$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE_ID" "$RUNTIME_ID")
echo "==> Created dedicated simulator: $SIM_NAME ($SIM_UDID)"

# Do not pre-boot the device with simctl. On the self-hosted runner a wedged
# CoreSimulator bootstatus can block before tests even start. xcodebuild owns
# simulator booting for the test destination and is already responsible for
# waiting until the destination is usable.

# verify-pr.sh currently selects the simulator by name. Patch only the temporary
# executable copy so the source script stays unchanged and all existing local
# verifier behavior is preserved.
sed "s/^SIM_NAME=\"$BASE_SIM_NAME\"$/SIM_NAME=\"$SIM_NAME\"/" scripts/verify-pr.sh > "$TEMP_VERIFY"
chmod +x "$TEMP_VERIFY"

exec_status=0
"$TEMP_VERIFY" "$@" || exec_status=$?
exit "$exec_status"
