# PRD: Redesign iOS Home Page and Visual Language

## Problem Statement

The current iOS home page (`CurrentShowHomeView`) does not match the immersive, theatrical mood established by the SplashView entry screen. It feels crowded: the hero cover image is small, a status pill is overlaid on the poster, and four feature rows compete for attention below the fold. The visual language is inconsistent with the product's premise of "开场之前，先进入状态" — users do not feel like they are stepping into the show before it starts.

Additionally, the existing layout does not adapt well to different cover image types (clean posters, text-heavy festival posters, live photos) or different show states (开场前 / 当天 / 散场后停留期 / 已结束 / 延期 / 取消). Cross-day shows and festivals are not given enough room to display lineup or date-range information.

## Solution

Redesign the iOS home page and the surrounding visual language so that:

1. The hero cover image dominates the screen and creates atmosphere.
2. Status text is removed from the poster itself; the page title and countdown communicate state.
3. Only two primary actions are exposed on the home page, plus an "All Tools" entry.
4. Users can choose one of three home styles in Settings: half-screen cover, full-screen immersive, or theatrical card.
5. Lineup/artist information is shown appropriately per show type without interactive artist tracking on the home screen.
6. Cross-day and festival shows display date ranges and lineups cleanly.

The redesign reuses the existing `DesignSystem` tokens and keeps all data in SwiftData; it is a presentation-layer change, not a data-model change.

## User Stories

1. As a user opening BeforeShow, I want the home screen to feel like the show is already around me, so that I can get into the mood.
2. As a user with a clean concert poster, I want the cover to fill most of the screen, so that the poster has impact.
3. As a user with a text-heavy festival poster, I want the app to keep the poster readable while still showing the title and countdown, so that information does not overlap.
4. As a user who prefers a theatrical vibe, I want a home style with stage beams and a central cover card, so that the app matches the opening-night feeling.
5. As a user, I want to pick my home style in Settings, so that the app feels personal.
6. As a user, I want the home page to show only the two most relevant tools for the current state, so that I am not overwhelmed by choices.
7. As a user, I want a single "全部工具" entry that reveals every tool, so that I can still reach less common features.
8. As a user going to a music festival, I want to see a horizontal lineup on the home page, so that I can scan the artists quickly.
9. As a user going to a Livehouse show, I want the home page to feel intimate, so that it matches the smaller venue.
11. As a user on the day of the show, I want the home page to prioritize practical tools (现场准备, 往返计划), so that I can check last-minute details.
12. As a user in the post-show retention window, I want the home page to highlight 现场碎片 and a prompt to add the next show, so that I can capture memories before the show moves to history.
13. As a user whose show has ended and has no next show, I want the ended show to stay in the Current tab with a prompt to add the next one, so that I do not lose access to fragments.
14. As a user with a cross-day Livehouse show, I want the home page to show the full start-to-end time range, so that I know when the night really ends.
15. As a user with a multi-day festival, I want the home page to show the date range, so that I know which days I am attending.
16. As a user, I do not want to see "开场前" as a page heading, so that the screen feels less like a status dashboard and more like an experience.
17. As a user with a postponed show whose new date is unknown, I want the countdown to pause and the status to say "时间待定", so that I am not confused.
18. As a user with a canceled show, I want the show to remain in 我的现场 but not be treated as current, so that I keep a record without being reminded of a canceled event.
19. As a user, I want the poster image cropped from the top, so that faces, logos, and key visuals are preserved.
20. As a user, I want the cover to have a placeholder when no image is provided, so that the screen still looks complete.
21. As a Pro user, I want the home page to continue working the same way after the redesign, so that my subscription value is not changed.
22. As a free user, I want the Pro upsell prompts to appear in the new visual style, so that they feel consistent with the rest of the app.
23. As a user, I want the "我的现场" list to highlight the current show with a gradient border and no "当前" label, so that the list is visually clean.
24. As a user, I want the show detail page to match the new visual language, so that navigation feels continuous.
25. As a user, I want the add-show flow to match the new visual language, so that first-time setup feels polished.
26. As a user, I want all tool screens (现场碎片, 往返计划, 现场准备, 现场回顾, 候选曲目) to share the same dark, immersive style, so that the app feels cohesive.
27. As a user, I want the settings page to match the new style and include the home-style picker, so that I can change the look from one place.
28. As a user, I want onboarding and the "add first show" screen to share the new visual language, so that the first-run experience is consistent.
29. As a user, I want loading and error states during add-show to match the new style, so that failures do not break immersion.
30. As a user, I want toast notifications (saved, failed, copied) to appear in the new style, so that feedback feels native to the redesign.

## Implementation Decisions

- **Three home styles.** The app will support three mutually exclusive home layouts, stored in `UserDefaults` under a single key:
  - `halfScreenCover` — cover occupies the top ~55% of the screen; information and tools sit below on a solid background.
  - `fullScreenImmersive` — cover fills the screen; title, date, countdown, and tools float over a bottom gradient.
  - `theatricalCard` — stage beams, central orb, and a prominent rounded cover card; countdown and tools below the card.

- **Style selection UI.** A new "首页风格" row in Settings pushes a selection screen with the three styles. The default is `halfScreenCover`.

- **Home state from `CurrentShowTimeState`.** The home page will continue to derive its state from the existing `CurrentShowTimeState` value object. Its outputs (`kind`, `title`, `countdownNumber`, `countdownUnit`, `helperText`, `effectiveStartTime`, `effectiveEndTime`) drive what is rendered, but the UI will no longer render a large "开场前" heading. Status text may appear in small captions where useful, but it is not a hero element.

- **Hero cover rules.**
  - The cover image is loaded asynchronously with a placeholder gradient.
  - It uses top-aligned cropping (`object-position: top` equivalent) so that posters with heads, logos, or titles at the top remain intact.
  - No status pill is overlaid on the cover.
  - For festivals, the cover may be a text-heavy poster; the `fullScreenImmersive` style will apply a stronger bottom gradient so UI text does not collide with poster text, and `halfScreenCover` keeps the cover and information on separate backgrounds.

- **Lineup display rules.**
  - The show title itself is expected to contain the artist or festival name (e.g., "五月天 · 上海演唱会" or "草莓音乐节 · 上海"). No separate artist line is shown directly under the title.
  - Music festivals: show a horizontally scrollable lineup of the first several artists parsed from the `artist` field. Taps are not interactive on the home screen; the row is read-only.
  - If the `artist` field is empty, no lineup area is shown.

- **Home tool grid.**
  - Always show two primary tool entries plus a "全部工具" button.
  - The two primary tools depend on `CurrentShowTimeState.kind`:
    - `before`: 今晚先听 + 现场准备
    - `today`: 现场准备 + 往返计划
    - `postShow`: 现场碎片 + prompt to add next show
    - `ended` (fallback when no other show exists): 现场碎片 + prompt to add next show
    - `postponed` / `canceled`: reduced to 现场碎片 + 全部工具
  - "全部工具" pushes or presents a full-screen flat grid of every tool.

- **No new data models.** The redesign uses existing `Show`, `CurrentShowSelection`, `CandidateSong`, `RoundTripPlan`, `ShowFragment`, and `ShowPreparation` models. No schema migration is required.

- **Cross-day rendering.** The home page will use `effectiveStartTime` and `effectiveEndTime` from `CurrentShowTimeState` to render ranges such as "2026年7月8日 23:00 - 7月9日 01:00". For festivals with an `endDate`, it will render "2026年8月15日 - 8月17日".

- **My Shows list visual update.** The current show card receives a gradient border highlight. The "当前" text label is removed. Sorting keeps the current show first.

- **Show detail and tool screens.** These screens will adopt the same dark surface, gradient accents, and card spacing defined in `DesignSystem`. They will not change their navigation structure or data flows.

- **Onboarding and empty states.** The onboarding page, add-first-show screen, and empty states will use the same glass-card buttons and dark gradient background as the rest of the app.

- **Pro prompts and loading/error states.** Bottom sheets and inline messages will follow the new card style. Loading spinners use the existing design tokens.

## Testing Decisions

- **Test external behavior, not layout details.** Good tests verify that the right state produces the right tool entries, the right countdown copy, and the right visibility of the festival lineup area. They do not assert exact SwiftUI frame values or colors.

- **`CurrentShowTimeState` remains the seam.** Extend the existing `ShowModelTests` / `CurrentShowTimeState` test coverage to assert:
  - Cross-day shows produce correct `effectiveEndTime` and helper text.
  - Festival-style date ranges are represented in the helper text.
  - Postponed and canceled shows report the correct `kind` and `isAutomaticallySelectable` values.

- **View-level tests via `NavigationTests` / `StartupRouteTests` patterns.** Add tests that instantiate the home view with a configured SwiftData container and verify:
  - The correct primary tools appear for each `CurrentShowTimeKind`.
  - The artist/lineup area is shown or hidden based on the `artist` field and `type`.
  - The "全部工具" entry is always present when a current show exists.

- **Home-style selection tests.** Add a small unit test around the home-style preference store to confirm reading/writing the selected style and falling back to the default.

- **Snapshot or build verification.** Because visual diffs are brittle, prefer `xcodebuild` build success and manual design-review of the HTML prototypes over automated snapshot tests. The existing HTML prototypes under `apps/ios/design-exploration/` serve as the visual acceptance reference.

## Out of Scope

- New AI generation capabilities or backend changes.
- New features such as social sharing, comments, or public timelines.
- Android, web, or macOS versions.
- Changes to StoreKit products, subscription entitlements, or pricing.
- Deep linking or widget updates.
- New notification scheduling logic; existing local notification behavior is preserved.

## Further Notes

- The HTML prototypes in `apps/ios/design-exploration/` capture the final visual direction. They cover the three home styles, show-type variants, time-state variants, all-tools, my-shows, add-show flow, tool screens, settings, onboarding, Pro limits, loading/error states, cross-day states, and toast notifications. They should be treated as the visual acceptance reference during implementation.
- The redesign is intentionally a presentation-layer refactor. It should not change the public API contracts of the data services or generation services.
- Accessibility should be maintained: home actions keep their accessibility labels, and the selected home style does not reduce touch targets below 44 pt.
