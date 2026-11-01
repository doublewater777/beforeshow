# Free fifteen shows flat capacity

## Status

Accepted — 2026-10-27  
Amended — 2026-10-31 (capacity 20 → 15 before 1.0.6 ship)

Supersedes [ADR 0042](0042-grow-free-show-capacity-from-five-show-base.md).

## Context

ADR 0042 modeled the free tier with a 5-show base plus a monthly +1 capacity growth rule. While this aimed to balance trial exploration and gradual conversion, the monthly baseline calculations, timezone monotonic boundary tracking, and complex rule explanation added friction for users and required intricate mental accounting.

To provide a generous, intuitive, and frictionless experience, BeforeShow simplifies the free capacity model starting in 1.0.6: free users directly receive a flat number of self-added shows. The initial draft used 20; before shipping 1.0.6 the free capacity was set to 15.

## Decision

1. **Flat free capacity**: Free users can save up to 15 self-added shows (`countsTowardFreeShowCapacity`).
2. **Remove monthly growth**: The base-5 plus monthly +1 mechanism and baseline calculation are discontinued.
3. **Delete releases capacity**: Deleting a saved self-added show immediately frees capacity. As long as current retained self-added shows < 15, the user can freely add new shows.
4. **Pro remains unlimited**: When reaching 15 shows, adding new shows requires upgrading to Pro. Pro users have unlimited capacity.
5. **Existing shows preserved**: When Pro expires, existing shows remain intact and fully viewable/editable; adding additional shows requires reducing retained count below 15 or renewing Pro.
