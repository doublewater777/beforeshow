# PRD: BeforeShow V2.1 iOS App

## Problem Statement

Users with an upcoming concert, Livehouse show, or music festival have a scattered pre-show ritual. They search ticket screenshots, music apps, Bilibili videos, social posts, maps, chats, hotels, and notes just to answer simple emotional and practical questions: what might be played, what should I listen to tonight, what does the live atmosphere feel like, how do I get there and back, and where do I keep the small memories around this现场?

Existing tools solve adjacent jobs but not the felt journey. Ticketing apps manage purchases, music apps play songs, maps navigate, social apps publish content, and calendars track dates. None of them make the period before the现场 feel like a coherent, private, low-pressure path into the night.

## Solution

Build BeforeShow V2.1 as an iOS-only SwiftUI app for people preparing for a音乐现场. The app centers one当前现场 at a time and helps the user enter state through a quiet countdown,候选曲目 ordered like a guessed setlist,今晚先听,现场回顾 through Bilibili’s official player, a user-owned往返计划, lightweight现场准备, and private现场碎片.

The product stays local-first and emotionally quiet. It does not become a ticket wallet, player, map, public community, task checklist, or generic event manager. Pro membership unlocks repeated AI generation and unlimited saved现场 while leaving private local content usable.

## User Stories

1. As a first-time user, I want to understand that 开场前 is for the period before a music现场, so that I know why I would use it instead of a calendar or ticketing app.
2. As a first-time user, I want to add a现场 with only a name and date, so that I can start even when I do not know every detail yet.
3. As a user with a ticket screenshot, I want device-side screenshot recognition to fill现场 fields, so that I do not need to type information manually.
4. As a privacy-conscious user, I want ticket screenshots to stay on device during recognition, so that sensitive ticket information is not uploaded.
5. As a user pasting ticket or chat text, I want the app to recognize useful现场 fields, so that adding a现场 feels fast.
6. As a user adding a现场 from OCR or paste recognition, I want to review and edit the result before saving, so that wrong extracted fields do not become my data.
7. As a user, I want the app to support 演唱会, Livehouse, and 音乐节, so that the product stays focused on music现场.
8. As a user trying to add an unsupported event type, I want a clear, gentle explanation, so that I understand this version is for music现场 only.
9. As a user with multiple saved现场, I want one当前现场 to drive the home experience, so that the app does not become a noisy schedule manager.
10. As a user, I want the app to choose the nearest relevant当前现场 by default, so that I do not need to manage the home screen every time.
11. As a user, I want to manually switch当前现场, so that I can focus on the现场 I care about most right now.
12. As a user, I want the app to respect my manually chosen当前现场, so that it does not unexpectedly jump away.
13. As a user, I want a quiet home screen for the当前现场, so that the app feels like a pre-show companion, not a dashboard.
14. As a user, I want the App Store subtitle to explain “开场之前，先进入状态,” so that I immediately understand the product.
15. As a user seeing brand surfaces, I want “灯亮之前，先进入状态” to carry the mood, so that the product feels like waiting in the dark before a show.
16. As a user, I want local notifications only for meaningful moments, so that I am reminded without feeling chased.
17. As a user, I want the app to ask for notification permission after I add a现场, so that the permission request has context.
18. As a user, I want a T-14 reminder at 20:00, so that I can begin entering state without a daily task system.
19. As a user, I want a T-1 “明天见” reminder at 20:00, so that the night before feels special.
20. As a user, I want a same-day “快开场了” reminder, so that I remember to shift into现场 mode.
21. As a user, I want missed notification milestones not to be backfilled, so that adding a现场 late does not create strange notifications.
22. As a user switching当前现场, I want future notifications to be rescheduled, so that reminders follow my focus.
23. As a user after a现场 ends, I want it to remain on the home screen for three days, so that the app does not immediately move on before I do.
24. As a user with a finished现场, I want to keep viewing and adding现场碎片, so that the memory can settle naturally.
25. As a user, I want to generate候选曲目, so that I can guess what might be played and in what order.
26. As a user, I want候选曲目 to contain only song name and artist, so that the list stays light and setlist-like.
27. As a user, I want the order of候选曲目 to represent the guessed现场 order, so that I can listen through it like a possible night.
28. As a user, I want no lyrics in候选曲目, so that the product avoids unnecessary copyright risk.
29. As a user, I want no confidence percentages or recommendation reasons, so that the list does not pretend to be scientific.
30. As a user, I want to reorder候选曲目 manually, so that my own guess can shape the list.
31. As a user, I want to add or remove候选曲目 manually, so that I can correct the app.
32. As a user, I want regeneration to require confirmation before replacing my current候选曲目, so that my edits are not silently overwritten.
33. As a user, I want候选曲目 generation to use联网搜索, so that the guessed order is not based only on model memory.
34. As a user, I want an overall uncertainty note for候选曲目, so that I understand it is not an official setlist.
35. As a user, I want to copy候选曲目 as plain text, so that I can share or save the list outside the app.
36. As a user, I want the app not to create music platform playlists, so that it does not cross into player or platform integration territory.
37. As a user, I want今晚先听 to pick one song from候选曲目, so that I can enter state without facing a long list.
38. As a user, I want今晚先听 not to track completion, so that listening does not become homework.
39. As a user, I want no “heard it” or streak UI, so that the app stays emotionally light.
40. As a user without候选曲目 yet, I want the home entrance to say “猜猜那晚会唱什么,” so that generation feels inviting.
41. As a user, I want to choose a default music platform the first time I search, so that future searches are one tap.
42. As a user, I want Apple Music, 网易云音乐, QQ 音乐, and Spotify search handoffs, so that I can use my preferred service.
43. As a user, I want the app not to check platform availability, so that search remains simple and robust.
44. As a music festival user, I want艺人关注项 with 想看, 待定, and 不看, so that I can shape my festival focus.
45. As a music festival user, I want候选曲目 generated per relevant艺人关注项, so that different artists do not become one messy list.
46. As a music festival user, I want想看 artists prioritized for今晚先听, so that the app follows my intent.
47. As a music festival user, I want不看 artists excluded from generation and tonight recommendations, so that the app does not waste attention.
48. As a user, I want现场回顾, so that I can watch a few live clips and find the feeling of the night.
49. As a user, I want现场回顾 separate from候选曲目, so that I can choose whether to listen or watch.
50. As a user, I want the入口文案 “提前看几段现场,” so that the feature feels like mood-setting, not video search.
51. As a user, I want Bilibili show recaps to show title, source, and playback entry, so that I know where the content comes from.
52. As a user, I want App playback to use Bilibili’s official external player, so that BeforeShow does not redistribute video.
53. As a user, I want fallback to the original Bilibili page when in-app playback fails, so that I can still watch.
54. As a user, I want no cached covers, videos, audio, comments, danmaku, or source pages, so that third-party media stays outside BeforeShow.
55. As a user, I want to load more现场回顾 only by tapping “再找一些,” so that it does not become an infinite video feed.
56. As a user, I want现场回顾 as cards with a detail playback view, so that it stays contextual instead of becoming a short-video app.
57. As a user, I want not to manually add Bilibili links to现场回顾, so that the feature does not turn into a video bookmark manager.
58. As a user, I want往返计划, so that I can think through how to go and how to return without making BeforeShow a navigation app.
59. As a user, I want去程 and返程 to be independent, so that I can decide how to go before I know how I will return.
60. As a user, I want未定返程 to be normal, so that I can admit I will decide later.
61. As a user, I want to generate a去程草稿, so that I have a starting point for getting to the现场.
62. As a user, I want to generate a返程草稿, so that I can prepare for the part that often feels chaotic.
63. As a user, I want往返草稿 to require enough directional information, so that it is useful rather than vague.
64. As a user, I want往返草稿 to use联网搜索 for traffic facts, so that the app does not invent unsafe details.
65. As a user, I want generated往返草稿 to remain a draft until I save it, so that I stay in control.
66. As a user, I want saved往返计划 to be manually editable, so that my hotel, meeting point, or personal plan can be more accurate than AI.
67. As a user, I want regenerated往返草稿 not to overwrite my saved plan automatically, so that my edits are respected.
68. As a user, I want no ride matching or stranger carpooling, so that the app avoids unsafe social travel territory.
69. As a user, I want返程 to stay visible during散场后停留期, so that I can still use it after the show.
70. As a user, I want no返程 completion state, so that the app does not turn travel into a task.
71. As a user, I want现场准备, so that I can read light reminders about weather, gear, etiquette, and注意事项.
72. As a user, I want现场准备 not to be a checklist, so that it does not create pressure.
73. As a user, I want现场准备 not to be editable, so that it remains a gentle product voice rather than another list to manage.
74. As a music festival user, I want preparation suggestions that include comfort and etiquette, so that I can enjoy myself while not disrupting others.
75. As a user, I want现场碎片, so that OOTD, food, friends, queues, videos, and散场 thoughts can stay with this现场.
76. As a user, I want现场碎片 to feel like a private post stream for one现场, so that I can record freely without publishing.
77. As a user, I want each现场碎片 to support multiple photos or videos, one text body, and one语音片段, so that each fragment can hold a complete little moment.
78. As a user, I want现场碎片 to be tied to a现场 by default, so that it never becomes a generic life diary.
79. As a user, I want to move a现场碎片 to another现场 if I made a mistake, so that I can correct ownership.
80. As a user, I want现场碎片 ordered by creation time, so that it feels natural and not over-managed.
81. As a user, I want no tags, categories, manual sorting, comments, likes, or sharing for现场碎片, so that it remains private.
82. As a user, I want photos and videos referenced from the system gallery, so that BeforeShow does not duplicate large media.
83. As a user, I want App recordings stored in the app and deleted with the relevant content, so that audio storage is understandable.
84. As a user, I want deletion of a现场 to remove local app data but not system gallery originals, so that I do not accidentally lose my photos or videos.
85. As a user, I want to mark a现场 as延期, so that the app stops acting like the date is still approaching.
86. As a user, I want延期 without a new date to pause countdown and generation, so that uncertainty is represented honestly.
87. As a user, I want延期 with a new date to re-enter the开场前 cycle, so that the app can start accompanying me again.
88. As a user, I want to mark a现场 as取消, so that the app stops pushing entering-state features for it.
89. As a user, I want取消现场 to remain viewable with现场碎片, so that the canceled experience can still be remembered.
90. As a user, I want artist, time, and venue corrections to be ordinary edits, so that the app does not overcomplicate changes.
91. As a free user, I want enough saved现场 capacity to build a meaningful footprint before paying, so that I can understand the long-term value of the app.
92. As a free user, I want a five-show base capacity and one additional capacity-growth step per local calendar month after that base, so that occasional long-term use remains possible without making Pro mandatory immediately.
93. As a free user, I want deletion to free capacity and invitation-only companion现场 not to consume it, so that the limit reflects the现场 I chose to save myself.
94. As a Pro member, I want unlimited saved现场, so that BeforeShow can fit my actual show-going life.
95. As a Pro member, I want repeated AI generation, so that I can refine候选曲目,往返计划, and现场回顾 as plans change.
96. As a Pro member, I want to restore purchases through the App Store, so that I can recover membership without a BeforeShow account.
97. As a Pro-expired user, I want access to existing local data, so that my memories and plans are not held hostage.
98. As a Pro-expired user, I want to keep adding现场碎片 to existing现场, so that private recording remains mine.
99. As a Pro-expired user, I want manual edits to remain available, so that only repeated AI and new over-limit shows are gated.
100. As a user, I want Pro prompts only when I hit a Pro limit, so that the home screen remains calm.
101. As a user, I want no ads, so that Pro is not framed as removing an annoyance.
102. As a user, I want privacy explanations, so that I know what stays local and what is sent for AI generation.
103. As a user, I want feedback to send only minimal diagnostics I choose to submit, so that现场 content is not uploaded unexpectedly.
104. As an App Store reviewer, I want the app to avoid ticketing, copyrighted lyrics, and self-hosted video playback, so that its compliance boundary is clear.
105. As an engineer, I want the domain language in the product to match the glossary, so that implementation does not reintroduce 行程, 歌单, 余韵, or other rejected concepts.
106. As an engineer, I want the iOS app to be local-first, so that the no-account decision is preserved.
107. As an engineer, I want AI generation behind a backend, so that model credentials are not shipped in the app.
108. As an operator, I want minimum technical logs without raw prompts or outputs, so that cost and reliability can be monitored without storing sensitive user content.

## Implementation Decisions

- Build V2.1 as an iOS-only native SwiftUI app.
- Use SwiftData for local structured data:现场,当前现场 choice,音乐节艺人关注项,候选曲目 order,往返计划,现场碎片 metadata, media references, recording references, default music platform, notification scheduling state, and Pro entitlement cache.
- Use PhotoKit references for system gallery photos and videos. Do not copy original photo/video files into the app.
- Store App-created audio recordings in the app sandbox and store only metadata/references in structured persistence.
- Use Vision for on-device OCR from ticketing screenshots. Do not upload screenshots for recognition.
- Add three添加现场 paths: manual form,粘贴识别,截图识别. All recognition output must be user-confirmed before saving.
- Model现场 as supporting only演唱会, Livehouse, and音乐节 in V2.1.
- Model生命周期 as开场前,当天,已结束 plus a three-day散场后停留期. Do not build an After module.
- Model现场变更 only as延期 or取消. Other factual edits are ordinary edits.
- Keep one当前现场 as the focus for home, notifications,今晚先听,往返计划, and现场碎片.
- Bottom tabs are当前,我的现场,设置.
- Settings includes Pro会员 first, then default music platform, privacy/local data, clear local data, feedback, and about.
- Schedule local notifications only for当前现场: T-14 20:00, T-1 20:00, and same-day 3 hours before start or 12:00 when no start time exists.
- Reschedule local notifications when当前现场 changes. Do not backfill missed notification milestones.
-候选曲目 contains only song name and artist. The persisted list order expresses guessed现场 order.
-候选曲目 generation must use联网搜索, return a structured ordered list, and display an overall uncertainty note. Do not store or display lyrics, confidence, recommendation reasons, platform IDs, cover art, durations, audio links, or per-song sources.
- Allow manual candidate song add, remove, and reorder. Regeneration must require explicit user confirmation before replacement.
-今晚先听 selects from候选曲目 order and does not track completion, streaks, or听过 state.
- Music handoff supports Apple Music, 网易云音乐, QQ 音乐, and Spotify via search. Default music platform is global.
-现场回顾 is separate from候选曲目. It uses Bilibili public video metadata and either the official external player in WKWebView or original-page fallback.
-现场回顾 stores only title, source, and BVID/link-like lightweight metadata. It does not cache covers, video, audio, danmaku, comments, or pages.
-现场回顾 uses a card list plus playback detail. It supports user-triggered “再找一些” pagination, not automatic infinite scrolling.
-往返计划 has independently generated and editable去程 and返程.未定返程 is a normal state.
-往返草稿 must use联网搜索 for concrete traffic facts and must not invent public transport, closure, shuttle, or venue facts without reliable search results.
- Personal places such as hotel, origin, destination, and meeting point are sent only when the user actively generates a relevant往返草稿.
-现场准备 is a read-only suggestion surface, not a checklist and not user-editable.
-现场碎片 is a private per-现场 stream. A fragment supports multiple photos/videos, one text body, and one语音片段.
-现场碎片 can be moved to another现场 but not copied to multiple现场. There are no unassigned fragments.
-现场碎片 sorts by creation time only. No categories, tags, manual order, comments, likes, sharing, or public feed in V2.1.
- Pro uses App Store subscriptions only. No BeforeShow account is built.
- Initial Pro packaging: ¥12/month and ¥68/year, no free trial.
- Free users have a five-show base capacity for self-added现场. After the base, free capacity can grow by one per local calendar month; unused monthly growth does not roll over, deletion frees capacity, and invitation-only companion现场 do not consume it.
- Pro unlocks unlimited saved现场, repeated AI generation, and additional现场回顾 discovery.
- Show fragments,现场准备,今晚先听, and manual editing remain free.
- Pro expiration never locks existing local data. Saved现场 remain available, and the user returns to the free monthly capacity-growth rule for new additions.
- Backend is Tencent Cloud CloudBase functions.
- Default model provider is Volcengine Doubao, with Alibaba Qwen as fallback.
- Backend stores no long-term user现场 data and no raw AI prompts/outputs. It keeps only minimal technical logs.
- Backend performs anonymous basic rate limiting. Do not introduce accounts, device fingerprinting, or strong anti-abuse controls for reinstall resets in V2.1.
- App Store identity: name 开场前, English/technical name BeforeShow, App Store subtitle “开场之前，先进入状态,” atmospheric brand line “灯亮之前，先进入状态,” category Music with Lifestyle secondary.

## Testing Decisions

- Tests should verify externally visible behavior at the highest feasible seam: user flows, persisted domain state, entitlement gates, generated-result contracts, notification scheduling, and media/reference behavior. Avoid tests that assert private implementation details.
- Highest seam for the iOS app: UI-level flow tests or feature-level integration tests around adding a现场, selecting当前现场, generating/saving候选曲目, using今晚先听, editing往返计划, adding现场碎片, and hitting Pro gates.
- Domain seam: pure model/state tests for当前现场 selection,散场后停留期,延期/取消 behavior, free allowance consumption, Pro expiration behavior,候选曲目 replacement confirmation, and现场碎片 deletion semantics.
- Persistence seam: SwiftData integration tests for saving and loading现场,候选曲目 order,往返计划,现场碎片 metadata, PhotoKit identifiers, recording references, Pro/free allowance state, and default music platform.
- OCR seam: Vision OCR parsing tests should use fixture text or mock OCR outputs to verify only allowed现场 fields are extracted and sensitive ticket fields are ignored.
- AI API seam: backend contract tests should verify request and response schemas for候选曲目,往返草稿, and现场回顾. Responses should reject lyrics, recommendation reasons, unsupported fields, and unstructured results.
- Search-dependent generation seam: backend tests should verify that往返草稿 does not produce concrete transport facts when reliable search evidence is absent.
- Bilibili seam: integration tests should verify that现场回顾 stores only lightweight metadata and constructs official-player/original-page entries without caching covers or media.
- StoreKit seam: purchase-state tests should verify free limits, Pro unlocks, Pro expiration access to existing data, restore purchase behavior, and no lockout of现场碎片 or manual edits.
- Notification seam: scheduling tests should verify T-14, T-1, and same-day notification timing, missed milestone behavior, permission-disabled behavior, and rescheduling after当前现场 changes.
- Privacy seam: tests should verify ticket screenshots are not uploaded for OCR, raw AI prompts/outputs are not persisted by the backend, feedback does not automatically include现场 content, and deleting a现场 does not delete system-gallery originals.
- Prior art in the current repository is limited: the existing fake-door app has no meaningful automated app behavior tests. New tests should be introduced at the highest seam of the new SwiftUI app and CloudBase backend rather than copying the fake-door structure.

## Out of Scope

- Android support.
- Expo, React Native, NativeWind, or cross-platform app implementation.
- Account system, login, cloud sync, or full backup/restore.
- Widget support.
- Lyrics display, including one-line lyrics.
- Audio playback, audio streaming, music platform playlist creation, or platform availability checks.
- Ticket wallet, ticket verification, ticket resale, or ticket matchmaking.
- Public community, comments, likes, follows, anonymous walls, group chat, or social feed.
- Bilibili cover caching, video caching, stream parsing, self-built video player, danmaku/comment caching, or user-submitted Bilibili links.
- Full-screen short-video feed or automatic infinite video scroll.
- AI real-time navigation, map replacement, ride matching, carpooling, or stranger同行.
- Editable or checkable现场准备 lists.
- Pro free trial, lifetime purchase, ads, or ad removal benefits.
- Strong anti-abuse controls for uninstall/reinstall free allowance reset.
- Archiving shows.
- Sharing现场碎片 or exporting complete local data.

## Further Notes

- Use the project glossary vocabulary consistently:现场,当前现场,我的现场,候选曲目,今晚先听,现场回顾,往返计划,现场碎片, Pro会员.
- Respect the ADRs covering gallery references, no lyrics, on-device OCR, iOS-only, SwiftUI, SwiftData, Tencent Cloud, Doubao/Qwen, official Bilibili player, Pro packaging, and tagline split.
- The Google Doc and local product definition are now the narrative source of truth, but implementation should treat the glossary and ADRs as the sharper constraints.
- The expected testing seams are: app flow, domain state, persistence, backend contracts, StoreKit entitlement behavior, notification scheduling, privacy boundaries, and Bilibili player boundary.
