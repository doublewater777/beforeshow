---
name: ship-feature
description: "Own the complete GitHub development loop whenever the user asks to build, add, change, or fix a feature in a connected repository. Read the repository, implement the change, create or update one PR, wait for remote checks, consume LOCAL_AGENT_VERIFY reports from the local simulator verifier, repair failures, perform a fresh review, and report only when the same PR HEAD is ready."
compatibility: "Requires a connected GitHub workspace and the repository's local verifier when simulator validation is needed."
---

# Ship Feature

Act as the owner of the feature request. The user should receive a working PR, not a code recipe to copy.

## Operating loop

Track the workflow through the GitHub PR and its HEAD SHA. Do not use the conversation as the source of truth for whether an earlier verification still applies.

1. **DISCOVER**
   - Identify the repository, current branch, project rules, `AGENTS.md`, README, and the smallest relevant code surface.
   - If the repository is already clear from context, continue without asking the user to restate it.
   - State assumptions only when they change the implementation or verification path.

2. **BUILD**
   - Create or reuse one feature branch and one PR for the request.
   - Implement the smallest complete change, preserving the repository's conventions and localization rules.
   - Commit the change and keep updating the same PR as failures are found.

3. **REMOTE_VERIFY**
   - Read the PR's current CI checks, test results, and diff.
   - Treat a result as stale when its reported HEAD SHA is not the PR's current HEAD.
   - Do not ask the user to paste logs that are already available on the PR.

4. **LOCAL_AGENT_VERIFY**
   - For iOS changes, the repository's verifier is `tools/ship-verify`.
   - The local loop can be started with `tools/ship-verify watch --pr <number> --publish`.
   - Expect a report shaped like `LOCAL_AGENT_VERIFY`, including `HEAD`, `RESULT`, environment, scenario, and evidence.
   - Require `RESULT: PASS` for the current PR HEAD before proceeding. A PASS for an older SHA does not count.
   - If the report is FAIL, read its evidence, fix the code, push a new commit, and wait for the next SHA-matched report.
   - If no local verifier is running, explain the one command needed to start it; do not claim local verification passed.

5. **REVIEW**
   - Re-read the current PR diff from scratch after the last code change.
   - Look for behavior regressions, missing tests, data-loss paths, entitlement/signing issues, accessibility/localization regressions, and stale assumptions.
   - Review must target the same HEAD that passed CI and local verification.

6. **READY**
   - Declare the PR ready only when CI PASS, `LOCAL_AGENT_VERIFY PASS`, and fresh review all refer to the same HEAD SHA.
   - Do not merge unless the user explicitly asks for merging.
   - Keep the final response short: PR link, current HEAD, checks, local scenario, and any remaining limitation.

## Local verifier contract

The verifier is the execution side of this Skill. It owns the simulator, not the Chat context:

```text
PR HEAD → local checkout → tests → build → simulator → UI scenario → PR report
```

The optional UI agent command receives these environment variables:

```text
VERIFY_REPO_ROOT
VERIFY_HEAD_SHA
VERIFY_APP_PATH
VERIFY_SIMULATOR_UDID
VERIFY_BUNDLE_ID
VERIFY_REPORT_PATH
```

Use the cheapest reliable check first. Static checks and tests come before simulator interaction; use Computer Use, AXe, or another local UI agent only for behavior that those checks cannot prove.

## Communication rule

Do not expose internal state-machine jargon unless it helps the user make a decision. Report concrete outcomes such as “PR #61 is waiting for a local iPhone 17 verification” or “the current HEAD failed because the save spinner never finished.”
