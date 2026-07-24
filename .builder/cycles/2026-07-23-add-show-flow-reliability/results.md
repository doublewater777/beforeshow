# Results

Implementation complete.

Behavior verified in code and regression tests:

- Draft start time is optional until the user confirms it; saving without one throws `missingStartTime`.
- Link parsing no longer invents midnight when the source omits or contains an invalid time.
- OCR keeps useful partial name/city/venue data, while seat and sensitive ticket fields are discarded.
- Unsupported-source, network, invalid-response, and generic link failures receive distinct recovery copy.
- Save is single-flight, persists before activating notifications, and rolls back failed SwiftData writes.
- Notification permission is requested contextually after the first successful save and focus scheduling is applied to the new show.
- Success feedback is owned by the presenting screen after the add flow closes.
- Imported local covers are removed when replaced, abandoned, edited away, or deleted with their show.
- The editor keeps a dirty draft open, confirms destructive dismissal, and only closes after its async save succeeds.
- The editor's cover is a clipped compact preview, so the title and core fields remain visible in the first viewport.
- Edit fields are grouped as basic information, schedule, location, and cover; the image-URL field is collapsed by default.
- Postponement and cancellation are reversible status actions, while permanent deletion is isolated in a separate “更多” section.
- Canceled shows cannot be set as current, retention-expired shows no longer become a fallback current show, and focus-affecting changes reschedule notifications.
- Notification cleanup removes legacy records and schedules only T-14, T-1, and show-day reminders.

Verification evidence:

- Focused current-show, notification, draft, and model tests: 54 passed, 0 failed.
- Full iOS test suite on iPhone 17 Pro / iOS 26.5: 81 passed, 0 failed.
- Generic iOS Simulator debug build: succeeded.
- `git diff --check`: passed.
- Final manual-add UI screenshot:
  `docs/screenshots/2026-07-23-add-show-reliability-manual.png`.
- Final edit-flow screenshots:
  - `docs/screenshots/2026-07-23-edit-show-editor.png`
  - `docs/screenshots/2026-07-23-edit-show-discard-confirmation.png`
  - `docs/screenshots/2026-07-23-edit-show-status-management.png`

Remaining validation:

- Observe the notification permission handoff and repeated tapping behavior with release users.
- Exercise provider failures and PhotosPicker selection manually on an unlocked device.
