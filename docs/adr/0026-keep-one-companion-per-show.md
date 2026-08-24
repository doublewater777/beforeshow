# Keep one companion per show

## Status

Superseded by ADR 0034 — 2026-08-24

## Context

The footprint-detail reference can visually accommodate multiple names, but BeforeShow originally defined companion sharing as one confirmed relationship per show. Footprint detail therefore showed at most one confirmed companion and hid absent, pending, or canceled relationships, avoiding a wider CloudKit invitation and permission-model redesign during the footprint-detail work.

## Decision

Keep one companion per show.

## Consequences

This constraint was later lifted. Companion sharing now uses one CloudKit share as a group, with multiple accepted members. See ADR 0034.
