# Implementation

Build:

- Represent missing draft start time explicitly and validate it before creating a `Show`.
- Preserve partial OCR/link drafts and distinguish actionable link failures.
- Remove seat extraction from screenshot OCR.
- Make save single-flight, roll back failed persistence, then request/schedule notifications.
- Dismiss immediately after completion and surface success in the presenting screen.
- Track local cover ownership and delete abandoned/replaced files.
- Give the editor an asynchronous save contract so persistence failures keep the sheet open.
- Add dirty-draft protection and inline schedule validation.
- Separate ordinary status changes from deletion, with state-specific recovery copy.
- Centralize current-show persistence and notification rescheduling across list and detail actions.
- Add focused regression tests.

Do not build:

- Additional import methods or providers.
- Background parsing.
- A new notification settings surface.

Dependencies:

- SwiftData model context.
- Vision on-device OCR.
- `UNUserNotificationCenter`.
- Existing design-system toast and sheet components.
