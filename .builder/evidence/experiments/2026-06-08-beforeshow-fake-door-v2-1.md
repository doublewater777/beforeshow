# 2026-06-08 BeforeShow Fake Door V2.1

Fake Door Test:

Target user: people with a real upcoming concert or music festival, especially 半熟用户 who know a few songs but do not feel ready.

Promise: BeforeShow helps them enter the show mood during the 14 days before the event.

Surface: `apps/fake-door`, a Vite landing page with interactive fake doors, a waitlist form, and local research export.

Traffic source: seed-user prototype sessions, social posts before concerts, music festival lineup discussions, and post-show survey follow-up.

Conversion action: user submits name, email, and a real upcoming show. Stronger signal if the same session includes setlist correction, countdown save, artist marking, traffic interest, or main-show switching.

Pass threshold: enough target users submit contact info, and P0 doors show deep behavior rather than click-only curiosity.

Time window: 4 weeks.

Follow-up plan for converters: invite them to a small prototype test, ask which upcoming show they want to prepare for, and compare their behavior across countdown, setlist, festival, and traffic doors.

## Door Scope

P0:

- Big countdown homepage emotion.
- AI setlist with user correction.
- Music festival multi-artist planning.

P1:

- AI traffic card.
- Main-show switching for heavy concert users.

P2:

- Live-video prep intent.

P3:

- Post-show anonymous message intent.

## Measurement

Events saved locally:

- `page_view`
- `door_select`
- `save_countdown`
- `song_correction`
- `artist_switch`
- `artist_plan`
- `traffic_interest`
- `join_intent`
- `lead_submit`
- export actions

Lead fields saved locally:

- name
- email
- upcoming show
- user segment
- selected feature interests
- interview opt-in
- source door

## Known Limits

No backend is currently implemented. The page is usable for local or moderated user tests and can export data. For public traffic, add an endpoint through `VITE_BEFORESHOW_EVENT_ENDPOINT` and replace local lead storage with a server-side form handler.

Real AI setlist, route search, Bilibili embedded playback, email delivery, and TestFlight distribution are intentionally not built in this fake-door pass.
