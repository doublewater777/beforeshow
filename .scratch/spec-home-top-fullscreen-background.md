## Problem Statement

当前 iOS 首页顶部没有形成清晰、沉浸的第一视觉层级。现有顶部区域以独立标题、添加入口、更多入口或紧凑现场卡片承载信息，界面感强于现场感；用户首先看到的是工具栏和容器，而不是当前现场本身。首页背景虽然是暗色舞台，但状态栏区域、内容背景和封面氛围没有完全连成一个整体，容易出现顶部像独立黑色盖板、封面像放在背景上的普通卡片的问题。

用户已经确认希望保留当前 iOS 首页的大尺寸 3:4 封面与大倒计时节奏，但要先重做顶部，再重做背景。顶部应删除独立工具栏，让封面直接成为安全区下方的第一块内容；背景应延伸到状态栏和 Home Indicator，由当前现场封面产生低透明度环境光，同时确保内容仍遵守安全区、状态栏始终清晰。

## Solution

将首页顶部重构为单一的 `Poster Stage`：移除封面上方的独立标题、添加按钮和更多按钮区域，在状态栏安全区下方直接展示接近当前 iOS 尺寸的完整 3:4 封面。封面保留底部标题、场馆和日期信息遮罩，并在封面右上角保留一个弱化的 44pt 更多入口；点按封面继续进入当前现场详情。

封面与倒计时之间保留 20pt 明确停顿。倒计时只展示大数字和单位，不展示“至 09.24”“慢慢进入状态”“南京”或“开场前”等重复信息。Tips 与工具区的业务规则、入口和状态保持不变。

首页背景改为全面屏舞台背景：暗场底色、低透明度冷暖舞台光和当前封面的模糊回声共同延伸到状态栏与 Home Indicator。只有背景忽略安全区；封面、倒计时、Tips、工具区和交互控件继续遵守安全区。顶部增加受控暗化，确保白色状态栏内容在明亮封面下仍清晰。第一版直接复用封面图像产生环境光，不新增主色分析或图片取色管线。

## User Stories

1. As a user opening the Current tab, I want the current show cover to be the first content below the status bar, so that the show feels more important than the app chrome.
2. As a user, I want the separate “当前现场” heading removed from the top, so that the page does not repeat what the selected tab already communicates.
3. As a user, I want the separate add button removed from the home top area, so that adding another show does not compete with the current show.
4. As a user, I want the separate more button removed from the home top area, so that the top does not read like a utility toolbar.
5. As a user, I want one quiet more action inside the cover, so that secondary actions remain available without creating another header row.
6. As a user, I want tapping the cover to open the current show detail, so that the large visual object is also a predictable navigation target.
7. As a user, I want the cover to retain a full 3:4 presentation at approximately the current iPhone 17 home size, so that the artwork keeps its impact.
8. As a user with a text-heavy official poster, I want the source artwork to remain uncropped inside the 3:4 frame, so that official information is not lost.
9. As a user, I want the show name, date, and place readable in a controlled bottom scrim, so that I can identify the current show without leaving the home page.
10. As a user with a long Chinese show title, I want the title to wrap predictably without covering too much artwork, so that both identity and poster remain readable.
11. As a user, I want a visible pause between the cover and countdown, so that they feel like two intentional beats rather than one crowded block.
12. As a user, I want the countdown to show only the number and unit, so that it remains emotionally strong and easy to scan.
13. As a user, I do not want the countdown to repeat the target date, city, or “开场前” state, so that the same information is not presented multiple times.
14. As a user, I want the current show cover colors to softly influence the surrounding background, so that every current show gives the home a distinct atmosphere.
15. As a user, I want the background to continue behind the status bar, so that the top of the screen feels like one continuous stage.
16. As a user, I want the background to continue behind the Home Indicator, so that the bottom of the screen does not end in a disconnected black strip.
17. As a user, I want status bar content to remain white and readable on every cover, so that immersion never reduces basic usability.
18. As a user, I want the cover and controls to stay inside the safe area, so that content never collides with the Dynamic Island or screen edges.
19. As a user with a very bright cover, I want the top background to be darkened automatically, so that status bar contrast remains stable.
20. As a user with a very dark cover, I want subtle fixed stage light to keep the background from becoming visually dead, so that the page still has depth.
21. As a user whose current show has no real cover, I want the existing fallback cover and neutral stage background to produce a complete home, so that missing artwork is not exposed as an error state.
22. As a user with Reduce Motion enabled, I want the background and cover to settle without looping movement, so that the home remains comfortable.
23. As a VoiceOver user, I want the cover, more action, countdown, Tips, and tools to retain clear accessibility labels and logical focus order, so that the redesign remains operable.
24. As a user, I want Tips and tool behavior to remain unchanged, so that a visual redesign does not alter what BeforeShow recommends or where actions open.
25. As a returning user, I want the background atmosphere to appear immediately without replaying onboarding motion, so that the home feels stable on every launch.

## Implementation Decisions

- Deliver in two ordered slices. Slice one replaces the current top composition with the large poster-led header and adjusts the countdown spacing. Slice two changes the home background to the cover-driven, full-screen treatment. Each slice must be independently buildable and visually reviewable.
- Preserve the iPhone 17 baseline: horizontal margins near the existing large-cover home, a 3:4 cover approximately 367×489pt, and the existing oversized countdown scale.
- Remove the separate top utility row or compact header container. Do not replace it with a marketing eyebrow, page heading, add button, or another status pill.
- Place one 44×44pt overflow action in the cover's top-right scrim. It opens the existing current-show tool or action surface; no new navigation destination is introduced.
- Keep the entire cover as the existing navigation entry to current show detail. The overflow action must remain independently tappable and must not trigger cover navigation.
- Keep the show name, date, and place in the lower cover scrim. Use existing display formatting and current-show data; no duplicate view model or data transformation layer is added.
- Keep source artwork in a sharp 3:4 container. The artwork is not blurred, recolored, or stretched; atmosphere is produced by a separate background copy.
- Set the cover-to-countdown pause to 20pt. Keep the countdown number scale unchanged from the approved Home C prototype.
- Countdown content is limited to the state-dependent number or phrase plus its unit when applicable. Do not render target date, location, “慢慢进入状态”, or a second lifecycle label beside it.
- Continue using the existing current-show time state as the countdown source. This spec changes presentation only and does not modify date calculations, postponed/canceled behavior, or current-show selection.
- Make the home root background ignore all safe-area edges. Content containers do not ignore safe areas; the first cover begins below the top safe-area inset with 8–12pt visual breathing room.
- Build the background from four ordered layers: stage-void base, subtle fixed cool/warm radial light, a blurred and enlarged copy of the current cover at low opacity, and a vertical contrast scrim that is strongest near the status bar and bottom navigation.
- Reuse the existing cover-loading and caching path for the ambient copy. Do not introduce a second network client or an independent image download.
- First version does not calculate dominant colors. The cover bitmap itself supplies ambient color; fixed opacity, saturation, blur, scale, and contrast bounds keep output predictable across covers.
- Cap the cover echo at low opacity and lower saturation than the source artwork. The sharp cover remains the only readable image; the background copy must not look like a second poster.
- Keep the app in dark appearance with light status bar content. The top contrast layer must make status indicators readable without depending on a specific poster.
- When the cover is unavailable or loading fails, use the existing fallback cover and neutral stage lighting. Do not show a broken-image treatment or “暂无封面” copy.
- Preserve the existing Tips resolver, tool summaries, tool sheets, current-show selection, Tab structure, add-show flow, and SwiftData models.
- Preserve minimum 44pt touch targets, VoiceOver labels, Dynamic Type behavior, and Reduce Motion. Background layers are decorative and hidden from assistive technologies.
- Motion is limited to the existing one-time cover/countdown arrival. The ambient background remains still after resolution; no looping beam, shimmer, or parallax is added by this spec.

## Testing Decisions

- Use one highest-level acceptance seam: launch the real SwiftUI app on an iPhone 17 simulator with seeded current-show data, then exercise the Current tab as a user. Build success and unit tests support this seam but do not replace it.
- A good test verifies externally visible behavior: content order, safe-area behavior, navigation, readable status bar, countdown copy, fallback behavior, and absence of obstruction. It does not assert private SwiftUI view structure, exact gradient stops, blur implementation, or internal modifier order.
- Reuse the existing debug sample-show seeding path to create deterministic current-show states. Do not add a new preview-only production data path.
- Verify slice one with a normal cover, a long Chinese title, and the approved Nanjing showcase cover. Confirm the top utility row is absent, the cover stays 3:4, overflow is independently tappable, cover navigation works, and countdown contains no target date/location/state copy.
- Verify slice two with four visual fixtures: bright cover, dark cover, missing cover, and the approved Nanjing showcase cover. Confirm background continuity under the status bar and Home Indicator, stable light status-bar contrast, and no visible second-poster effect.
- Verify the no-current-show state remains usable and continues to offer 添加现场 through its existing path. The new current-show background must not leak stale cover imagery into the empty state.
- Verify `today`, `ended`, `postponed`, and `canceled` countdown variants still render their existing state-dependent phrase and do not gain duplicate metadata.
- Verify Tips visibility and action routing at the existing lifecycle boundaries. This spec must not change resolver outputs or cause a Tip to be covered by the bottom Tab bar.
- Verify the horizontal tool area and every existing tool sheet still open from the Current tab.
- Verify VoiceOver focus order starts with the cover/detail target, then the overflow action, countdown summary, Tips, and tools; decorative background layers must not appear in the accessibility tree.
- Verify Reduce Motion removes cover/countdown travel or blur animation according to existing behavior and leaves the ambient background static.
- Run the existing iOS test suite and an iPhone 17 simulator build. Pre-existing unrelated failures must be reported separately rather than worked around in this change.
- Capture before/after iPhone 17 screenshots for the top area and full screen. Manual visual approval of those screenshots is required because exact atmosphere and safe-area continuity are the acceptance criteria.

## Out of Scope

- Redesigning Tips content, timing, resolver rules, or fallback behavior.
- Redesigning the horizontal tool area, tool cards, tool sheets, or bottom Tab bar.
- Changing current-show selection or adding a new current-show switcher.
- Changing 添加现场, 我的现场, onboarding, settings, notifications, or Pro behavior.
- Adding dominant-color extraction, palette generation, Core Image analysis, Metal shaders, or third-party image libraries.
- Changing SwiftData schemas, backend APIs, image URLs, or caching contracts.
- Adding user-selectable home themes or multiple home styles.
- Allowing the sharp cover, text, or controls to render underneath the Dynamic Island or outside safe areas.
- Replaying splash or onboarding animation for returning users.

## Further Notes

- The approved visual reference is Home concept C in the current onboarding/home prototype, with the latest decisions applied: large 3:4 cover, cover metadata and quiet overflow retained, 20pt cover-to-countdown pause, and countdown secondary copy removed.
- This issue is a focused implementation slice related to #42. Where #42 describes a broader or older home direction, this issue is authoritative for the current-home top area, cover size, countdown adjacency, and full-screen background behavior.
- Product copy must continue using the project glossary: 当前现场, 添加现场, 我的现场, 开场前, Tips, 去程计划, and 现场准备.
