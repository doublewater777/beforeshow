# Current Show Management Section

Stage: business-model

Target user: a live-music attendee managing the one show that matters now.

User problem: the current page mixes the current-show poster and countdown with explanatory cards and next-show actions, while ending a live show cannot capture the real curtain time through a clear confirmation flow.

Desired behavior change: users can understand and manage the current show from one poster-led section, always find the same four management shortcuts, and explicitly confirm or correct the curtain time.

Success:

- The page starts with a “当前” heading and add button, followed by the real current show poster, phase metadata, countdown, and persistent ticket, route, reminder, and companion shortcuts.
- The poster opens the real show detail and has no overflow control.
- A live show exposes “散场了，结束这场现场”.
- A show that crossed its estimated end without a confirmed `endedAt` still exposes a first-time curtain-time entry on Current and in detail.
- “刚刚结束” stores the current time; “早就结束” requires a valid date and time; “还没结束” dismisses without changing the clock.
- A confirmed show immediately renders as ended and remains available in the existing show library/footprint surface.
- The detail page can change the confirmed curtain time or undo the end.
- Editing the start into the future, postponing, or canceling cannot leave an invalid confirmed curtain time behind.
- Settings remains reachable from the production Current header, and later-show eligibility refreshes while the page stays open.
- Below the current-show controls, the page shows only the two nearest later shows with poster, name, date, city, and time distance.
- When more than two later shows exist, “查看我的现场 · N 场” opens a dedicated secondary management page.
- The secondary page can search, filter, and manage future, ended, postponed, and canceled records without repeating the current-page hero.
- No full future list on the Current page, statistics/history, prototype tab bar, or explanatory prototype copy is added.
- Focused tests pass and the UI is verified on iPhone 17 with screenshots.

Out of scope:

- Rebuilding retired travel planning, ticket-provider integrations, social graphs, or a new reminder system.
- Changing the existing bottom “我的现场” tab; the new management page is a separate destination from Current.
- Replacing the app's existing bottom navigation.
