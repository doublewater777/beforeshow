# Agent Workflow Usage

Use this file as the convention for when to apply the installed engineering skills in BeforeShow.

## TDD

Use `tdd` for domain logic, state models, and behaviors that can be verified through a clean interface:
- SwiftData model mutations, validation, and lifecycle transitions
- MusicKit catalog matching and candidate song logic
- Show link parsing and platform detection
- CD player state transitions and playback queue mechanics
- Countdown calculation and time semantics
- Notification scheduling logic

Do not write fragile UI implementation-detail tests that assert private view hierarchies. Test through public interfaces or state containers.

## Diagnose

Use `diagnosing-bugs` when a bug, crash, failing test, or performance regression is reported.

Start by building a deterministic feedback loop: a failing test, a focused xcodebuild command, or a simulator reproduction. Do not patch from intuition without reproducing first.

## Handoff

Use `handoff` when work spans multiple sessions, touches several modules, or leaves follow-up tasks.

The handoff should include the goal, completed work, unfinished work, changed files, verification steps, and any unresolved decisions.

## Architecture Evolution

Use `improve-codebase-architecture` when BeforeShow code becomes harder to change because concepts are mixed, public interfaces are too wide, or legacy hotspots grow.

Adhere to `apps/ios/ARCHITECTURE.md` and check boundaries with `python3 apps/ios/scripts/check_architecture.py`.

Create an ADR in `docs/adr/` only when a decision is hard to reverse, surprising without context, and the result of a real trade-off.

## Domain Modeling

Use `domain-modeling` or `grill-with-docs` when introducing new features, shaping language, or updating `CONTEXT.md`. Always use the ubiquitous language defined in `CONTEXT.md`.
