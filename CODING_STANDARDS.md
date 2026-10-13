# Coding Standards

Review-time standards for BeforeShow. Implementation agents should not load this whole file into working memory; reviewers should.

## Source of truth

- iOS boundaries: `apps/ios/ARCHITECTURE.md`

- Domain language: `GLOSSARY.md`

- Hard decisions: `docs/adr/`

- Commit subject: `docs/agents/commit-convention.md`

## Review focus

- Prefer deep modules with simple interfaces over many shallow helpers.

- Test behavior at seams; do not lock tests to private helpers.

- Legacy hotspots only shrink: `RootView.swift`, `AddShowFlowViews.swift`, `FootprintsArchive.swift`, `FootprintArchiveViews.swift`, `MemoryFragmentsView.swift`.

- New Swift sources go under `BeforeShow/Features/<Feature>/` by default; never use `Shared/` as a dumping ground.

- Keep presentation discipline: one primary surface per user transaction.

- Mechanical violations belong in scripts/hooks/CI, not more prompt text.

## When adding a rule

1. Prefer a deterministic check (`apps/ios/scripts/check_architecture.py`, hooks, tests).

2. If it needs judgement, add a short bullet here and point to an ADR or architecture section.

3. Do not grow `AGENTS.md` with review-only rules.
