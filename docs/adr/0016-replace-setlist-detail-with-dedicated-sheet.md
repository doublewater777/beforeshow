# Replace setlist detail with a dedicated 歌单猜想 sheet

The home feature card opens a **new dedicated sheet** for 歌单猜想. The previous full-page `CandidateSongsView` playlist detail (poster hero, platform search row actions, and related chrome) is removed rather than evolved in place or kept as a second entry.

First generation is one-tap from existing show data (no extra three-field form). Regeneration requires explicit user confirmation and must preserve user-added songs and starred songs. Music-festival users can adjust which artists participate from inside the sheet (via existing 艺人关注项); if a setlist already exists, the app asks before regenerating. This version does not track “already played” marks.

The trade-off is a cleaner single surface aligned with the home feature-cards prototype versus rewriting a working detail screen; dual entry points were rejected to avoid two UIs for one capability.
