# No music-platform search handoff from 歌单猜想

歌单猜想 will not open a default music app search for a song, and the Settings entry **默认音乐平台** will be removed in this version. Users still get song title, artist, order, four 曲目档位, 曲目短因, 最想看 (heart), edit/share, and generation — not in-app试听 or platform deep links.

This supersedes the music-app search handoff expectation for the setlist surface in ADR 0002 and product copy that described试听 via platform search. ADR 0002’s decision not to display lyrics still stands. The trade-off is a simpler sheet and less platform-integration surface versus losing one-tap试听; we can restore a handoff later if试听 becomes a product priority again.
