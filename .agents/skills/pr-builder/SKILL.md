---
name: pr-builder
description: "Own implementation work for a GitHub feature or fix from request to a review-ready pull request. Use when the user asks to build, add, change, implement, or fix something in a connected repository and wants Chat to do the work rather than explain how. Inspect the repo, create or reuse one branch and PR, implement the smallest correct change, consume CI and LOCAL_AGENT_VERIFY feedback, fix failures, and stop only when the current PR HEAD is ready for independent review."
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

## Remote verification

For the current PR HEAD:

- Read available CI/check results and logs directly from GitHub.
- Fix failures caused by the change instead of asking the user to paste logs that are already available.
- Never treat a check from an older HEAD SHA as proof for the current HEAD.
- Do not weaken, skip, or delete meaningful tests merely to obtain a passing result.

If the repository has no applicable CI, record that fact rather than pretending remote verification passed.

## Local agent verification

Some changes require a real local runtime, simulator/emulator, credentials, hardware, or Computer Use. In that case, rely on the repository's local verifier or local coding agent rather than asking the user to manually reproduce routine checks.

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
- If no local verifier is running, give the smallest actionable handoff needed to start the repository's verifier; do not make the user orchestrate the rest of the loop.

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

When no user action is required, continue working.

When an external local verifier is required, give only the concrete status and required handoff, for example:

```text
PR #61 is at abc123. Remote checks pass. Waiting for the local simulator verifier on this HEAD.
```

When handing off to review, report the PR, current HEAD, remote-check status, and local-verification status concisely.
