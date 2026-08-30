# Classify added shows by lifecycle, not entry point

BeforeShow exposes one user-facing action, 「添加现场」, from both Current and Footprints. The entry point does not select a historical/upcoming persistence mode; the show's lifecycle determines whether it becomes current, schedules notifications, or appears in Footprints, and the user is asked only when the show may still be live. This keeps two convenient entry points without maintaining two drifting domain intents.

## Consequences

- A newly added future show does not replace an existing current show; a user-confirmed live show does.
- Clearly ended shows enter Footprints without a separate backfill mode or automatically triggering the post-show ceremony.
- Duplicate detection happens before the monthly Pro quota; past and future new shows share the same quota.
- A show added after it started only schedules notifications that are still meaningful in the future; missed notifications are not backfilled.
