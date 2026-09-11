# Allow multiple companions per show

## Status

Accepted — 2026-08-24

## Context

Companion invitations already used one CloudKit `CKShare` per show (ADR 0024). The share can hold many participants, but the product layer kept a two-person group: a second accepted member was rejected, owner reconciliation stripped extras, and local `Show` stored a single `companionName`. ADR 0026 recorded that limit so footprint detail could ship without redesigning invitations.

Users going to a live event together are often more than two people. Rebuilding companion as pairwise sessions would duplicate CloudKit roots and break the existing share-sheet invite path.

## Decision

Keep one `CKShare` per show and allow multiple accepted non-owner members:

- Owner invites and adds people through the existing system sharing UI; adding more from a confirmed show re-presents that share instead of creating a new session.
- Session status stays `pending` until the first accept, then `accepted` for the whole group. Outstanding invites are not warnings.
- A participant leaving removes only their access. The session is not marked canceled while others remain. When the last accepted member is gone, owner refresh still closes the local relationship.
- Local cache stores `companionNames`. CloudKit share participant identities are the name source; the old single `participantDisplayName` field is only a fallback.
- Companion-sheet “共同足迹” matches exact name sets. Footprint identity counts each person pairwise. Share cards with two or more named companions print the names and skip a single ordinal.

## Consequences

- Owner cancel still dissolves the group and revokes the share.
- Same-name collisions and missing iCloud names remain, as in ADR 0027. There is still no stable cross-show companion ID.
- Participant devices see owner plus other accepted members, not themselves.
- No app-level member cap; avatar stacks collapse extras.
