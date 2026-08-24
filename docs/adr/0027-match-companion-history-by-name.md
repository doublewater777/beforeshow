# Match companion history by name

BeforeShow still has no stable cross-show companion identity. Names are trimmed, de-duplicated lists stored on each show.

Two different counts reuse those names:

- Companion-sheet 共同足迹: completed, confirmed shows whose companion name **sets are equal**. Going with A, then later with A and B, are two groups.
- Footprint identity: each named person is counted pairwise wherever that name appears in `companionNames` on a completed confirmed show.

Renamed companions stop matching, and different people with the same name can collide. That is accepted until a stable companion ID exists.
