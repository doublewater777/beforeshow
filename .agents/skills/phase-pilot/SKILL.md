---
name: phase-pilot
description: Turn a feature idea in an existing codebase into a deeply grilled, documented Spec with one cohesive Phase Plan, then have ChatGPT Web implement one fresh-conversation phase at a time while local Codex supervises exact-HEAD verification. Use for "聊透需求再分 Phase 开发" or "Web 开发、本地监督" workflows. Do not use for small one-session changes or ticket-based planning.
metadata:
  short-description: Grill, specify, phase, implement, and verify
---

# Phase Pilot

Run a two-surface development workflow:

- ChatGPT Web owns product discussion and implementation.
- Local Codex owns orchestration, independent verification, and phase gates.
- One Spec with an embedded Phase Plan is the canonical execution artifact.
- Do not generate or use `/to-tickets`. The user intentionally prefers cohesive phases over scattered tickets.

Use the same skill version on both surfaces. Conversation history is not shared automatically; durable repository and tracker artifacts are.

## Select the mode

Choose exactly one mode from the user's request and current state:

1. **Planner mode** — no approved Spec and Phase Plan exist yet.
2. **Phase implementation mode** — a fresh ChatGPT Web conversation has been assigned one approved phase.
3. **Supervisor mode** — local Codex has been asked to drive Web conversations and verify every phase through completion.

Do not combine planner and implementation work in one conversation. The planning conversation ends with a supervisor bootstrap brief; the supervisor starts Phase 1 in a fresh Web conversation.

## Shared context contract

Before acting, read the available canonical artifacts instead of relying on remembered chat history:

- repository instructions such as `AGENTS.md` and architecture documents
- the domain glossary such as `CONTEXT.md`
- relevant ADRs
- the approved Spec and its Phase Plan
- the latest integrated base SHA
- the active phase's PR and exact HEAD SHA
- exact verification reports bound to that SHA

Keep decisions in one canonical place. Do not copy the whole Spec into every conversation. Reference it by repository path or issue URL and include only a compact phase brief.

If Web cannot access the same skill files or repository artifacts, stop and ask the user to attach or paste them. Never pretend local skill context is automatically visible to Web.

## Planner mode

### 1. Establish repository context

Read the repository instructions, architecture, domain glossary, relevant ADRs, and existing implementation. Resolve factual codebase questions by inspection rather than asking the user.

### 2. Grill with docs

Invoke `/grill-with-docs` when available. Follow its discipline:

- ask one decision question at a time
- provide a recommended answer with each question
- walk dependencies in decision order
- update the glossary and ADRs as decisions become durable
- do not implement while unresolved questions remain

Keep this planning conversation unbroken through grilling, Spec creation, and Phase Plan approval. If it approaches an unsafe context size, use `/handoff` and continue in one fresh planning conversation before producing the Spec.

### 3. Produce the Spec

Invoke `/to-spec` when available. Synthesize the completed discussion; do not restart the interview. The Spec must cover the user problem, solution, user stories, implementation decisions, testing decisions, out-of-scope behavior, and agreed test seams.

### 4. Add the Phase Plan to the same Spec

Do not invoke `/to-tickets`. Add a `Phase Plan` section to the Spec. Each phase must fit one fresh implementation conversation and contain:

- **Outcome** — the coherent capability completed by the phase
- **Scope** — behavior and technical boundaries included
- **Out of scope** — what this phase must not begin
- **Prerequisite** — prior phase or integrated SHA required
- **Acceptance criteria** — observable completion conditions
- **Verification** — targeted tests, full regression expectations, and UI/runtime checks
- **Delivery** — one branch, one PR, and one reported final HEAD

Prefer cohesive product capabilities. Enabling infrastructure phases are acceptable only when later behavior genuinely depends on them and the phase remains independently verifiable.

Ask the user to approve the complete Phase Plan. Revise it in place rather than creating separate tickets or issues.

### 5. Emit the supervisor bootstrap brief

End planner mode with a compact brief containing:

- Spec path or URL
- ordered phase names
- current base branch and SHA
- non-negotiable product and architecture invariants
- Phase 1 acceptance and verification summary
- whether the user explicitly authorized commits, pushes, PR creation, and merges

Do not implement Phase 1 in the planning conversation.

## Phase implementation mode

This mode always runs in a fresh ChatGPT Web conversation dedicated to exactly one phase.

1. Read the Spec, full Phase Plan, repository instructions, glossary, relevant ADRs, and the assigned phase brief.
2. Confirm the required base branch and exact prerequisite SHA before editing.
3. Invoke `/implement` when available. Use TDD at the agreed seams and run code review before finalizing.
4. Modify only the assigned phase. Treat later phases and the Spec's global out-of-scope section as prohibited work.
5. Use one branch and one PR for the phase. Fix failures on that same branch and PR.
6. Do not start, plan, or partially implement the next phase.
7. Finish by reporting only the material handoff: PR URL, exact HEAD SHA, tests run, known limitations, and any divergence from the approved phase.

The Web implementer's tests are evidence, not the phase gate. Only local verification can pass the phase.

## Supervisor mode

Supervisor mode is a persistent local loop. It may control ChatGPT Web only when the user has authorized that browser interaction.

### 1. Establish the ledger

Read the approved Spec and Phase Plan. Record each phase as one of:

`planned → implementing → verifying → passed → merged`

Also record the current PR, exact HEAD, and integrated base SHA. A new commit invalidates every older verification result.

### 2. Start one fresh Web conversation per phase

For the first incomplete phase, create a new ChatGPT Web conversation and send a compact implementation brief. Include:

- instruction to invoke `$phase-pilot` in phase implementation mode
- Spec path or URL
- phase name and its full approved section
- repository constraints and critical invariants
- base branch and exact prerequisite SHA
- requirement for an independent branch, PR, and final HEAD
- explicit prohibition on entering the next phase

Default to serial integration: Phase N must be locally passed and merged before Phase N+1 branches from the new main HEAD. Use stacked PRs only when the user explicitly chooses them.

### 3. Verify independently

When Web reports a PR and HEAD:

- confirm the PR's actual current HEAD and base
- confirm the prerequisite SHA is an ancestor when required
- inspect scope for leakage into later phases
- run the repository's local verifier, such as `pr-verifier`, against the exact PR HEAD
- run independent review when required
- include signed build, entitlements, runtime survival, and UI evidence when relevant

Never convert a failing or incomplete run into PASS based on the Web implementer's claim.

### 4. Loop on failures

On FAIL, send the exact SHA-bound evidence to the same phase conversation. Require a fix on the same branch and PR, then verify the new HEAD from the beginning.

If that conversation grows too large, create a `/handoff` and open a fresh repair conversation for the same phase. This is not a new phase and must not create a second PR.

### 5. Pass, integrate, and advance

On PASS:

- record the exact passing HEAD
- merge only if the user's request explicitly authorized merging
- otherwise stop at the merge checkpoint and present a concise decision-ready brief
- after integration, verify the resulting main SHA when repository policy requires it
- update the phase ledger
- start the next phase in another fresh Web conversation

Do not advance while the previous phase is merely draft, unverified, failing, or unintegrated.

### 6. Finish the workflow

After the final phase, run the Spec's full regression and required manual/UI scenarios against the integrated result. The workflow is complete only when every phase is passed and integrated, the final regression passes, and no approved acceptance criterion remains open.

## Compact prompt templates

### Planner kickoff

```text
Use $phase-pilot in planner mode for this feature. Start with /grill-with-docs, one decision question at a time with a recommendation. Then create one Spec and an embedded Phase Plan. Do not create tickets and do not implement in this planning conversation.
```

### Phase implementation kickoff

```text
Use $phase-pilot in phase implementation mode. Implement only <Phase name> from <Spec URL/path>, based on <branch> at <SHA>. Respect AGENTS.md, architecture, glossary, ADRs, and this phase's Out of scope. Deliver one PR and report its exact final HEAD. Do not enter the next phase.
```

### Verification failure

```text
Local independent verification FAILED for <PR> at <SHA>. Fix only these exact failures on the same branch and PR, report the new HEAD, and do not enter the next phase:\n<evidence>
```

## Authorization boundary

This skill structures work; it does not expand permission. Browser messages, pushes, PR mutations, merges, and other external changes must remain within the user's explicit request. Never infer merge authorization merely from permission to supervise or verify.
