# Free twenty shows flat capacity

## Status

Accepted — 2026-10-27

Supersedes [ADR 0042](0042-grow-free-show-capacity-from-five-show-base.md).

## Context

ADR 0042 modeled the free tier with a 5-show base plus a monthly +1 capacity growth rule. While this aimed to balance trial exploration and gradual conversion, the monthly baseline calculations, timezone monotonic boundary tracking, and complex rule explanation added friction for users and required intricate mental accounting.

To provide a generous, intuitive, and frictionless experience, BeforeShow simplifies the free capacity model starting in 1.0.6: free users directly receive 20 free self-added shows.

## Decision

1. **Flat free capacity**: Free users can save up to 20 self-added shows (`countsTowardFreeShowCapacity`).
2. **Remove monthly growth**: The base-5 plus monthly +1 mechanism and baseline calculation are discontinued.
3. **Delete releases capacity**: Deleting a saved self-added show immediately frees capacity. As long as current retained self-added shows < 20, the user can freely add new shows.
4. **Pro remains unlimited**: When reaching 20 shows, adding new shows requires upgrading to Pro. Pro users have unlimited capacity.
5. **Existing shows preserved**: When Pro expires, existing shows remain intact and fully viewable/editable; adding additional shows requires reducing retained count below 20 or renewing Pro.
