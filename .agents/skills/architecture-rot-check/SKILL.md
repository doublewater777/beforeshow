---
name: architecture-rot-check
description: Periodic BeforeShow architecture rot check. Use for scheduled anti-rot audits, weekly codebase health scans, or when asked to prevent code rot / architecture drift without implementing refactors yet.
disable-model-invocation: false
---

# Architecture Rot Check

Run a **read-only** anti-rot audit for BeforeShow. Discover debt; do not refactor unless the user explicitly asks to implement a selected candidate.

Default posture for scheduled runs: **hands-off**. Write the report, file issues when needed, stay quiet otherwise. Do not ask the user questions at the end of a scheduled run.

This skill is the scheduled front door. It composes:

- deterministic guard: `python3 apps/ios/scripts/check_architecture.py`
- deepening scan: `improve-codebase-architecture`
- optional entropy audit: `reclaim-code-entropy` in audit mode
- iOS boundaries: `apps/ios/ARCHITECTURE.md`
- domain language: `GLOSSARY.md` + `docs/adr/`

## Process

### 1. Baseline guardrails

1. Read `apps/ios/ARCHITECTURE.md`, `GLOSSARY.md`, and recent ADRs touching hotspots.
2. Run:

```bash
python3 apps/ios/scripts/check_architecture.py
```

3. Capture pass/fail. A failing guard is always a P0 finding.

### 2. Hotspot discovery

Prefer recent change hotspots over whole-repo sightseeing:

```bash
git log --since='14 days ago' --name-only --pretty=format: -- 'apps/ios/**/*.swift' | sed '/^$/d' | sort | uniq -c | sort -nr | head -40
```

Also inspect the oversize files pinned in `OVERSIZE_LINE_PINS` (`apps/ios/scripts/check_architecture.py`).

### 3. Architecture deepening scan

Follow `improve-codebase-architecture`:

- find shallow modules, leaked seams, hard-to-test interfaces
- use deletion test language from `codebase-design`
- do **not** edit business code
- for interactive runs, write HTML under `$TMPDIR/architecture-review-<timestamp>.html` and open it
- for scheduled / hands-off runs, skip opening HTML; the Markdown report is enough

### 4. Entropy scan (light)

Follow `reclaim-code-entropy` in **audit** mode only:

- look for unconsumed surfaces, mirrored facts, speculative generality, forwarding-only layers
- rank only evidence-backed candidates
- finding nothing safe to remove is valid

### 5. Persist a durable summary

Write Markdown to:

`docs/agents/architecture-reviews/YYYY-MM-DD.md`

Required sections:

1. **Guardrails** — `check_architecture.py` result
2. **Hotspots** — top changed files / legacy files reviewed
3. **Deepening candidates** — Strong / Worth exploring / Speculative
4. **Entropy candidates** — only proved ones
5. **Recommended next action** — one primary candidate, or "no action"
6. **Do not reopen** — ADR conflicts to leave alone
7. **Filed issues** — links created this run, or "none"

Keep the report short. No speculative rewrite plans.

### 6. Hands-off follow-up

For scheduled runs:

1. Search open GitHub issues for an existing anti-rot issue covering the same candidate/title before creating a duplicate.
2. If the architecture guard failed, create or update one issue labeled `needs-triage` with the failing command output and report path.
3. If there is exactly one clear **Strong** deepening candidate, create one issue labeled `needs-triage` summarizing:
   - files involved
   - why it is Strong
   - recommended next step: grill → spec → implement
   - link to the Markdown report
4. Do **not** file issues for Worth exploring / Speculative alone.
5. Do **not** auto-implement, open a PR, or commit.
6. Do **not** ask the user which candidate to explore.
7. Stay completely quiet when: guard passed AND no Strong candidate AND no material hotspot growth vs the latest prior report AND no new issue was filed.
8. Notify only when a new issue was filed, a prior Strong item clearly worsened, or the run itself failed.

Interactive manual runs may still present candidates and ask which one to grill.

## BeforeShow constraints

- Prefer shrinking oversize files over inventing new abstraction layers.
- Do not propose large-font / VoiceOver / compatibility work.
- Do not dump feature code into `Shared/`.
- New Swift files belong under `BeforeShow/Features/<Feature>/` unless App/Domain/Infrastructure/UI is clearly correct.
