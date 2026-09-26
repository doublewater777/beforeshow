# Metadata Package — 开场前 1.0

Date: 2026-08-19  
依据: `docs/aso/keyword-research-cn-2026-08-19.md`  
落地文件: `metadata/app-info/*.json`, `metadata/version/1.0/*.json`

品牌句「开场之前，先进入状态」不再占用副标题（搜索权重第二）。它放在描述首屏。氛围句「灯亮之前，先进入状态」继续用于宣传文本 / 开屏 / 官网。

## zh-Hans（主市场）

### Title

| | Copy | Chars | Keywords |
|---|------|------:|----------|
| **推荐** | 开场前 - 演唱会倒计时 | 12/30 | 开场前, 演唱会, 倒计时, 演唱会倒计时 |
| Alt A | 开场前：演唱会倒计时 | 10/30 | 更中文，少两个空格 |
| Alt B | 开场前-演唱会音乐节倒计时 | 16/30 | 把音乐节提前，副标题变空 |

推荐用带空格的连字符：搜索结果里品牌和功能断开，比堆砌店名好读。

### Subtitle

| | Copy | Chars | Keywords |
|---|------|------:|----------|
| **推荐** | 音乐节与Livehouse倒数提醒 | 17/30 | 音乐节, Livehouse, 倒数, 提醒 |
| Alt A | 音乐节与Livehouse倒数小组件 | 18/30 | 更工具，少「提醒」 |
| Alt B | 开场之前，先进入状态 | 11/30 | 品牌，几乎不贡献新词 |

不把「小组件」塞满 30 字。标题已经有倒计时，副标题负责场馆类型 + 口语「倒数」+ 利益「提醒」。

### Keyword Field

```
演出,现场,观演,音乐会,足迹,日历,通知,准备,巡演,散场,记录,海报,艺人,乐队,下一场,待看,开场,记忆,小组件,widget,concert,festival,countdown,场馆,安可
```

99/100。未重复标题/副标题里的：开场前、演唱会、倒计时、音乐节、Livehouse、倒数、提醒。

未收入：歌单（迁移意图）、票根（产品边界）、演出购票类。

### Promotional Text

`灯亮之前，先进入状态。为下一场演唱会、Livehouse 或音乐节留一个安静的倒数。`  
42/170。上线后可随季节改，不用过审。

### Description（转化，不索引）

见 `metadata/version/1.0/zh-Hans.json`。首屏：品牌句 + 不是票夹 + 免费容量/小组件。

## zh-Hant

| Field | Copy | Chars |
|-------|------|------:|
| Title | 開場前 - 演唱會倒數 | 11/30 |
| Subtitle | 音樂祭與Livehouse提醒小組件 | 18/30 |
| Keywords | `演出,現場,觀演,音樂會,足跡,日曆,通知,準備,巡演,散場,紀錄,海報,藝人,樂隊,下一場,待看,開場,記憶,concert,festival,countdown,live,widget,安可,場館` | 100/100 |

港台用户搜「倒數」多于「倒計時」，标题改用倒數。音樂祭是当地词，不是「音乐节」的硬译。

## en-US

| Field | Copy | Chars |
|-------|------|------:|
| Title | BeforeShow - Concert Countdown | 30/30 |
| Subtitle | Festival & Livehouse Reminders | 30/30 |
| Keywords | `widget,setlist,gig,tour,venue,show,memory,recap,fan,tracker,diary,upcoming,alert,live,archive,note` | 98/100 |

未重复：BeforeShow, Concert, Countdown, Festival, Livehouse, Reminders。

## Coverage Matrix（zh-Hans）

| Keyword | Title | Subtitle | Keywords |
|---------|:-----:|:--------:|:--------:|
| 开场前 | ✓ | | |
| 演唱会 | ✓ | | |
| 倒计时 | ✓ | | |
| 音乐节 | | ✓ | |
| Livehouse | | ✓ | |
| 倒数 | | ✓ | |
| 提醒 | | ✓ | |
| 现场 | | | ✓ |
| 观演 | | | ✓ |
| 小组件 | | | ✓ |
| 足迹 | | | ✓ |
| concert / festival / countdown | | | ✓ |

## Before / After

| Field | 旧草稿 | 新 | 改进 |
|-------|--------|----|------|
| Title | 开场前（3） | 开场前 - 演唱会倒计时（12） | 吃下主组合词 |
| Subtitle | 演唱会倒计时与现场准备（11，且和 ADR 品牌句打架） | 音乐节与Livehouse倒数提醒（17） | 不再和标题重复「演唱会/倒计时」 |
| Keywords | 39 字，含重复「记录」 | 99 字，无标题重复 | +60 字索引 |
| Description | 一段品牌独白 | 首屏 hook + 利益点 + 三步 + 订阅说明 | 按转化写 |
| 品牌句 | 误放副标题 | 描述首屏 + 宣传文本 | 搜索和品牌拆开 |
