# Home composition is Poster Atlas only

**Status:** accepted

BeforeShow previously documented **three parallel home compositions**:

1. A dashboard-leaning “Home Experience Contract” (full-bleed upper hero, preparation rail, countdown-as-bridge)
2. **Poster Atlas** (freestanding centered 3:4 poster, countdown below, one “今天可以做” action)
3. **Native Poster Continuity** (preserve shipped native scale, utility row, horizontal tools, floating tab bar)

For a solo product, three home targets is fatal maintenance cost and blocks design decisions from converging.

**Decision:** **Poster Atlas is the sole home composition.** Spec: `DESIGN.md` → Home Composition Contract — Poster Atlas. Prototype of record: `apps/ios/BeforeShow/prototypes/home-poster-atlas.html`.

Retired as home targets (do not reintroduce):

- Home Experience Contract (as a competing layout)
- Native Poster Continuity (as a design target)

Shipped native UI that still matches Continuity is **migration debt**, not a co-equal direction.

**Out of scope of this ADR:** tool / sheet chrome. `home-feature-cards-mrnv1rxl.html` remains the visual source for 歌单猜想 / 「怎么去」 feature surfaces and global V3 palette — it is not a second home layout.

**Trade-off:** highest emotional distinctiveness and a single composition to implement, versus a larger gap from the currently shipped home (tabs, tool rail, Continuity spacing). We accept the migration cost so documentation and implementation share one north star.
