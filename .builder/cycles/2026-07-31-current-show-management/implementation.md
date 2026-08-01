# Implementation

Build:

- Extract the poster-through-shortcuts surface as `CurrentShowManagementSection`.
- Add the top title/add affordance and remove the poster overflow control from this surface.
- Drive poster metadata, countdown, live duration, and ended presentation from `CurrentShowTimeState`, while keeping all four quick actions persistently visible with real `Show` data.
- Persist an optional user-confirmed `endedAt` and make it the authoritative end boundary.
- Add the three-path end confirmation sheet and detail correction/undo controls.
- Keep lightweight shortcuts bounded to existing platform/app capabilities.
- Add a separate `CurrentShowFollowUpSummary` capped at two real later shows.
- Add a dedicated secondary management destination with search, status filters, grouped records, and per-show actions; leave the existing “我的现场” tab implementation unchanged.
- Keep the ambient layer abstract so it supports the inset poster without repeating a second recognizable copy of the cover behind it.
- Synchronize widgets and notification focus after an end-state change.
- Add focused model/policy tests and iPhone 17 screenshots.

Do not build:

- A full future/status-change list directly on Current, history/statistics, or a new tab bar.
- Full in-app ticketing, trip planning, companion accounts, or reminder redesign.

Dependencies:

- SwiftData `Show` model.
- Shared `CurrentShowTimeState` used by the app and widgets.
- Existing add flow, detail page, notification focus, design system, Apple Maps handoff, and system share/settings surfaces.
