# Experiments

Automated checks:

- Drafts without a start time fail validation.
- Missing link time stays missing rather than becoming midnight.
- OCR keeps useful partial fields but drops seat and sensitive ticket data.
- Link errors map to unsupported, retryable network, and invalid-response guidance.
- Notification post-save policy requests at most once and applies the new focus.
- Only T-14, T-1, and show-day notifications are scheduled.
- A canceled manual selection falls back to a valid show; a retention-expired show does not become current.

Simulator checks on iPhone 17:

- Exercise manual, failed-link fallback, and screenshot confirmation paths.
- Double-tap save and confirm only one show exists.
- Confirm completion feedback appears after the add sheet closes.
- Save one final screenshot of the changed add-show UI.
- Edit a show, trigger invalid time feedback, cancel a dirty draft, postpone it, and verify the status/delete separation.
- Save final screenshots of the changed editor and status surface.

Pass threshold: all targeted tests and the iOS build pass, and the final simulator walkthrough matches every success criterion.

Loop-back trigger: any path can still silently invent a required field or leave persistence/notification state partially updated.
