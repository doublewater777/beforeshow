# Client enriches missing 曲目档位 and 曲目短因

Generation and the backend prompt require each 歌单猜想 item to include a **tier** (`high|mid|guest|encore`) and a short Chinese **hint**. In practice older or partial responses still return only song name + artist. Leaving those rows as all「较可能」with empty sides makes the product look broken relative to ADR 0017 / the home feature-cards prototype.

**Decision:** After generate, and once when opening a sheet whose *generated* rows are all mid with no hints, the client fills a plausible live-set shape and short 因. Model-provided non-mid tiers and any existing hints are preserved. Hand-added songs are out of scope: no forced tier picker, no auto-filled short 因, and they are not rewritten by the legacy repair pass (user cares about name + order; 最想看 is a separate heart).

**Trade-off:** Users may see filled tiers/hints that are shape-based fallbacks rather than model judgments, until the deployed prompt reliably returns mixed tiers and per-song short 因. We accept that over an empty or all-mid list, and keep the sheet-foot model disclaimer. Rejected alternative: wait only on backend deploy and leave existing catalogs blank until the user regenerates (and spends free/Pro generation).
