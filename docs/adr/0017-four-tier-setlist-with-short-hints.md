# Four-tier setlist rows with short hints

歌单猜想 list rows use **four 曲目档位** — 高可能、较可能、嘉宾、返场 — plus an optional **曲目短因** (about 6–12 Chinese characters) next to the tier label. Examples of short hints: 「这轮巡演主题曲」「近几站场场都唱」「全场大合唱的那首」「给北京场的彩蛋」「安可位的老熟人」. Tier and hint are produced by generation, stored locally, and default tier to 较可能 when missing; missing hints show nothing (no empty placeholder). Hints are not lyrics, long recommendation prose, source URLs, or the old structural “段落” labels (主舞台 / 舞美段落).

This supersedes ADR 0013 (two-tier confidence only). The trade-off is a richer, prototype-aligned scan of the list versus a more prediction-product feel; we keep tiers discrete and hints short so the list stays scannable rather than becoming a scoreboard.
