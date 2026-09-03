#!/usr/bin/env bash
# verify-pr.sh — BeforeShow PR 本地运行时验证（local verifier）
#
# 隔离 worktree → xcodegen → architecture guard → Phase 1 / Phase 2 定向 signed tests
# → 完整 signed tests → entitlements 检查 → 安装到 iPhone 17 模拟器
# → 启动存活检查 → LOCAL_AGENT_VERIFY 报告 → （可选）PR comment。
#
# Usage:
#   scripts/verify-pr.sh [PR_NUMBER] [--no-comment]
#
# 不带 PR_NUMBER 时取当前分支的 PR。
# 退出码：0 = PASS，1 = FAIL，2 = 前置条件失败（找不到 PR 等）。
set -euo pipefail

TEAM=29C8MS76CZ
SCHEME=BeforeShow
SIM_NAME="iPhone 17"
REPO_ROOT="$(git rev-parse --show-toplevel)"

PR=""
NO_COMMENT=0
for arg in "$@"; do
  case "$arg" in
    --no-comment) NO_COMMENT=1 ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) PR="$arg" ;;
  esac
done

if [ -z "$PR" ]; then
  PR=$(gh pr view --json number --jq .number) \
    || { echo "当前分支没有 PR，请显式传入 PR 编号。" >&2; exit 2; }
fi

SHA=$(gh pr view "$PR" --json headRefOid --jq .headRefOid)
SHORT=${SHA:0:12}
echo "==> Verifying PR #$PR @ $SHA"

if ! git cat-file -e "$SHA^{commit}" 2>/dev/null; then
  git fetch origin "$SHA" 2>/dev/null || git fetch origin "pull/$PR/head"
  if ! git cat-file -e "$SHA^{commit}" 2>/dev/null; then
    echo "fetch 后仍找不到 HEAD $SHORT（PR 可能刚更新），请重试。" >&2
    exit 2
  fi
fi
WORKTREE="/tmp/beforeshow-verify/pr$PR-$SHORT"
git worktree remove --force "$WORKTREE" 2>/dev/null || true
rm -rf "$WORKTREE"
git worktree prune
git worktree add --detach "$WORKTREE" "$SHA" >/dev/null
PROJECT="$WORKTREE/apps/ios/BeforeShow.xcodeproj"
DD="$WORKTREE/apps/ios/DerivedData-verify"
LOG_DIR="$WORKTREE/.verify"
mkdir -p "$LOG_DIR"

RESULT=PASS
EVIDENCE=()

# New/moved Swift files are declared through project.yml. Always regenerate the
# isolated verifier project so the exact PR HEAD, not a stale committed pbxproj,
# is what Xcode compiles.
echo "==> XcodeGen"
if ! (cd "$WORKTREE/apps/ios" && xcodegen generate) > "$LOG_DIR/xcodegen.log" 2>&1; then
  RESULT=FAIL
  tail -80 "$LOG_DIR/xcodegen.log" || true
  EVIDENCE+=("xcodegen: FAILED (log: $LOG_DIR/xcodegen.log)")
else
  EVIDENCE+=("xcodegen: PASS")
fi

# --- Architecture guard ---
if [ "$RESULT" = PASS ]; then
  echo "==> Architecture guard"
  if ! python3 "$WORKTREE/apps/ios/scripts/check_architecture.py" > "$LOG_DIR/architecture.log" 2>&1; then
    RESULT=FAIL
    echo "architecture guard FAILED："
    tail -80 "$LOG_DIR/architecture.log" || true
    EVIDENCE+=("architecture: FAILED (log: $LOG_DIR/architecture.log)")
  else
    EVIDENCE+=("architecture: PASS")
  fi
fi

# --- Phase 1 定向 signed tests ---
if [ "$RESULT" = PASS ]; then
  echo "==> Phase 1 targeted signed tests ($SCHEME, $SIM_NAME)"
  if ! xcodebuild test \
      -project "$PROJECT" -scheme "$SCHEME" \
      -destination "platform=iOS Simulator,name=$SIM_NAME" \
      -allowProvisioningUpdates DEVELOPMENT_TEAM=$TEAM \
      -derivedDataPath "$DD" \
      -only-testing:BeforeShowTests/CurrentShowSessionTests \
      -only-testing:BeforeShowTests/ShowMutationCoordinatorTests \
      -only-testing:BeforeShowTests/LocalNotificationSchedulingTests \
      -resultBundlePath "$LOG_DIR/phase1-tests.xcresult" \
      > "$LOG_DIR/phase1-test.log" 2>&1; then
    RESULT=FAIL
    echo "Phase 1 targeted tests FAILED — 最后 80 行："
    tail -80 "$LOG_DIR/phase1-test.log" || true
    EVIDENCE+=("phase1 targeted tests: FAILED (log: $LOG_DIR/phase1-test.log)")
  else
    SUITE=$(grep -E "Test Suite 'All tests' (passed|failed)" "$LOG_DIR/phase1-test.log" | tail -1 | sed 's/^ *//' || true)
    EVIDENCE+=("phase1 targeted tests: ${SUITE:-passed} (xcresult: $LOG_DIR/phase1-tests.xcresult)")
  fi
fi

# --- Phase 2 persistence signed tests ---
if [ "$RESULT" = PASS ]; then
  echo "==> Phase 2 targeted signed tests ($SCHEME, $SIM_NAME)"
  if ! xcodebuild test \
      -project "$PROJECT" -scheme "$SCHEME" \
      -destination "platform=iOS Simulator,name=$SIM_NAME" \
      -allowProvisioningUpdates DEVELOPMENT_TEAM=$TEAM \
      -derivedDataPath "$DD" \
      -only-testing:BeforeShowTests/ListeningPersistenceTests \
      -only-testing:BeforeShowTests/ListeningDeletionTests \
      -resultBundlePath "$LOG_DIR/phase2-tests.xcresult" \
      > "$LOG_DIR/phase2-test.log" 2>&1; then
    RESULT=FAIL
    echo "Phase 2 targeted tests FAILED — 最后 80 行："
    tail -80 "$LOG_DIR/phase2-test.log" || true
    EVIDENCE+=("phase2 targeted tests: FAILED (log: $LOG_DIR/phase2-test.log)")
  else
    SUITE=$(grep -E "Test Suite 'All tests' (passed|failed)" "$LOG_DIR/phase2-test.log" | tail -1 | sed 's/^ *//' || true)
    EVIDENCE+=("phase2 targeted tests: ${SUITE:-passed} (xcresult: $LOG_DIR/phase2-tests.xcresult)")
  fi
fi

# --- 完整 signed tests；同一 DerivedData 复用已下载依赖 ---
if [ "$RESULT" = PASS ]; then
  echo "==> Full signed xcodebuild test ($SCHEME, $SIM_NAME)"
  rm -rf "$LOG_DIR/tests.xcresult"
  if ! xcodebuild test \
      -project "$PROJECT" -scheme "$SCHEME" \
      -destination "platform=iOS Simulator,name=$SIM_NAME" \
      -allowProvisioningUpdates DEVELOPMENT_TEAM=$TEAM \
      -derivedDataPath "$DD" \
      -resultBundlePath "$LOG_DIR/tests.xcresult" \
      > "$LOG_DIR/test.log" 2>&1; then
    RESULT=FAIL
    echo "xcodebuild test FAILED — 最后 80 行："
    tail -80 "$LOG_DIR/test.log" || true
    EVIDENCE+=("full signed tests: FAILED (log: $LOG_DIR/test.log)")
  else
    SUITE=$(grep -E "Test Suite 'All tests' (passed|failed)" "$LOG_DIR/test.log" | tail -1 | sed 's/^ *//' || true)
    EVIDENCE+=("full signed tests: ${SUITE:-passed} (xcresult: $LOG_DIR/tests.xcresult)")
  fi
fi

APP=$(find "$DD/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name "*.app" 2>/dev/null | head -1 || true)
if [ "$RESULT" = PASS ]; then
  ENT_HITS=$(find "$DD/Build/Intermediates.noindex" -name "Entitlements-Simulated.plist" \
    -exec grep -l "icloud-container-identifiers" {} + 2>/dev/null | wc -l | tr -d ' ')
  if [ "$ENT_HITS" -eq 0 ]; then
    RESULT=FAIL
    EVIDENCE+=("entitlements: icloud-container-identifiers MISSING（签名退化为 ad-hoc）")
  else
    EVIDENCE+=("entitlements: icloud-container-identifiers present ($ENT_HITS plist)")
  fi
fi

if [ "$RESULT" = PASS ]; then
  if [ -z "$APP" ] || [ ! -d "$APP" ]; then
    RESULT=FAIL
    EVIDENCE+=("launch: built .app not found")
  else
    BID=$(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")
    UDID=$(xcrun simctl list devices | sed -n "s/^ *$SIM_NAME (\([A-F0-9-]*\)) (Booted)[[:space:]]*\$/\1/p" | head -1 | tr -d '[:space:]')
    if [ -z "$UDID" ]; then
      UDID=$(xcrun simctl list devices | sed -n "s/^ *$SIM_NAME (\([A-F0-9-]*\)) (Shutdown)[[:space:]]*\$/\1/p" | head -1 | tr -d '[:space:]')
      if [ -z "$UDID" ]; then
        RESULT=FAIL
        EVIDENCE+=("launch: iPhone 17 simulator not found")
      else
        echo "==> Booting $SIM_NAME ($UDID)"
        xcrun simctl boot "$UDID"
      fi
    fi

    if [ "$RESULT" = PASS ]; then
      xcrun simctl shutdown "$UDID" 2>/dev/null || true
      xcrun simctl boot "$UDID"
      xcrun simctl bootstatus "$UDID" -b >/dev/null
      LAUNCH_OK=0
      LAUNCH_OUT=""
      for ATTEMPT in 1 2; do
        xcrun simctl uninstall "$UDID" "$BID" 2>/dev/null || true
        xcrun simctl install "$UDID" "$APP"
        LAUNCH_OUT=$(xcrun simctl launch "$UDID" "$BID")
        sleep 5
        if xcrun simctl spawn "$UDID" launchctl list | grep -Fq "UIKitApplication:$BID"; then
          LAUNCH_OK=1
          if [ "$ATTEMPT" = 1 ]; then
            EVIDENCE+=("launch: $LAUNCH_OUT — 进程 5 秒后仍存活")
          else
            EVIDENCE+=("launch: 第 1 次启动瞬时退出，第 2 次重装启动存活: $LAUNCH_OUT")
          fi
          break
        fi
        [ "$ATTEMPT" = 1 ] && sleep 2
      done
      if [ "$LAUNCH_OK" = 0 ]; then
        RESULT=FAIL
        EVIDENCE+=("launch: 两次安装启动均在 5 秒内退出 (last: $LAUNCH_OUT)")
        CRASH=$(find ~/Library/Logs/DiagnosticReports -maxdepth 1 -iname "*beforeshow*" -mmin -10 2>/dev/null | head -1 || true)
        [ -n "$CRASH" ] && EVIDENCE+=("crash report: $CRASH")
      fi
      xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
    fi
  fi
fi

ENV_DESC="Xcode $(xcodebuild -version | head -1 | awk '{print $2}'), simulator \"$SIM_NAME\", DEVELOPMENT_TEAM=$TEAM"
SCENARIO="xcodegen + architecture + Phase 1/2 定向 signed tests + 完整 signed tests + entitlements + iPhone 17 安装 + 5 秒启动存活"

REPORT=$(cat <<EOF
LOCAL_AGENT_VERIFY
HEAD: $SHA
RESULT: $RESULT
Environment: $ENV_DESC
Scenario: $SCENARIO
Evidence:
$(printf '  - %s\n' "${EVIDENCE[@]}")
EOF
)

echo
echo "$REPORT"

if [ "$NO_COMMENT" = 0 ]; then
  if gh pr view "$PR" --json comments --jq '.comments[].body' \
      | grep -Fq "verify-pr" \
      && gh pr view "$PR" --json comments --jq '.comments[].body' | grep -Fq "HEAD: $SHA"; then
    echo "==> PR #$PR 已有 HEAD $SHORT 的 verify-pr 报告，跳过 comment"
  else
    { echo "## verify-pr — $RESULT"
      echo
      echo '```text'
      echo "$REPORT"
      echo '```'
    } > "$LOG_DIR/comment.md"
    gh pr comment "$PR" --body-file "$LOG_DIR/comment.md" >/dev/null
    echo "==> 已发 PR comment"
  fi
fi

echo "==> Worktree 与日志保留在 $WORKTREE (清理: git worktree remove --force \"$WORKTREE\")"
[ "$RESULT" = PASS ]
