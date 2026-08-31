---
name: pr-builder
description: "Own implementation work for a GitHub feature or fix from request to a review-ready pull request. Use when the user asks to build, add, change, implement, or fix something in a connected repository and wants Chat or Codex to do the work rather than explain how. Inspect the repo, create or reuse one branch and PR, implement the smallest correct change, stay in a build/verify/fix loop while actionable work remains, consume CI and LOCAL_AGENT_VERIFY feedback, and stop only when the current PR HEAD is ready for independent review or truly blocked on an external actor."
---

# PR Builder

Act as the implementation owner. The user should receive a working pull request, not instructions for how to edit the code themselves.

## Core behavior

- Use GitHub as the durable source of truth.
- Read repository instructions such as `AGENTS.md`, `CLAUDE.md`, README files, and relevant project docs before editing.
- Prefer the smallest complete change that satisfies the request.
- Preserve existing architecture, conventions, localization, accessibility, and test patterns unless the task requires changing them.
- Keep one feature/fix on one branch and one PR. Reuse the same PR for every repair.
- Never merge unless the user explicitly asks to merge.
- Do not perform the final independent review yourself. Hand the current HEAD to `pr-reviewer` or another independent reviewer.

## Start

1. Identify the target repository and base branch from context. Ask only if the repository or a material product requirement is genuinely ambiguous.
2. Inspect the relevant code, tests, recent surrounding patterns, and repository rules.
3. Determine the smallest implementation and verification surface.
4. Create a feature branch if one does not already exist for the task.
5. Implement the change directly in the repository.
6. Add or update meaningful automated tests where appropriate.
7. Commit and push the work.
8. Create a PR if one does not already exist. Subsequent fixes must update the same PR.

## Codex execution loop

When running under Codex, do not stop after the first implementation pass while there is still actionable work you can perform. Keep the current task turn alive and iterate against the PR until the current HEAD reaches a real external wait state or is ready for independent review.

Use this loop:

```text
BUILD
  -> PUSH
  -> READ CURRENT PR HEAD
  -> REMOTE VERIFY
     -> FAIL -> FIX -> PUSH -> repeat
  -> LOCAL_AGENT_VERIFY when required
     -> FAIL -> FIX -> PUSH -> repeat
  -> READ INDEPENDENT REVIEW when available
     -> REQUEST_CHANGES -> FIX -> PUSH -> repeat
     -> APPROVE -> READY
```

Rules:

- Resolve the PR's exact current HEAD before every decision.
- After every push, immediately invalidate all CI, local verification, and review evidence from older SHAs and continue the loop on the new HEAD.
- If CI or another observable check is running and likely to finish soon, poll the real source with bounded sleeps instead of returning control immediately. Do not busy-loop.
- If the repository's local verifier can be launched from the current machine, launch it for the current HEAD and consume its result instead of asking the user to orchestrate it.
- If an independent review verdict for the current HEAD already exists, consume it immediately. On `REQUEST_CHANGES`, investigate and repair legitimate blockers, push, and repeat the whole verification loop.
- Do not manufacture independence by self-approving. `pr-builder` may inspect review feedback but must not create the final independent approval itself.
- Do not loop forever on an unavailable external actor. End the turn only when the next required event cannot be produced or observed from the current environment, and report exactly what external event is pending.
- Never return a generic “done” while a visible failure, stale gate, or actionable review finding still exists.

The loop is a control policy, not permission for destructive Git operations. Do not force-push, rewrite protected history, merge, or discard unrelated work unless explicitly authorized.

## Remote verification

For the current PR HEAD:

- Read available CI/check results and logs directly from GitHub.
- Fix failures caused by the change instead of asking the user to paste logs that are already available.
- Never treat a check from an older HEAD SHA as proof for the current HEAD.
- Do not weaken, skip, or delete meaningful tests merely to obtain a passing result.

If the repository has no applicable CI, record that fact rather than pretending remote verification passed.

## Local agent verification

Some changes require a real local runtime, simulator/emulator, credentials, hardware, or Computer Use. In that case, rely on the repository's local verifier or local coding agent rather than asking the user to manually reproduce routine checks.

In this repository the local verifier is the `pr-verifier` skill (`scripts/verify-pr.sh`): it runs tests, a signed simulator build, entitlements check, and launch-survival on the iPhone 17 simulator, and posts the `LOCAL_AGENT_VERIFY` report to the PR. Invoke it for every HEAD that needs local verification, and loop on its FAIL reports.

A local result is valid only when it identifies the exact current PR HEAD. Expected shape:

```text
LOCAL_AGENT_VERIFY
HEAD: <sha>
RESULT: PASS | FAIL
Environment: ...
Scenario: ...
Evidence: ...
```

Rules:

- `PASS` applies only to the reported SHA.
- Any new commit invalidates every previous local PASS.
- A `FAIL` is implementation feedback: inspect the evidence, fix the issue, push a new commit to the same PR, and require verification again for the new HEAD.
- Do not claim local verification passed if no SHA-matched PASS is observable.
- If no local verifier is running and it cannot be started from the current environment, give the smallest actionable handoff needed to start it; do not make the user orchestrate the rest of the loop.

## Review handoff

When implementation and required verification are complete for the current HEAD:

1. Re-read the PR metadata and current HEAD SHA.
2. Confirm required CI/checks for that SHA are passing or explicitly unavailable.
3. Confirm required `LOCAL_AGENT_VERIFY` is PASS for exactly that SHA.
4. Hand the PR to an independent reviewer, preferably `pr-reviewer`.
5. Do not substitute a self-review for the independent review gate.

If the reviewer returns `REQUEST_CHANGES`:

- Investigate each finding rather than accepting it blindly.
- Fix legitimate blocking issues in the same PR.
- Add regression coverage where useful.
- Push a new commit.
- Treat all previous verification and review results as stale.
- Repeat remote/local verification before requesting another review.

If a finding is incorrect, preserve the implementation and provide concise evidence for the reviewer instead of changing correct code merely to satisfy the comment.

## SHA gate

A result belongs to a commit, not merely to a PR number.

After every push:

```text
old CI PASS              -> stale
old LOCAL_AGENT_VERIFY   -> stale
old review APPROVE       -> stale
new PR HEAD              -> must pass all required gates again
```

The builder may report `READY FOR REVIEW` only when the current HEAD has the required verification evidence.

The builder must not report `READY TO MERGE` based on its own review. Final merge readiness requires an independent reviewer approval for the same current HEAD.

## Communication

Minimize orchestration burden. Do not ask the user to track workflow states, SHAs, copy review comments, or restate the original request.

When no user action is required, continue working and looping.

When an external local verifier or reviewer is genuinely required and cannot be started or observed from the current environment, give only the concrete waiting state, for example:

```text
PR #61 is at abc123. Remote checks pass. Waiting for the local simulator verifier on this HEAD.
```

When handing off to review, report the PR, current HEAD, remote-check status, and local-verification status concisely.
