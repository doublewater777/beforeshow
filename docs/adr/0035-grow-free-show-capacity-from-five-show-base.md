# Grow free show capacity from a five-show base

## Status

Accepted — 2026-09-26

## Context

BeforeShow originally treated Pro conversion as a saved-show limit. The shipping gate later evolved into a monthly "add one show" rule, while product and App Store documents still described a one-show free allowance. That left three incompatible meanings for the same limit: lifetime capacity, monthly additions, and current saved count.

The new free tier should let a new user build a meaningful footprint before seeing a paywall, while still preserving a gradual reason for frequent long-term users to choose Pro. Deleting a show should not feel like permanently burning an allowance, and accepting a companion invitation should not consume a user's own free capacity.

## Decision

Model the free tier as **saved self-added show capacity**, not historical add attempts.

- Free users have a base capacity of 5 self-added shows.
- In each local calendar month, free capacity may grow by 1 above the month's free baseline. Unused monthly growth does not roll over.
- The effective free limit for a month is `max(6, monthlyBaseline + 1)`.
- A new or below-base user can therefore fill the five-show base and still add a sixth show in the same month.
- Deleting a self-added show immediately frees capacity. The user may refill up to the same month's limit; deletion does not consume a permanent add attempt.
- Future, live, ended, and Footprints shows all count while they remain saved.
- A show created only by accepting a companion invitation does not count. A self-added show that is later merged with a companion invitation continues to count.
- Pro has unlimited capacity. Existing shows remain accessible after Pro expires.
- When a user transitions from Pro to free, the current self-added show count becomes that month's free baseline if the month has not already initialized a free baseline.
- A local calendar month initializes its free baseline at most once. Repeated Pro/free entitlement changes in the same month cannot grant repeated monthly growth.
- When this policy first ships, an existing user's current self-added show count becomes the migration month's baseline. The app does not attempt to reconstruct deleted historical shows.
- On the next local calendar month, the baseline is recalculated from the self-added shows that remain saved at that boundary.

Examples:

- Month starts at 0 → free limit 6.
- Month starts at 5 → free limit 6.
- Month starts at 8 → free limit 9.
- Month starts at 8, user deletes to 4 → the user may refill up to 9 during that month.
- Pro expires at 25 saved self-added shows → free limit becomes 26 for that month, unless that month already established its free baseline.

## Consequences

- Pro's paid value remains unlimited saved shows, but the paywall moves later than the original one-show model.
- The existing "shows added this month" gate is no longer the correct domain model; implementation must persist or otherwise derive a monthly free-capacity baseline.
- Limit UI should explain the current capacity rule rather than say "one show per month."
- Product, business-model, App Store, ASO, settings, paywall, localization, and regression-test copy must converge on this policy.
- Historical cycle documents may retain their original assumptions when they are clearly historical evidence; current source-of-truth documents must use this ADR.
