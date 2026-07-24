# Add and Edit Show Flow Reliability

Stage: business-model

Target user: a live-music attendee adding a real upcoming show to BeforeShow.

User problem: adding or editing a show can accept incomplete data, fail to keep the current-show notifications aligned, hide persistence failures, or make status changes feel destructive and ambiguous.

Desired behavior change: every saved change is explicit, recoverable before persistence, reflected in the current-show focus and its notifications, and confirmed only after persistence succeeds.

Success:

- Manual, link, and screenshot paths only save after name and start time are confirmed.
- Link and OCR failures preserve useful draft fields and show actionable guidance.
- One save gesture creates exactly one show.
- Notification permission and focus scheduling run after persistence succeeds.
- Screenshot OCR does not retain seat, order, price, or identity data.
- Temporary local cover files are removed when abandoned or replaced.
- Editing protects unsaved changes, explains invalid time ranges inline, and only dismisses after a successful save.
- Postponement and cancellation live in a clear status section; deletion remains separate.
- Canceled and retention-expired shows cannot silently become the current show.
- Editing, postponing, canceling, deleting, or switching focus resynchronizes local notifications.
- The flow builds and its relevant tests pass on iPhone 17.

Out of scope:

- New ticket providers.
- Server-side OCR.
- Notification redesign.
- Changes to Pro pricing or the one-show free allowance.
