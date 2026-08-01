# Results

Implemented the reusable `CurrentShowManagementSection` using the existing SwiftData `Show` model and navigation flows. The section now owns the current title/add entry, poster and ambient light, state metadata, countdown/live/ended timing, persistent shortcuts, and the complete end-show confirmation flow.

Following user feedback, ticket, route, reminder, and companion now remain visible at every show phase. Route lookup falls back to the real show name when venue data is incomplete.

Visual review found two overlapping causes of the apparent poster displacement: the fixed-size outer hero did not re-clip the cover image after layout, and the recognizable full-screen cover echo made that overflow harder to distinguish. The hero now clips all visual layers to its 26pt rounded boundary, and the background keeps only cover-derived ambient color bloom, so the poster boundary and 20pt inset read clearly.

The follow-up scope now includes a bounded later-show summary and a separate management destination:

- Current shows at most the two nearest later scheduled shows, ordered by real start time, with poster, name, date, city, and relative distance.
- When more later shows exist, “查看我的现场 · N 场” opens a dedicated secondary page.
- The secondary page searches and filters all real upcoming, ended, postponed, and canceled records and exposes detail, set-current, edit, and confirmed-delete actions.
- The existing bottom “我的现场” tab was not changed.

Final verification after review hardening: 135 tests passed with 0 failures; the user visually reviewed the feature result and confirmed that it looks good before the final safeguards were added.

Manual end state is persisted as `endedAt`. Confirming an end immediately switches timing to ended and counts the show in the existing footprint/history model. The detail page supports editing the end date/time or undoing the end.

Review hardening added six safeguards: estimated-ended shows without `endedAt` can now backfill the real curtain time from Current or detail; historical backfill opens at the scheduled/estimated end without a “刚刚结束” shortcut; intermediate days of multi-day daily-cycle shows cannot write a global `endedAt`; Settings has a Release-visible header entry; show edits and status changes clear stale `endedAt` values at the model boundary; and the later-show summary filters against each minute timeline tick so started shows disappear without another model update.

Verification:

- `git diff --check`: passed.
- iPhone 17 simulator build and full unit test suite after review fixes: 135 tests, 0 failures.
- AXe manual QA: live section, end confirmation, historical end-time entry, ended state, poster-to-detail navigation, edit end time, and undo entry all verified.
- Simulator screenshots saved under `docs/screenshots/2026-07-31-current-show-management-*.png`.
