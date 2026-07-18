# Show two-tier song confidence on 歌单猜想

BeforeShow will display a coarse two-tier confidence on each song in 歌单猜想: **高可能** and **较可能**. Confidence is produced by the generation API with the song list, stored with each local song, and defaults to 较可能 when missing (including older local data). It is not a percentage, recommendation reason, segment label, or guest/encore role, and it does not claim official setlist truth.

This revises the earlier product rule that candidate songs must not show confidence. The trade-off is clearer list scanning versus a stronger “prediction product” feel; we accept the former and keep the field deliberately coarse so it stays a hint, not a score.
