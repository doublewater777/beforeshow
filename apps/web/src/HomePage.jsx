const APP_STORE_URL = "https://apps.apple.com/cn/app/id6780078298";

// ── 核心特色功能深度展示（配图） ────────────────────────────────
const coreFeatures = [
  {
    id: "listen",
    kicker: "阵容海报与听看预习",
    title: "开场前，先把歌听熟，把现场看透",
    desc: "按这一场的演出阵容自动编排海报式名录，搭配独创「帮我挑一张」3D 唱片柜与流动动效挑选心仪专辑；智能匹配 Apple Music 热门试听曲与本场专属歌单。更支持一键切换「看」现场实况视频，提前感受舞美与气氛。",
    bullets: [
      "音乐节海报式层级排布（头牌、主力与完整阵容），点击直达艺人专页",
      "「帮我挑一张」：3D 唱片柜、一屏一张、正面唱片架、旋转木马、冲天抛洒与飘羽等百变动效",
      "智能匹配 Apple Music 阵容热门代表作试听曲，本场专属歌单聚合",
      "看 · 舞台现场视频：智能联动参演艺人 Bilibili 演出与巡演舞台实况",
      "Liquid Glass 流体磨砂胶囊底栏，常驻迷你播放器无感跨页切歌",
    ],
    mockup: "listen",
  },
  {
    id: "timetable",
    kicker: "多舞台排期矩阵",
    title: "多舞台时刻表，不错过每一场精彩",
    desc: "长图海报一键 OCR 智能解析，自动生成多舞台演出时刻表。支持多舞台横屏展开大画幅沉浸浏览，彻底消除边缘遮挡与黑边；演出时间冲突直观高亮，一键标星最期待的乐队并在登台前送达轻提醒。",
    bullets: [
      "海报与排期长图截图一键 OCR 智能解析与原图画中画比对",
      "多舞台多时段横屏排期矩阵，画幅开阔无遮挡",
      "跨舞台演出重叠冲突智能高亮，轻松规划赶场",
      "想看乐队一键标星，开演前专属提醒准时送达",
      "精美个人观演时刻表海报导出，随心分享同伴",
    ],
    mockup: "timetable",
  },
  {
    id: "widgets",
    kicker: "灵动岛与全尺寸小组件",
    title: "不用打开，也在靠近",
    desc: "锁屏实时活动（Live Activity）与灵动岛全程陪伴：从开场倒数、正在演出到下一场预告动态刷新。小、中、大号桌面小组件随心排布，抬起手机，心跳与开场同频。",
    bullets: [
      "灵动岛与锁屏 Live Activity 实时动态追踪",
      "“即将开场 · 正在演出 · 散场次日”三阶段无感接力",
      "全尺寸小、中、大号桌面现场倒计时与试听合辑小组件",
      "锁屏圆形与长条倒计时时钟，抬手即览",
      "舞台蓝与暖金双色阶主题，完美融入桌面布局",
    ],
    screen: "/screens/home.jpg",
    alt: "主屏上的开场前倒计时与播放器小组件",
  },
  {
    id: "footprints",
    kicker: "散场仪式与生活足迹",
    title: "散场后，收进足迹",
    desc: "散场专属仪式感：三段式记录“开场前、进行中、散场后”的现场随拍照片、实体票根与真实感想。去过的场次、城市足迹地图、场馆分布与看演艺人自动沉淀，回头看看，这就是你的现场生活。",
    bullets: [
      "“开场前 · 进行中 · 散场后”三段式现场回忆碎片与胶卷印样",
      "散场仪式烟花与离场打卡，为今晚画上圆满句点",
      "现场实况 Setlist 歌单、周边谷子柜与演出开销手账收录",
      "足迹全景归档：累计场次、城市地图、星空音阶与场馆分布",
      "现场门票票根与 Backstage Pass 后台通行证质感长图生成",
    ],
    screen: "/screens/footprints.jpg",
    alt: "开场前「足迹」页：现场场次、轨迹与艺人统计",
  },
];

// ── 全流程功能矩阵（涵盖每一个 Feature） ──────────────────────────
const featureCategories = [
  {
    category: "现场筹备与添加",
    tagline: "3 秒建档，雨天晴天出行早知道",
    items: [
      {
        title: "购票链接智能解析",
        desc: "支持大麦、秀动、猫眼等主流票务平台链接，粘贴即可快速解析演出时间、场馆与艺人阵容。",
        icon: "ticket",
      },
      {
        title: "截图 OCR 智能提取",
        desc: "海报、宣传单、电子票截图直接导入，OCR 智能提取关键现场信息，告别手动誊抄。",
        icon: "scan",
      },
      {
        title: "精准现场倒计时",
        desc: "按天、时、分三段式高精度倒数，舞台微光质感卡片，支持生成倒计时海报卡片分享同伴。",
        icon: "timer",
      },
      {
        title: "现场模式 (Live Mode)",
        desc: "演出当天自动切换至现场模式，实时脉冲提醒当前登台乐队与下一场演出，不错过高光瞬间。",
        icon: "sparkles",
      },
      {
        title: "现场天气胶囊与贴士",
        desc: "现场降水概率、体感温度与风速一目了然，附带防雨防晒出行贴士，雨天晴天早做准备。",
        icon: "cloud-sun",
      },
      {
        title: "同行搭子与同看纪念册",
        desc: "基于 CloudKit 私有协同邀请看演搭子，沉淀共同观演足迹，生成专属双人同看纪念册。",
        icon: "users",
      },
      {
        title: "现场资产凭据收纳",
        desc: "集中收纳电子门票截图、纸质票照片、入场二维码与身份证件备忘，弱网断网离线秒开。",
        icon: "folder",
      },
    ],
  },
  {
    category: "多舞台演出时刻表",
    tagline: "音乐节多舞台排期，横屏大画幅沉浸体验",
    items: [
      {
        title: "截图长图智能转排期",
        desc: "复杂多舞台排期长图海报截屏导入，OCR 智能提取完整多时段时刻表。",
        icon: "table",
      },
      {
        title: "原图画中画比对校验",
        desc: "支持在排期矩阵旁悬浮画中画对照原图，快速校对无差错。",
        icon: "layout",
      },
      {
        title: "多舞台横屏排期矩阵",
        desc: "横屏大画幅沉浸展开，消除边缘遮挡与黑边，纵览全天多舞台演出流向。",
        icon: "grid",
      },
      {
        title: "演出冲突智能预警",
        desc: "跨舞台时间重叠智能高亮标记，直观辅助安排转场路线，不错过重要现场。",
        icon: "alert-triangle",
      },
      {
        title: "想看标星与登台提醒",
        desc: "星标最想看的音乐人，登台开演前准时触发专属轻提醒，无缝赶场。",
        icon: "star",
      },
      {
        title: "时刻表海报导出分享",
        desc: "一键生成排版考究的个人观演时刻表长图，轻松分享同行好友与朋友圈。",
        icon: "share",
      },
      {
        title: "手动排期自由增改",
        desc: "支持按舞台自由新增、编辑演出时段与阵容名单，灵活应对临时调整。",
        icon: "edit",
      },
    ],
  },
  {
    category: "现场音乐与舞台实况",
    tagline: "海报阵容一览，3D 挑唱片、听热曲与看现场视频",
    items: [
      {
        title: "「帮我挑一张」3D 唱片柜",
        desc: "独创 3D 唱片柜陈列与抽出视效，更支持一屏一张、正面唱片架、旋转木马、冲天抛洒与飘羽等 6 种立体动效挑片体验。",
        icon: "layers",
      },
      {
        title: "音乐节海报式阵容排版",
        desc: "像音乐节海报一样分级排布头牌（Headliners）、主力与全阵容名单，视觉层次分明，点击音乐人即可深入探索。",
        icon: "layout",
      },
      {
        title: "本场歌单与原声试听",
        desc: "聚合整场演出阵容精选热曲与代表作专辑，免跳转第三方应用直接试听高品质原声片段。",
        icon: "music",
      },
      {
        title: "看 · 舞台现场实况视频",
        desc: "智能收纳参演音乐人的 Bilibili 现场 Live 与巡演舞台实况视频，开场前提前感受舞美与现场燥热氛围。",
        icon: "video",
      },
      {
        title: "流体磨砂底栏与迷你播放器",
        desc: "Liquid Glass 流体玻璃胶囊底栏居中常驻迷你播放器，查排期、看天气、翻足迹时音乐不断流，无感跨页操控。",
        icon: "radio",
      },
      {
        title: "艺人专页与 Apple Music 直达",
        desc: "深度连接 Apple Music 音乐人专页与专辑发行时间线，一键唤起完整流媒体畅听整张专辑与现场歌单。",
        icon: "external-link",
      },
    ],
  },
  {
    category: "实时活动与桌面小组件",
    tagline: "不用打开，也在靠近",
    items: [
      {
        title: "灵动岛与锁屏实时活动",
        desc: "抬手看锁屏与灵动岛即刻掌握开场倒数、当前正在演出舞台与下一场预告。",
        icon: "smartphone",
      },
      {
        title: "现场生命周期三段切换",
        desc: "自动在“即将开场倒计时”、“正在演出当前台”与“散场次日”状态无感流转接力。",
        icon: "repeat",
      },
      {
        title: "全尺寸桌面小组件",
        desc: "小号、中号、大号多种规格，支持桌面现场倒计时、海报画框与正在听合辑卡片。",
        icon: "grid",
      },
      {
        title: "锁屏圆形与长条小组件",
        desc: "完美契合 iOS 锁屏时间下方区域，抬腕便能感受到下一场的临近。",
        icon: "clock",
      },
      {
        title: "冷暖双色舞台质感",
        desc: "支持深邃舞台蓝与暖金双色温主题，随心搭配个性化手机主屏幕壁纸。",
        icon: "palette",
      },
    ],
  },
  {
    category: "散场仪式与生活足迹",
    tagline: "散场后，收进足迹：手账、星空与回忆书",
    items: [
      {
        title: "散场仪式烟花打卡",
        desc: "散场专属烟花与离场打卡动效，用一次温柔的交互为今晚的演出画上圆满句号。",
        icon: "sparkles",
      },
      {
        title: "三段式现场回忆碎片",
        desc: "按「开场前、进行中、散场后」记录现场随拍照片、票根与真实感想，支持胶卷印样 Contact Sheet 网格排版。",
        icon: "camera",
      },
      {
        title: "现场实况 Setlist 歌单",
        desc: "散场后记录当晚真实演出歌单，支持在 App 内播放回味现场每一首曲目的感动。",
        icon: "music",
      },
      {
        title: "现场周边谷子柜收纳",
        desc: "现场购买的演出限定周边、乐队 T 恤、毛巾、唱片拍照入柜，留存实体收藏。",
        icon: "folder",
      },
      {
        title: "演出开销账单手账",
        desc: "门票、交通出行、酒店住宿与现场周边开销流水手账，清晰记录每一次奔赴现场的花销。",
        icon: "dollar-sign",
      },
      {
        title: "现场足迹全景图鉴",
        desc: "自动统计累计看演场次、去过的城市足迹、打卡场馆分布与观演艺人总览排行榜。",
        icon: "map-pin",
      },
      {
        title: "乐迷里程碑与成就徽章",
        desc: "专为现场乐迷设计的趣味打卡成就体系，自动点亮看演场次、打卡城市与特色场馆徽章墙。",
        icon: "award",
      },
      {
        title: "「你的星空」音阶与星图",
        desc: "每一次看演都化作夜空中的一颗星，支持大调、小调、布鲁斯等音阶交互发声弹奏，星星还可排成星座。",
        icon: "star",
      },
      {
        title: "现场回忆翻页书",
        desc: "像翻阅实体画册一样回顾历场演出的照片、门票与随记，让每一场奔赴都有迹可循。",
        icon: "book-open",
      },
      {
        title: "票根与 Backstage Pass 长图",
        desc: "一键生成复古演出门票票根、后台工作证（Backstage Pass）风格的精美长图，随心分享朋友圈。",
        icon: "file-text",
      },
    ],
  },
  {
    category: "贴心节奏通知与系统体验",
    tagline: "不打扰、不刷屏，纯净私密的现场伴侣",
    items: [
      {
        title: "7 大节点节奏轻提醒",
        desc: "开场前 14 天、7 天、3 天、1 天、当天上午、前 3 小时与散场次日，只在恰当时刻出现。",
        icon: "bell",
      },
      {
        title: "摇一摇极速反馈",
        desc: "使用过程中遇到任何问题或体验建议，摇一摇手机即可直连开发者快速反馈。",
        icon: "help-circle",
      },
      {
        title: "在线检查版本更新",
        desc: "设置页支持实时比对 App Store 最新版本，一键直达应用商店快速更新。",
        icon: "refresh-cw",
      },
      {
        title: "纯本地存储与隐私优先",
        desc: "现场数据与照片完整保存在本地及私有 iCloud，无需登录注册账号，绝不刺探隐私。",
        icon: "shield-check",
      },
      {
        title: "多语言国际化支持",
        desc: "完整适配简体中文、繁体中文与英文界面，全球看演轻松无忧。",
        icon: "globe",
      },
    ],
  },
];

// ── 7 大提醒节点 ──────────────────────────────────────────────
const reminders = [
  { label: "14 天前", desc: "开场半月，检查票务与行程安排" },
  { label: "7 天前", desc: "演出前一周，开场天气早知道" },
  { label: "3 天前", desc: "规划交通出行与现场观演路线" },
  { label: "1 天前", desc: "明天开场，温习阵容精选代表作" },
  { label: "当天上午", desc: "今日开场，注意防晒雨具与入场须知" },
  { label: "前 3 小时", desc: "演出即将开始，出发奔赴现场" },
  { label: "散场次日", desc: "演出结束，收进足迹写下回忆碎片" },
];

// ── 常见问题解答 ──────────────────────────────────────────────
const faqs = [
  {
    q: "支持哪些平台的购票链接导入？",
    a: "支持大麦、秀动、猫眼等主流票务平台的演出分享链接。在 App 内点击添加现场并粘贴链接，即可自动解析演出时间、场馆、城市及艺人阵容信息。",
  },
  {
    q: "演出时刻表如何识别？",
    a: "将官方公布的音乐节多舞台排期长图或海报保存至相册，在时刻表页面选择该长图，App 即可通过 OCR 智能识别自动生成多舞台时间线，并支持手动修正微调。",
  },
  {
    q: "听歌合辑需要额外开通 Apple Music 付费会员吗？",
    a: "不需要。BeforeShow 集成了官方公共试听服务，无需绑定账户或付费即可直接畅听当场参演音乐人的高品质 30 秒原声试听片段，适合开场前快速预习曲目。",
  },
  {
    q: "灵动岛与实时活动（Live Activity）怎么开启？",
    a: "在 iOS 17 及以上系统安装 App 后，演出开场当天及现场期间，系统将自动在锁屏与灵动岛展示实时倒计时、正在演出舞台与下一场预告，无需复杂配置。",
  },
  {
    q: "我的现场照片与足迹会被上传到服务器吗？",
    a: "不会。BeforeShow 坚持“隐私优先”原则，所有现场数据、照片和记录均完整保存在您的本地设备和私有 iCloud 容器中，我们不设远程中心化数据库，绝不收集个人现场内容。",
  },
];

function AppStoreButton({ className = "" }) {
  return (
    <a className={`store-btn ${className}`} href={APP_STORE_URL} target="_blank" rel="noopener noreferrer">
      <svg className="store-btn-mark" viewBox="0 0 384 512" aria-hidden="true">
        <path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184.8 4 273.5q0 39.3 14.4 81.2c12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z" />
      </svg>
      <span className="store-btn-text">
        <small>在 App Store</small>
        免费下载
      </span>
    </a>
  );
}

function Phone({ src, alt, eager = false }) {
  return (
    <div className="phone">
      <img src={src} alt={alt} width="720" height="1565" loading={eager ? "eager" : "lazy"} />
    </div>
  );
}

function ListenMockup() {
  return (
    <div className="listen-mockup" aria-hidden="true">
      {/* 顶部 Surface 切换 */}
      <div className="listen-surface-bar">
        <span className="listen-surface-tab active">
          <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" strokeWidth="2"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>
          听 · 阵容海报
        </span>
        <span className="listen-surface-tab">
          <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" strokeWidth="2"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2" ry="2"/></svg>
          看 · 舞台实况
        </span>
      </div>

      {/* 音乐节阵容海报 */}
      <div className="listen-poster-card">
        <div className="poster-show-tag">FESTIVAL LINEUP BILL</div>
        <div className="poster-show-title">星云音乐节 2026 · NEBULA</div>
        <div className="poster-divider" />
        <div className="poster-headliners">万能青年旅店 · 草东没有派对</div>
        <div className="poster-second">重塑雕像的权利 · 新裤子 · 落日飞车</div>
        <div className="poster-rest">惘闻 · 康姆士 · 回春丹 · 声音碎片 · 蛙池</div>
      </div>

      {/* 帮我挑一张 - 3D 唱片柜与流动动效 */}
      <div className="listen-pick-section">
        <div className="pick-section-head">
          <span className="pick-section-title">帮我挑一张</span>
          <span className="pick-section-count">12 张唱片</span>
        </div>
        <div className="listen-pick-card">
          <div className="pick-cover-3d">
            <div className="pick-cover-spine" />
            <div className="pick-cover-art">
              <span>冀西南</span>
              <span>林路行</span>
            </div>
          </div>
          <div className="pick-info">
            <span className="pick-artist">万能青年旅店</span>
            <span className="pick-album">冀西南林路行</span>
            <span className="pick-meta">10 首热门原声试听</span>
          </div>
          <div className="pick-style-tag">3D 唱片柜</div>
        </div>
      </div>

      {/* 底部 Liquid Glass 磨砂迷你播放器 */}
      <div className="listen-bottom-bar">
        <span className="nav-tab-mini">✦ 当前</span>
        <div className="liquid-glass-player">
          <div className="player-track-art">♫</div>
          <div className="player-track-info">
            <span className="player-track-title">山雀</span>
            <span className="player-track-artist">万能青年旅店</span>
          </div>
          <div className="player-controls">
            <span className="player-btn">❚❚</span>
            <span className="player-btn">⏭</span>
          </div>
        </div>
        <span className="nav-tab-mini">⚐ 足迹</span>
      </div>
    </div>
  );
}

function TimetableMockup() {
  return (
    <div className="timetable-mockup" aria-hidden="true">
      <div className="timetable-header">
        <div className="timetable-status-dot" />
        <span className="timetable-title-pill">多舞台矩阵排期 · 横屏沉浸展开</span>
        <span className="timetable-tag">LIVE STAGE</span>
      </div>
      <div className="timetable-grid">
        <div className="timetable-col">
          <div className="stage-name main-stage">主舞台 · Main Stage</div>
          <div className="slot slot-active">
            <span className="slot-time">15:30 – 16:30</span>
            <span className="slot-band">落日飞车 Sunset Rollercoaster</span>
            <span className="slot-badge">★ 想看</span>
          </div>
          <div className="slot slot-conflict">
            <span className="slot-time">17:10 – 18:10</span>
            <span className="slot-band">万能青年旅店</span>
            <span className="slot-conflict-tag">冲突预警</span>
          </div>
          <div className="slot">
            <span className="slot-time">19:30 – 20:30</span>
            <span className="slot-band">草东没有派对</span>
            <span className="slot-badge">★ 想看</span>
          </div>
        </div>
        <div className="timetable-col">
          <div className="stage-name sub-stage">回声舞台 · Echo Stage</div>
          <div className="slot">
            <span className="slot-time">16:00 – 17:00</span>
            <span className="slot-band">新裤子 New Pants</span>
          </div>
          <div className="slot slot-conflict">
            <span className="slot-time">17:30 – 18:30</span>
            <span className="slot-band">重塑雕像的权利 Re-TROS</span>
            <span className="slot-conflict-tag">冲突预警</span>
          </div>
          <div className="slot">
            <span className="slot-time">20:00 – 21:00</span>
            <span className="slot-band">惘闻 Wang Wen</span>
          </div>
        </div>
      </div>
      <div className="timetable-footer">
        <span>已标星 3 场想看 · 演出前 15 分钟轻提醒</span>
      </div>
    </div>
  );
}

function FeatureIcon({ name }) {
  switch (name) {
    case "ticket":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M2 9a3 3 0 0 1 0 6v2a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-2a3 3 0 0 1 0-6V7a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2z"/>
          <path d="M13 5v2"/><path d="M13 11v2"/><path d="M13 17v2"/>
        </svg>
      );
    case "scan":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M3 7V5a2 2 0 0 1 2-2h2"/><path d="M17 3h2a2 2 0 0 1 2 2v2"/><path d="M21 17v2a2 2 0 0 1-2 2h-2"/><path d="M7 21H5a2 2 0 0 1-2-2v-2"/>
          <rect x="7" y="7" width="10" height="10" rx="1"/>
        </svg>
      );
    case "timer":
    case "clock":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>
        </svg>
      );
    case "cloud-sun":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M12 2v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="M20 12h2"/><path d="m19.07 4.93-1.41 1.41"/><path d="M15.947 12.65a4 4 0 0 0-5.925-4.128"/>
          <path d="M13 22H7a5 5 0 1 1 4.9-6H13a3 3 0 0 1 0 6z"/>
        </svg>
      );
    case "users":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>
        </svg>
      );
    case "folder":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2z"/>
        </svg>
      );
    case "table":
    case "layout":
    case "grid":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 9h18"/><path d="M9 21V9"/>
        </svg>
      );
    case "alert-triangle":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>
        </svg>
      );
    case "star":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/>
        </svg>
      );
    case "share":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><line x1="8.59" y1="13.51" x2="15.42" y2="17.49"/><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"/>
        </svg>
      );
    case "edit":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/>
        </svg>
      );
    case "disc":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="3"/><line x1="12" y1="2" x2="12" y2="5"/><line x1="12" y1="19" x2="12" y2="22"/>
        </svg>
      );
    case "music":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>
        </svg>
      );
    case "play-circle":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="12" cy="12" r="10"/><polygon points="10 8 16 12 10 16 10 8"/>
        </svg>
      );
    case "radio":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="12" cy="12" r="2"/><path d="M16.24 7.76a6 6 0 0 1 0 8.49m-8.48-.01a6 6 0 0 1 0-8.49m11.31-2.82a10 10 0 0 1 0 14.14m-14.14 0a10 10 0 0 1 0-14.14"/>
        </svg>
      );
    case "external-link":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/>
        </svg>
      );
    case "smartphone":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <rect x="5" y="2" width="14" height="20" rx="2" ry="2"/><line x1="12" y1="18" x2="12.01" y2="18"/>
        </svg>
      );
    case "repeat":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <polyline points="17 1 21 5 17 9"/><path d="M3 11V9a4 4 0 0 1 4-4h14"/><polyline points="7 23 3 19 7 15"/><path d="M21 13v2a4 4 0 0 1-4 4H3"/>
        </svg>
      );
    case "palette":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="13.5" cy="6.5" r=".5"/><circle cx="17.5" cy="10.5" r=".5"/><circle cx="8.5" cy="7.5" r=".5"/><circle cx="6.5" cy="12.5" r=".5"/>
          <path d="M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.926 0 1.648-.746 1.648-1.688 0-.437-.18-.835-.437-1.125-.29-.289-.438-.652-.438-1.125a1.64 1.64 0 0 1 1.668-1.668h1.996c3.051 0 5.563-2.512 5.563-5.563C21.999 6.5 17.5 2 12 2z"/>
        </svg>
      );
    case "sparkles":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="m12 3-1.912 5.813a2 2 0 0 1-1.275 1.275L3 12l5.813 1.912a2 2 0 0 1 1.275 1.275L12 21l1.912-5.813a2 2 0 0 1 1.275-1.275L21 12l-5.813-1.912a2 2 0 0 1-1.275-1.275L12 3Z"/>
        </svg>
      );
    case "camera":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z"/><circle cx="12" cy="13" r="3"/>
        </svg>
      );
    case "map-pin":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/>
        </svg>
      );
    case "award":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="12" cy="8" r="7"/><polyline points="8.21 13.89 7 23 12 20 17 23 15.79 13.88"/>
        </svg>
      );
    case "file-text":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><polyline points="10 9 9 9 8 9"/>
        </svg>
      );
    case "bell":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/>
        </svg>
      );
    case "help-circle":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="12" cy="12" r="10"/><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/><line x1="12" y1="17" x2="12.01" y2="17"/>
        </svg>
      );
    case "refresh-cw":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/>
        </svg>
      );
    case "video":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2" ry="2"/>
        </svg>
      );
    case "layers":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <polygon points="12 2 2 7 12 12 22 7 12 2"/><polyline points="2 17 12 22 22 17"/><polyline points="2 12 12 17 22 12"/>
        </svg>
      );
    case "dollar-sign":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <line x1="12" y1="1" x2="12" y2="23"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/>
        </svg>
      );
    case "book-open":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"/><path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"/>
        </svg>
      );
    case "shield-check":
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><polyline points="9 12 11 14 15 10"/>
        </svg>
      );
    case "globe":
    default:
      return (
        <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/>
        </svg>
      );
  }
}

export default function HomePage() {
  return (
    <>
      <a href="#main-content" className="skip-link">跳到主要内容</a>
      <header className="site-nav">
        <a className="nav-logo" href="/">
          <img src="/app-icon.png" alt="" width="32" height="32" />
          <span>开场前</span>
        </a>
        <nav className="nav-menu" aria-label="网站主要导航">
          <a href="#features">核心特色</a>
          <a href="#all-features">全流程功能</a>
          <a href="#reminders">节奏提醒</a>
          <a href="#faqs">常见问题</a>
        </nav>
        <a className="nav-cta" href={APP_STORE_URL} target="_blank" rel="noopener noreferrer">App Store 下载</a>
      </header>

      <main id="main-content">
        {/* ── Hero ────────────────────────────────────────────── */}
        <section className="hero" aria-labelledby="hero-title">
          <div className="hero-seam" aria-hidden="true" />
          <div className="hero-copy">
            <p className="eyebrow"><span className="eyebrow-dot" />演唱会 · 音乐节 · Livehouse 现场伴侣</p>
            <h1 id="hero-title" className="hero-title">灯亮之前，<br />先进入状态。</h1>
            <p className="hero-sub">首页只围着下一场：海报、实时倒计时、排期时刻表、演出天气与同行搭子都在一屏里，陪你慢慢靠近这一场。</p>
            <div className="hero-actions">
              <AppStoreButton />
              <span className="hero-note">iOS 17+ · 支持灵动岛与全尺寸小组件 · 前 5 场免费保存</span>
            </div>
          </div>
          <div className="hero-visual">
            <Phone src="/screens/current.jpg" alt="开场前「当前」页：现场海报与开场倒计时" eager />
          </div>
        </section>

        {/* ── 核心特色功能深度展示 ────────────────────────────── */}
        <section id="features" aria-label="核心特色功能">
          {coreFeatures.map((feature, index) => (
            <div
              className={`feature ${index % 2 ? "feature-flip" : ""}`}
              id={feature.id}
              key={feature.id}
            >
              <div className="feature-copy">
                <p className="feature-kicker">{String(index + 1).padStart(2, "0")} · {feature.kicker}</p>
                <h2 className="feature-title">{feature.title}</h2>
                <p className="feature-desc">{feature.desc}</p>
                {feature.bullets && (
                  <ul className="feature-bullets">
                    {feature.bullets.map((bullet) => (
                      <li key={bullet}>
                        <span className="bullet-icon">✓</span>
                        <span>{bullet}</span>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
              <div className="feature-visual">
                {feature.mockup === "timetable" ? (
                  <TimetableMockup />
                ) : feature.mockup === "listen" ? (
                  <ListenMockup />
                ) : (
                  <Phone src={feature.screen} alt={feature.alt} />
                )}
              </div>
            </div>
          ))}
        </section>

        {/* ── 现场全流程功能矩阵 ────────────────────────────────── */}
        <section className="all-features-section" id="all-features" aria-labelledby="all-features-title">
          <div className="section-head">
            <p className="feature-kicker">现场全流程功能矩阵</p>
            <h2 className="section-title" id="all-features-title">从筹备、赶场到回忆，每个功能都为现场而生</h2>
            <p className="section-sub">告别零散杂乱的备忘录与截图，一站式陪伴你的每一场现场生活。</p>
          </div>

          <div className="categories-stack">
            {featureCategories.map((cat, catIdx) => (
              <div className="category-block" key={cat.category}>
                <div className="category-header">
                  <span className="category-num">0{catIdx + 1}</span>
                  <div className="category-titles">
                    <h3 className="category-name">{cat.category}</h3>
                    <p className="category-tagline">{cat.tagline}</p>
                  </div>
                </div>

                <div className="category-grid">
                  {cat.items.map((item) => (
                    <div className="feature-card" key={item.title}>
                      <div className="card-icon-wrap">
                        <FeatureIcon name={item.icon} />
                      </div>
                      <h4 className="card-title">{item.title}</h4>
                      <p className="card-desc">{item.desc}</p>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </section>

        {/* ── 节奏节点提醒 ────────────────────────────────────── */}
        <section className="reminders" id="reminders" aria-labelledby="reminders-title">
          <p className="feature-kicker">轻轻提醒</p>
          <h2 className="feature-title" id="reminders-title">只在该出现的时候出现</h2>
          <p className="feature-desc">7 大关键节点轻提醒，用你已经记下的现场信息说话，不刷屏，也不打扰。</p>
          <ol className="reminder-track">
            {reminders.map((r, idx) => (
              <li key={r.label}>
                <span className={`reminder-dot ${idx === reminders.length - 2 ? "active" : ""}`} />
                <strong className="reminder-node-label">{r.label}</strong>
                <span className="reminder-node-desc">{r.desc}</span>
              </li>
            ))}
          </ol>
        </section>

        {/* ── 常见问题解答 ────────────────────────────────────── */}
        <section className="faqs-section" id="faqs" aria-labelledby="faqs-title">
          <div className="section-head">
            <p className="feature-kicker">常见问题</p>
            <h2 className="section-title" id="faqs-title">常见疑问解答</h2>
          </div>
          <div className="faqs-grid">
            {faqs.map((faq) => (
              <div className="faq-card" key={faq.q}>
                <h3 className="faq-question">{faq.q}</h3>
                <p className="faq-answer">{faq.a}</p>
              </div>
            ))}
          </div>
        </section>

        {/* ── 底部行动召唤 ────────────────────────────────────── */}
        <section className="closing" aria-labelledby="closing-title">
          <img className="closing-icon" src="/app-icon.png" alt="" width="96" height="96" loading="lazy" />
          <h2 className="closing-title" id="closing-title">下一场，从开场前开始。</h2>
          <p className="closing-sub">在 App Store 免费获取，让下一场现场更有期待感。</p>
          <AppStoreButton />
        </section>
      </main>

      {/* ── 页脚 ────────────────────────────────────────────── */}
      <footer className="footer">
        <div className="footer-brand">
          <span>开场前 · BeforeShow</span>
          <span className="footer-slogan">灯亮之前，先进入状态。</span>
        </div>
        <nav className="footer-links" aria-label="页脚链接">
          <a href="/privacy/">隐私政策</a>
          <a href="/terms/">用户协议</a>
          <a href="/link-guide/">如何获取票务链接</a>
          <a href="https://beian.miit.gov.cn/" target="_blank" rel="noopener noreferrer">浙ICP备2026041359号-3A</a>
        </nav>
      </footer>
    </>
  );
}
