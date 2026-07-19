# Four-tier setlist rows with short hints

**Status:** accepted (fill rules refined by ADR 0020)

歌单猜想 list rows use **four 曲目档位** with prototype display labels **高概率 / 可能 / 嘉宾曲目 / 安可猜测**, plus a **曲目短因** (about 6–12 Chinese characters) next to the tier label. Examples: 「这轮巡演主题曲」「近巡必唱」「给北京场的彩蛋」「安可位常客」. Generation is expected to produce both tier and short hint. Hints are not lyrics, long recommendation prose, source URLs, or the old structural “段落” labels (主舞台 / 舞美段落).

This supersedes ADR 0013 (two-tier confidence only). The trade-off is a richer, prototype-aligned scan of the list versus a more prediction-product feel; we keep tiers discrete and hints short so the list stays scannable rather than becoming a scoreboard.

How missing tier/hint is handled when the model or an old payload omits them is decided in **ADR 0020** (client enrich / legacy repair), not “always mid + blank side.”
