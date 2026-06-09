# Fake Door Stage

## Current Summary

BeforeShow is testing whether people with a real upcoming concert or music festival will move beyond polite interest and leave contact information for a prep companion. The current page is a usable local fake-door surface with a landing page, interactive feature doors, usage-flow narrative, audience fit section, a waitlist form, local event tracking, and JSON/CSV export.

The riskiest demand signal is not a click. It is whether the target user has a real upcoming show and voluntarily leaves contact information after trying one of the doors.

## Inputs

Target wedge: 已买五月天演唱会门票、正在等开场的用户。

Promise: 输入下一场要看的演出，生成开场前 14 天预习清单。通过倒数提醒、AI 预测歌单、现场视频、出行方案，以及导入网易云音乐/QQ 音乐，帮助用户更快进入状态并降低准备成本。

Traffic source:

- 演出前两周种草帖。
- 五月天演唱会相关讨论和抢票后分享。
- TestFlight or local prototype user test.
- 演后问卷回访。

Pass threshold:

- Primary conversion: users submit name, email, and a real upcoming show.
- P0 behavioral signal: countdown save, setlist correction, artist marking, or main-show switching happens before conversion.
- Minimum useful sample: 50 seed users for prototype testing, 300+ visits for landing-page directional reads.

## Evidence

Artifacts:

- App source: `apps/fake-door/`
- Original plan archive: `.builder/evidence/artifacts/2026-06-08-beforshow-fake-door-plan-revised.html`
- Experiment record: `.builder/evidence/experiments/2026-06-08-beforeshow-fake-door-v2-1.md`

The page stores events and leads in browser localStorage when no backend is configured. If `VITE_BEFORESHOW_EVENT_ENDPOINT` is set, events are also sent to that endpoint.

## Decisions

Build only the deterministic validation surface now:

- Landing copy and primary conversion form.
- Seven fake doors from the revised plan.
- Interactive P0/P1 prototypes with local behavior tracking.
- Local export for research review.

Leave backend aggregation, email delivery, real AI, real route search, Bilibili playback, and TestFlight distribution as follow-up implementation work.

## Gate

Pass if target users with real upcoming shows submit the form and the same session includes at least one meaningful feature-door action.

Fail if clicks happen without contact info, if converters are outside the target wedge, or if users only praise the concept without taking a concrete action.
