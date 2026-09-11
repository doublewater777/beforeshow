# Offline ASO Audit — local `metadata/` 1.0

Date: 2026-08-19  
Primary locale: zh-Hans  
Astro MCP: 未接，跳过关键词缺口抓取

## Field Utilization

| Locale | Name | Subtitle | Keywords | Promo | Description |
|--------|------|----------|----------|-------|-------------|
| zh-Hans | 12/30 | 17/30 | 99/100 | 42/170 | 453/4000 |
| zh-Hant | 11/30 | 18/30 | 100/100 | 42/170 | 441/4000 |
| en-US | 30/30 | 30/30 | 98/100 | 107/170 | 1078/4000 |

## Checks

| # | Check | Sev | Field | Locale | Detail |
|---|-------|-----|-------|--------|--------|
| 1 | Over limit / missing / separators | — | — | — | **0 errors** |
| 2 | Subtitle < 20 | ⚠️ | subtitle | zh-Hans / zh-Hant | 17、18。中文信息密度高于英文，再加字会变成「倒数提醒小组件」堆砌。接受。 |
| 3 | Keyword waste | ⚠️ | keywords | zh-Hans / zh-Hant | `开场` / `開場` 与店名 `开场前` 有子串重叠。保留：品牌复合词不一定单独索引「开场」。 |
| 4 | Desc coverage | 💡 | description | all | 关键词栏里的索引词不必全部写进描述。描述按转化写，不堆「观演/巡演/待看」。 |

**Summary:** 0 errors, 2 accepted warnings.

## 还不能靠这次 audit 关掉的事

- ASC 上仍是空 listing，这是本地稿审计
- 没有真实排名
- 截图未上传；缺小组件一张
- zh-Hant / en-US locale 还没在 ASC 创建
