---
name: pr-verifier
description: "Run local runtime verification for a GitHub PR at its current HEAD: isolated worktree, unit tests, signed simulator build, entitlements check, install and launch-survival on the iPhone 17 simulator, producing a SHA-bound LOCAL_AGENT_VERIFY report and posting it as a PR comment. Use when a PR needs local verification, a LOCAL_AGENT_VERIFY PASS is required for merge readiness, or a new commit must be re-verified."
---

# PR Verifier

Produce the local verification evidence that `pr-builder` reports and `pr-reviewer` consumes. You are the verifier, not the builder and not the reviewer.

## Hard role boundary

- Do not edit repository source files (the verification worktree is disposable).
- Do not fix findings, commit, push, merge, or review code.
- Do not issue APPROVE/REQUEST_CHANGES verdicts — that is `pr-reviewer`'s job.
- If verification exposes a bug, report it as a FAIL; the fix belongs to `pr-builder`.

## Establish the target

1. Identify the PR. Record its exact current HEAD SHA before starting.
2. If the PR HEAD changes while verifying, discard the in-progress result and re-verify the new HEAD.

## Run verification

```bash
scripts/verify-pr.sh <PR_NUMBER>            # from the repo root
scripts/verify-pr.sh                        # PR of the current branch
scripts/verify-pr.sh <PR_NUMBER> --no-comment   # skip the PR comment
```

The script performs, in order:

1. Detached worktree of the PR HEAD under `/tmp/beforeshow-verify/`
2. `xcodebuild test` (unit tests + signed simulator build, `DEVELOPMENT_TEAM` explicit)
3. Entitlements check — `icloud-container-identifiers` must be present (detects the ad-hoc signing regression)
4. Install + launch on the iPhone 17 simulator, process must survive 5 seconds
5. `LOCAL_AGENT_VERIFY` report to stdout; exit code 0 = PASS, 1 = FAIL
6. PR comment with the report (deduplicated per HEAD)

## Report format

The script's stdout (and the PR comment) contains exactly:

```text
LOCAL_AGENT_VERIFY
HEAD: <sha>
RESULT: PASS | FAIL
Environment: ...
Scenario: ...
Evidence:
  - ...
```

A PASS is valid only for the reported SHA. Any new commit on the PR invalidates every previous PASS — re-run the script against the new HEAD.

## Optional UI agent

For changes where launch-survival is not enough (navigation flows, dynamic UI), use Codex for the UI check — it has the computer-use plugin:

1. Dispatch the `codex:codex-rescue` subagent (forwards one task to Codex) with: the exact scenario to verify, the app bundle id from the build, the booted simulator name, and the PR HEAD SHA. Ask Codex to drive the app in the simulator and report concrete observations.
2. Append Codex's observations to the Evidence lines. A UI verification failure is a FAIL.

## Handoff

- The result reaches the PR as a `LOCAL_AGENT_VERIFY` comment — this is the script's default behavior; never run with `--no-comment` in the normal flow.
- After the comment is posted, hand off to `pr-builder` in a new conversation: use computer use to open Chrome, start a new chat, and give it the PR number, the exact HEAD SHA, and the PASS/FAIL result. `pr-builder` loops on FAIL and proceeds to review on PASS.
- Never claim a PASS that the script did not print, and never upgrade a FAIL to PASS without re-running.
