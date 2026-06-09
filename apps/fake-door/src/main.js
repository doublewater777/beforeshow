import "./styles.css";
import { submitLeadToFeishu } from "./feishu.js";

// ── Data ────────────────────────────────────────────
const STORAGE_LEADS = "beforeshow.leads.v2";
const STORAGE_EVENTS = "beforeshow.events.v2";
const STORAGE_SESSION = "beforeshow.session.v2";

const shows = [
  {
    id: "mayday",
    type: "concert",
    label: "演唱会",
    artist: "五月天",
    venue: "上海体育场",
    date: "2026-06-22T19:30:00+08:00",
    accent: "#e86c4a",
    song: "倔强",
    traffic: {
      alert: "建议提前 90 分钟出发，开演前 1 小时入场口会封堵。",
      go: {
        metro: "地铁 3/4 号线 → 上海体育馆站 3 号口出，步行约 8 分钟。",
        taxi: "打车预估 ¥35–55，建议提前叫车，演出日附近打车溢价约 1.5x。",
        walk: "从地铁口步行 800 米，沿场馆围栏绕行，约 10 分钟。",
        entry: "建议走东门（C/D 入口），排队通常比南门短 15–20 分钟。",
      },
      back: {
        metro: "散场高峰期地铁候车约 20 分钟，建议等人潮散去再出发。",
        taxi: "散场后溢价约 2x，建议步行到 500 米外的兴国路再叫车。",
        walk: "步行至最近地铁站约 10 分钟，可边走边回味演出。",
        tip: "散场后先在场馆附近等 15–20 分钟，人潮散去后交通会顺畅很多。",
      },
    },
    videos: [
      {
        bvid: "BV1bt411Q7Lp",
        title: "《倔强》万人合唱",
        desc: "演唱会大合唱氛围，最能体现五月天现场。",
      },
      {
        bvid: "BV1gG4y1S7kN",
        title: "《突然好想你》跨年现场",
        desc: "2023 线上跨年，情绪共鸣的代表现场。",
      },
    ],
  },
  {
    id: "soundtoy",
    type: "live",
    label: "Live",
    artist: "声音玩具",
    venue: "北京丁香山 MAO Livehouse",
    date: "2026-07-12T20:00:00+08:00",
    accent: "#b05bff",
    song: "音乐状态",
    liveInfo: {
      capacity: "少于 300 人小场",
      vibe: "你能听到拨弦和呼吸声",
      seating: "站立区 + 少量吧台座位",
    },
    traffic: {
      alert: "Livehouse 周边停车极少，强烈建议地铁或打车。",
      go: {
        metro: "地铁 10 号线 → 三元桥站 D 口出，步行约 12 分钟。",
        taxi: "打车预估 ¥25–40，可在场馆门口直接下车。",
        walk: "从三元桥地铁出口步行约 1.2 公里，沿朝阳公园路直行。",
        entry: "小场只有一个入口，建议开演前 30 分钟到，换票需要时间。",
      },
      back: {
        metro: "散场后地铁压力较小，基本不用等，直接走。",
        taxi: "Livehouse 附近好叫车，散场溢价约 1.2x。",
        walk: "步行回三元桥站约 12 分钟，一路有路灯，适合晚上步行。",
        tip: "小场散场快，出来后没有大型演唱会的人潮，基本不用等。",
      },
    },
    videos: [
      {
        bvid: "BV1y5411u78V",
        title: "声音玩具现场",
        desc: "小场现场氛围，立即感受拨弦和人与人之间的距离感。",
      },
    ],
  },
  {
    id: "westlake",
    type: "festival",
    label: "音乐节",
    artist: "西湖音乐节",
    venue: "杭州西湖太子碗公园",
    date: "2026-08-09T14:00:00+08:00",
    accent: "#1db954",
    song: "山海",
    artists: [
      { id: "caodong",   name: "草东没有派对", slot: "14:30", stage: "主舞台" },
      { id: "mxm",      name: "毛不易",       slot: "16:10", stage: "湖边舞台" },
      { id: "wubai",    name: "伍佰",          slot: "18:00", stage: "主舞台" },
      { id: "decajoins",name: "deca joins",   slot: "20:20", stage: "湖边舞台" },
      { id: "sodagreen",name: "苏打绿",        slot: "21:30", stage: "主舞台" },
    ],
    traffic: {
      alert: "音乐节场地在西湖边，公共交通有限，提前规划是关键。",
      go: {
        metro: "地铁 1 号线 → 定安路站 A 口出，步行约 18 分钟或转公交。",
        taxi: "打车预估 ¥20–35，节日期间路面可能拥堵，预留 30 分钟余量。",
        walk: "从定安路地铁站步行约 1.5 公里，沿湖边小路，风景不错。",
        entry: "主舞台区建议走北门，湖边舞台走南入口，分开可以节省排队时间。",
      },
      back: {
        metro: "22:00 后末班车，压轴演出结束后需尽快前往地铁站。",
        taxi: "散场后叫车困难，建议提前 30 分钟叫好车或多人拼车。",
        walk: "步行至定安路地铁约 20 分钟，注意末班车时间。",
        tip: "音乐节散场叫车是难点，强烈建议和同伴约好集合点，或留到人潮散去再离场。",
      },
    },
    videos: [
      {
        bvid: "BV1hD421G7rA",
        title: "西湖音乐节现场 Vol.1",
        desc: "湖边演出的独特氛围，感受一下现场气场。",
      },
      {
        bvid: "BV1Fb421q7x1",
        title: "西湖音乐节现场 Vol.2",
        desc: "夜场压轴演出现场，了解音乐节的最佳气氛。",
      },
    ],
  },
];

const starterSongs = [
  { id: "s1", title: "突然好想你", weight: 95, status: "很可能会唱" },
  { id: "s2", title: "派对动物",   weight: 86, status: "重点预习" },
  { id: "s3", title: "知足",       weight: 81, status: "已经听过" },
  { id: "s4", title: "爱情万岁",   weight: 73, status: "待判断" },
  { id: "s5", title: "终结孤单",   weight: 68, status: "待判断" },
  { id: "s6", title: "而我知道",   weight: 59, status: "待判断" },
];

// ── State ────────────────────────────────────────────
const state = {
  tab: "countdown",
  activeVideoIdx: 0,
  activeShowId: "westlake",   // default: festival
  songs: readJson("songs", starterSongs),
  festivalWishlist: readJson("festivalWishlist", {}),
  formErrors: {},
  submitting: false,
  submitted: false,
  toast: "",
};

// ── Storage helpers ──────────────────────────────────
function readJson(key, fallback) {
  try {
    const raw = localStorage.getItem(`beforeshow.${key}.v2`);
    return raw ? JSON.parse(raw) : fallback;
  } catch { return fallback; }
}

function writeJson(key, value) {
  localStorage.setItem(`beforeshow.${key}.v2`, JSON.stringify(value));
}

function getSessionId() {
  const existing = localStorage.getItem(STORAGE_SESSION);
  if (existing) return existing;
  const id = `s_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;
  localStorage.setItem(STORAGE_SESSION, id);
  return id;
}

function track(type, detail = {}) {
  const event = {
    id: `e_${Date.now().toString(36)}`,
    at: new Date().toISOString(),
    session: getSessionId(),
    type,
    ...detail,
  };
  try {
    const raw = localStorage.getItem(STORAGE_EVENTS);
    const arr = raw ? JSON.parse(raw) : [];
    arr.push(event);
    localStorage.setItem(STORAGE_EVENTS, JSON.stringify(arr.slice(-300)));
  } catch {}
}

// ── Helpers ──────────────────────────────────────────
function esc(v) {
  return String(v)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function daysUntil(iso) {
  return Math.max(0, Math.ceil((new Date(iso) - Date.now()) / 86400000));
}

function selectedShow() {
  return shows.find((s) => s.id === state.activeShowId) || shows[0];
}

function formatDate(iso) {
  return new Intl.DateTimeFormat("zh-CN", {
    month: "long", day: "numeric",
    hour: "2-digit", minute: "2-digit",
  }).format(new Date(iso));
}

// ── Render ───────────────────────────────────────────
function render() {
  const app = document.getElementById("app");
  if (!app) return;
  app.innerHTML = `
    ${renderNav()}
    <main>
      ${renderHero()}
      ${renderExperience()}
      ${renderHow()}
      ${renderJoin()}
    </main>
    ${renderFooter()}
    ${state.toast ? `<div class="toast" role="status">${esc(state.toast)}</div>` : ""}
  `;
}

// ── Nav ──────────────────────────────────────────────
function renderNav() {
  return `
    <nav class="site-nav" aria-label="主导航">
      <div class="nav-logo">
        <div class="nav-logo-mark" aria-hidden="true">
          <svg viewBox="0 0 18 18" xmlns="http://www.w3.org/2000/svg">
            <path d="M9 1.5 C9 1.5 2 5.5 2 11a7 7 0 0 0 14 0C16 5.5 9 1.5 9 1.5Z"/>
            <circle cx="9" cy="10" r="2.5"/>
          </svg>
        </div>
        <span class="nav-brand">开场前</span>
      </div>
      <div class="nav-cta">
        <button class="btn btn-ghost btn-sm" data-scroll="#experience">先体验</button>
        <button class="btn btn-primary btn-sm" data-scroll="#join">加入内测</button>
      </div>
    </nav>
  `;
}

// ── Hero ─────────────────────────────────────────────
function renderHero() {
  return `
    <section class="hero" aria-labelledby="hero-title">
      <div class="hero-bg" aria-hidden="true">
        <div class="hero-bg-base"></div>
        <div class="beam beam-1"></div>
        <div class="beam beam-2"></div>
        <div class="beam beam-3"></div>
        <div class="beam beam-4"></div>
        <div class="stage-orb"></div>
        <div class="hero-crowd"></div>
      </div>
      <div class="hero-content">
        <div class="hero-eyebrow fade-up">
          <span class="hero-eyebrow-dot"></span>
          演出前预习助手
        </div>
        <h1 id="hero-title" class="hero-title fade-up fade-up-delay-1">
          <span class="hero-title-line">灯亮前，</span>
          <span class="hero-title-line hero-title-accent">先进入状态。</span>
        </h1>
        <p class="hero-sub fade-up fade-up-delay-2">
          把演出前两周变成倒计时、歌单预习和路线提醒。
          让你到场时已经是那场演出的人，而不是刚刚想起来的那个。
        </p>
        <div class="hero-cta-group fade-up fade-up-delay-3">
          <button class="btn btn-primary" data-scroll="#join" id="hero-cta-main">
            加入内测名单
          </button>
          <button class="btn btn-ghost" data-scroll="#experience" id="hero-cta-try">
            先体验一下
          </button>
        </div>
        <div class="hero-social-proof fade-up fade-up-delay-4">
          <div class="proof-avatars" aria-hidden="true">
            <div class="proof-avatar" style="background:#e86c4a">音</div>
            <div class="proof-avatar" style="background:#b05bff">乐</div>
            <div class="proof-avatar" style="background:#1db954">节</div>
            <div class="proof-avatar" style="background:#f0bd72">客</div>
          </div>
          <span>正在招募内测用户</span>
        </div>
      </div>
    </section>
  `;
}

// ── Experience ───────────────────────────────────────
function renderExperience() {
  return `
    <section id="experience" aria-labelledby="experience-title">
      <div class="section">
        <p class="section-label">产品预览</p>
        <h2 class="section-title" id="experience-title">
          演出前的每一天，<br>都有它该做的事。
        </h2>
        <p class="section-desc">
          用真实数据感受产品。下面是四个核心功能的可交互预览，点一点，感受一下。
        </p>

        <div class="showcase-tabs" role="tablist" aria-label="功能切换">
          <button
            class="btn-pill ${state.tab === "countdown" ? "active" : ""}"
            role="tab"
            aria-selected="${state.tab === "countdown"}"
            data-tab="countdown"
            id="tab-countdown"
          >⏱ 倒计时</button>
          <button
            class="btn-pill ${state.tab === "setlist" ? "active" : ""}"
            role="tab"
            aria-selected="${state.tab === "setlist"}"
            data-tab="setlist"
            id="tab-setlist"
          >🎵 歌单预习</button>
          <button
            class="btn-pill ${state.tab === "video" ? "active" : ""}"
            role="tab"
            aria-selected="${state.tab === "video"}"
            data-tab="video"
            id="tab-video"
          >🎬 现场视频</button>
          <button
            class="btn-pill ${state.tab === "traffic" ? "active" : ""}"
            role="tab"
            aria-selected="${state.tab === "traffic"}"
            data-tab="traffic"
            id="tab-traffic"
          >🚇 交通方案</button>
        </div>

        ${
          state.tab === "countdown" ? renderCountdownDemo() :
          state.tab === "setlist"   ? renderSetlistDemo()   :
          state.tab === "video"     ? renderVideoDemo()     :
          renderTrafficDemo()
        }
      </div>
    </section>
  `;
}

function renderCountdownDemo() {
  const show = selectedShow();
  const days = daysUntil(show.date);

  let rightPanel;
  if (show.type === "festival") rightPanel = renderFestivalCountdownRight(show);
  else if (show.type === "live") rightPanel = renderLiveCountdownRight(show);
  else rightPanel = renderConcertCountdownRight(show);

  return `
    <div class="countdown-card" style="--show-accent: ${esc(show.accent)}">
      <div class="countdown-top">
        <span style="font-size:14px; font-weight:700; color:var(--text-soft)">我的演出</span>
        <div class="show-select-chips" role="group" aria-label="选择演出">
          ${shows.map((s) => `
            <button
              class="btn-pill ${s.id === show.id ? "active" : ""}"
              data-show-id="${s.id}"
              aria-pressed="${s.id === show.id}"
              id="show-${s.id}"
            >
              <span class="show-type-dot show-type-${s.type}"></span>
              ${esc(s.label)} · ${esc(s.artist)}
            </button>
          `).join("")}
        </div>
      </div>
      <div class="countdown-main-area">
        <div class="countdown-left">
          <div class="countdown-glow"></div>
          <p class="countdown-days-label">距离开场</p>
          <span class="countdown-days-number" aria-label="${days} 天">${days}</span>
          <span class="countdown-days-unit">天</span>
        </div>
        ${rightPanel}
      </div>
    </div>
  `;
}

function renderConcertCountdownRight(show) {
  return `
    <div class="countdown-right">
      <div>
        <h3 class="countdown-artist">${esc(show.artist)} · ${esc(show.venue)}</h3>
        <p class="countdown-meta">${formatDate(show.date)}</p>
        <div class="countdown-suggestion">
          <p class="suggestion-label">今天的准备</p>
          <p class="suggestion-text">先听一遍<strong>《${esc(show.song)}》</strong>现场版，让身体记得这场演出的节奏。</p>
        </div>
      </div>
      <button class="btn btn-primary" data-fake-action="save_countdown" id="btn-save-countdown">
        保存到我的演出
      </button>
    </div>
  `;
}

function renderLiveCountdownRight(show) {
  const info = show.liveInfo || {};
  return `
    <div class="countdown-right">
      <div>
        <h3 class="countdown-artist">${esc(show.artist)} · ${esc(show.venue)}</h3>
        <p class="countdown-meta">${formatDate(show.date)}</p>
        <div class="live-info-card">
          <p class="live-info-label">小场尺度</p>
          <div class="live-info-rows">
            ${info.capacity ? `<div class="live-info-row"><span>📍</span><span>${esc(info.capacity)}</span></div>` : ""}
            ${info.vibe     ? `<div class="live-info-row"><span>🎧</span><span>${esc(info.vibe)}</span></div>` : ""}
            ${info.seating  ? `<div class="live-info-row"><span>🧍</span><span>${esc(info.seating)}</span></div>` : ""}
          </div>
        </div>
      </div>
      <button class="btn btn-primary" data-fake-action="save_countdown" id="btn-save-countdown">
        保存到我的演出
      </button>
    </div>
  `;
}

function renderFestivalCountdownRight(show) {
  const artists = show.artists || [];
  return `
    <div class="countdown-right festival-right">
      <div>
        <h3 class="countdown-artist">${esc(show.artist)} · ${esc(show.venue)}</h3>
        <p class="countdown-meta">${formatDate(show.date)}</p>
      </div>
      <div class="festival-artist-list" role="list" aria-label="艺人阵容">
        ${artists.map((a) => {
          const wished = state.festivalWishlist[a.id];
          return `
            <div class="festival-artist-row${wished ? " wished" : ""}" role="listitem">
              <div class="festival-artist-info">
                <span class="festival-slot">${esc(a.slot)}</span>
                <span class="festival-stage">${esc(a.stage)}</span>
                <span class="festival-name">${esc(a.name)}</span>
              </div>
              <button
                class="festival-wish-btn${wished ? " active" : ""}"
                data-festival-artist="${a.id}"
                aria-pressed="${wished ? "true" : "false"}"
                aria-label="${esc(a.name)} 想看"
              >${wished ? "♥ 想看" : "♡ 想看"}</button>
            </div>
          `;
        }).join("")}
      </div>
      <button class="btn btn-primary" data-fake-action="save_countdown" id="btn-save-countdown">
        保存阵容计划
      </button>
    </div>
  `;
}

function renderSetlistDemo() {
  return `
    <div class="setlist-card">
      <div class="setlist-header">
        <span class="setlist-ai-badge">✦ AI 预测</span>
        <span class="setlist-title">五月天 · 预测歌单</span>
      </div>
      <div class="setlist-body" role="list" aria-label="歌单列表">
        ${state.songs.map((song, i) => `
          <div class="song-row ${song.status === "移除" ? "muted" : ""}" role="listitem">
            <span class="song-num">${String(i + 1).padStart(2, "0")}</span>
            <div class="song-info">
              <p class="song-name">${esc(song.title)}</p>
              <p class="song-meta">${esc(song.status)} · ${song.weight}% 概率</p>
            </div>
            <div class="song-weight-bar" aria-hidden="true">
              <div class="song-weight-fill" style="width:${song.weight}%"></div>
            </div>
            <div class="song-actions-row" aria-label="${esc(song.title)} 操作">
              <button class="song-action-btn" data-song-action="likely" data-song-id="${song.id}">会唱</button>
              <button class="song-action-btn" data-song-action="priority" data-song-id="${song.id}">重点</button>
              <button class="song-action-btn" data-song-action="heard" data-song-id="${song.id}">听过</button>
              <button class="song-action-btn" data-song-action="remove" data-song-id="${song.id}">移除</button>
            </div>
          </div>
        `).join("")}
      </div>
    </div>
  `;
}

// ── Video Demo ───────────────────────────────────────
function renderVideoDemo() {
  const show = selectedShow();
  const videos = show.videos || [];
  const idx = Math.min(state.activeVideoIdx, videos.length - 1);
  const active = videos[idx];

  if (!active) return `<p style="color:var(--text-faint); padding:40px 0;">暂无视频数据。</p>`;

  const bilibiliSrc = `https://player.bilibili.com/player.html?bvid=${active.bvid}&page=1&high_quality=1&danmaku=0&autoplay=0`;

  return `
    <div class="video-demo-card">
      <div class="video-demo-top">
        <div class="video-artist-info">
          <span class="video-artist-name">${esc(show.artist)}</span>
          <span class="video-artist-label">最佳现场</span>
        </div>
        <div class="video-selector" role="group" aria-label="选择视频">
          ${videos.map((v, i) => `
            <button
              class="btn-pill ${i === idx ? "active" : ""}"
              data-video-idx="${i}"
              aria-pressed="${i === idx}"
              id="video-btn-${i}"
            >${esc(v.title)}</button>
          `).join("")}
        </div>
      </div>
      <div class="video-frame-wrap">
        <iframe
          class="video-iframe"
          src="${bilibiliSrc}"
          title="${esc(active.title)}"
          frameborder="0"
          allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
          allowfullscreen
          loading="lazy"
        ></iframe>
      </div>
      <div class="video-meta">
        <div class="video-meta-left">
          <p class="video-meta-title">${esc(active.title)}</p>
          <p class="video-meta-desc">${esc(active.desc)}</p>
        </div>
        <a
          class="btn btn-ghost btn-sm video-bili-link"
          href="https://www.bilibili.com/video/${active.bvid}"
          target="_blank"
          rel="noopener noreferrer"
          id="video-bili-link"
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
            <path d="M17.813 4.653h.854c1.51.054 2.769.578 3.773 1.574 1.004.995 1.524 2.249 1.56 3.76v7.36c-.036 1.51-.556 2.769-1.56 3.773s-2.262 1.524-3.773 1.56H5.333c-1.51-.036-2.769-.556-3.773-1.56S.036 18.858 0 17.347v-7.36c.036-1.511.556-2.765 1.56-3.76 1.004-.996 2.262-1.52 3.773-1.574h.774l-1.174-1.12a1.234 1.234 0 0 1-.373-.906c0-.356.124-.658.373-.907l.027-.027c.267-.249.573-.373.92-.373.347 0 .653.124.92.373L9.653 4.44c.071.071.134.142.187.213h4.267a.836.836 0 0 1 .16-.213l2.853-2.747c.267-.249.573-.373.92-.373.347 0 .662.124.929.373.267.249.391.551.391.907 0 .355-.124.657-.373.906zM5.333 7.24c-.746.018-1.373.276-1.88.773-.506.498-.769 1.13-.787 1.894v7.52c.018.764.281 1.396.787 1.893.507.498 1.134.756 1.88.773h13.334c.746-.017 1.373-.275 1.88-.773.506-.497.769-1.129.786-1.893v-7.52c-.017-.764-.28-1.396-.786-1.894-.507-.497-1.134-.755-1.88-.773zM8 11.107c.373 0 .684.124.933.373.25.249.383.569.4.96v1.173c-.017.391-.15.711-.4.96-.249.25-.56.374-.933.374s-.684-.125-.933-.374c-.25-.249-.383-.569-.4-.96V12.44c0-.373.129-.689.386-.947.258-.257.574-.386.947-.386zm8 0c.373 0 .684.124.933.373.25.249.383.569.4.96v1.173c-.017.391-.15.711-.4.96-.249.25-.56.374-.933.374s-.684-.125-.933-.374c-.25-.249-.383-.569-.4-.96V12.44c.017-.391.15-.711.4-.96.249-.249.56-.373.933-.373z"/>
          </svg>
          在 B 站看
        </a>
      </div>
    </div>
  `;
}

// ── Traffic Demo ──────────────────────────────────────
function renderTrafficDemo() {
  const show = selectedShow();
  const t = show.traffic;

  if (!t) return `<p style="color:var(--text-faint); padding:40px 0;">暂无交通数据。</p>`;

  const goCard = `
    <div class="traffic-card traffic-card-go">
      <div class="traffic-card-head">
        <span class="traffic-card-icon">🚀</span>
        <div>
          <p class="traffic-card-label">去程</p>
          <p class="traffic-card-subtitle">${esc(show.venue)}</p>
        </div>
      </div>
      <div class="traffic-rows">
        <div class="traffic-row">
          <span class="traffic-row-icon traffic-metro">🚇</span>
          <div class="traffic-row-body">
            <p class="traffic-row-label">地铁</p>
            <p class="traffic-row-text">${esc(t.go.metro)}</p>
          </div>
        </div>
        <div class="traffic-row">
          <span class="traffic-row-icon traffic-taxi">🚕</span>
          <div class="traffic-row-body">
            <p class="traffic-row-label">打车</p>
            <p class="traffic-row-text">${esc(t.go.taxi)}</p>
          </div>
        </div>
        <div class="traffic-row">
          <span class="traffic-row-icon traffic-walk">🚶</span>
          <div class="traffic-row-body">
            <p class="traffic-row-label">步行</p>
            <p class="traffic-row-text">${esc(t.go.walk)}</p>
          </div>
        </div>
        <div class="traffic-row traffic-row-entry">
          <span class="traffic-row-icon">🚪</span>
          <div class="traffic-row-body">
            <p class="traffic-row-label">入场口</p>
            <p class="traffic-row-text">${esc(t.go.entry)}</p>
          </div>
        </div>
      </div>
    </div>
  `;

  const backCard = `
    <div class="traffic-card traffic-card-back">
      <div class="traffic-card-head">
        <span class="traffic-card-icon">🌙</span>
        <div>
          <p class="traffic-card-label">回程</p>
          <p class="traffic-card-subtitle">散场之后</p>
        </div>
      </div>
      <div class="traffic-rows">
        <div class="traffic-row">
          <span class="traffic-row-icon traffic-metro">🚇</span>
          <div class="traffic-row-body">
            <p class="traffic-row-label">地铁</p>
            <p class="traffic-row-text">${esc(t.back.metro)}</p>
          </div>
        </div>
        <div class="traffic-row">
          <span class="traffic-row-icon traffic-taxi">🚕</span>
          <div class="traffic-row-body">
            <p class="traffic-row-label">打车</p>
            <p class="traffic-row-text">${esc(t.back.taxi)}</p>
          </div>
        </div>
        <div class="traffic-row">
          <span class="traffic-row-icon traffic-walk">🚶</span>
          <div class="traffic-row-body">
            <p class="traffic-row-label">步行</p>
            <p class="traffic-row-text">${esc(t.back.walk)}</p>
          </div>
        </div>
        <div class="traffic-row traffic-row-tip">
          <span class="traffic-row-icon">💡</span>
          <div class="traffic-row-body">
            <p class="traffic-row-label">散场建议</p>
            <p class="traffic-row-text">${esc(t.back.tip)}</p>
          </div>
        </div>
      </div>
    </div>
  `;

  return `
    <div class="traffic-demo">
      <div class="traffic-alert" role="note">
        <span class="traffic-alert-icon">⏰</span>
        <span>${esc(t.alert)}</span>
      </div>
      <div class="traffic-grid">
        ${goCard}
        ${backCard}
      </div>
      <p class="traffic-footnote">以上为静态预估数据。上线后接入实时路况、地铁延误和打车等待时间。</p>
    </div>
  `;
}

// ── How ──────────────────────────────────────────────
function renderHow() {
  const steps = [
    {
      icon: "🎫",
      num: "01",
      title: "绑定你的演出",
      desc: "告诉开场前你要去哪场，它就开始倒计时——每天给你一个小任务。",
      color: "var(--accent)",
    },
    {
      icon: "🎵",
      num: "02",
      title: "AI 先给歌单，你来修正",
      desc: "根据历史演出预测歌单，你把不熟的歌标出来，它帮你排优先级。",
      color: "var(--accent-purple)",
    },
    {
      icon: "🗺️",
      num: "03",
      title: "到场前，路都想好了",
      desc: "几点出发、从哪个门进、散场去哪等车——全部提前安排好，不用现场慌。",
      color: "var(--accent-warm)",
    },
  ];
  return `
    <section aria-labelledby="how-title">
      <div class="section">
        <p class="section-label">工作原理</p>
        <h2 class="section-title" id="how-title">从买票到入场，<br>一直陪着你。</h2>
        <div class="how-grid">
          ${steps.map((step) => `
            <div class="how-card" style="--line-color: ${step.color}">
              <div class="how-icon" style="background: rgba(255,255,255,0.06); border-color: var(--border);">
                ${step.icon}
              </div>
              <p class="how-num">${step.num}</p>
              <h3 class="how-title">${step.title}</h3>
              <p class="how-desc">${step.desc}</p>
            </div>
          `).join("")}
        </div>
      </div>
    </section>
  `;
}

// ── Join / Waitlist ───────────────────────────────────
function renderJoin() {
  return `
    <section id="join" aria-labelledby="join-title">
      <div class="join-inner">
        <p class="section-label" style="justify-content:center">加入内测</p>
        <h2 class="join-title" id="join-title">
          有一场真的要去看的演出？
        </h2>
        <p class="join-sub">
          留下你的联系方式，内测开放后第一时间通知你。<br>
          我们会在演出前帮你做好所有准备。
        </p>
        ${state.submitted ? renderSuccessState() : renderWaitlistForm()}
      </div>
    </section>
  `;
}

function renderSuccessState() {
  return `
    <div class="waitlist-form success-state">
      <div class="success-icon" aria-hidden="true">✓</div>
      <h3 class="success-title">已加入内测名单</h3>
      <p class="success-desc">我们会在内测开放时第一时间联系你。<br>那场演出，到时候我们一起准备。</p>
    </div>
  `;
}

function renderWaitlistForm() {
  const emailError = state.formErrors.email;
  const showError = state.formErrors.show;
  return `
    <form class="waitlist-form" novalidate aria-labelledby="join-title" id="waitlist-form">
      <div class="form-row">
        <label class="form-label" for="field-email">邮箱 <span aria-hidden="true">*</span></label>
        <input
          id="field-email"
          class="form-input ${emailError ? "error" : ""}"
          name="email"
          type="email"
          placeholder="your@email.com"
          autocomplete="email"
          aria-required="true"
          aria-describedby="email-hint ${emailError ? "email-error" : ""}"
        />
        ${emailError ? `<span id="email-error" class="form-error" role="alert">${esc(emailError)}</span>` : ""}
        <span id="email-hint" class="form-hint">内测邀请将发到这里</span>
      </div>
      <div class="form-row">
        <label class="form-label" for="field-show">最近要看的演出 <span aria-hidden="true">*</span></label>
        <input
          id="field-show"
          class="form-input ${showError ? "error" : ""}"
          name="show"
          type="text"
          placeholder="例：五月天上海、草莓音乐节"
          aria-required="true"
          aria-describedby="${showError ? "show-error" : ""}"
        />
        ${showError ? `<span id="show-error" class="form-error" role="alert">${esc(showError)}</span>` : ""}
      </div>
      <button class="btn btn-primary form-submit" type="submit" id="btn-join-submit" ${state.submitting ? "disabled" : ""}>
        ${state.submitting ? "提交中…" : "加入内测名单 →"}
      </button>
      <p class="form-footnote">
        不会发垃圾邮件。只在内测开放时联系你。
      </p>
    </form>
  `;
}

// ── Footer ───────────────────────────────────────────
function renderFooter() {
  return `
    <footer class="footer">
      <span>开场前 · BeforeShow</span>
      <span>专为演出观众，做演出前那两周。</span>
    </footer>
  `;
}

// ── Event Handlers ───────────────────────────────────
function setToast(msg) {
  state.toast = msg;
  render();
  clearTimeout(setToast._t);
  setToast._t = setTimeout(() => {
    state.toast = "";
    render();
  }, 2800);
}

function handleSongAction(songId, action) {
  const labels = { likely: "很可能会唱", priority: "重点预习", heard: "已经听过", remove: "移除" };
  state.songs = state.songs.map((s) =>
    s.id === songId
      ? { ...s, status: labels[action] || s.status, weight: Math.min(99, s.weight + 3) }
      : s,
  );
  if (action === "priority") {
    const target = state.songs.find((s) => s.id === songId);
    state.songs = [target, ...state.songs.filter((s) => s.id !== songId)];
  }
  writeJson("songs", state.songs);
  track("song_action", { songId, action });
  setToast("歌单已更新。");
}

function saveLeadLocally(lead) {
  try {
    const raw = localStorage.getItem(STORAGE_LEADS);
    const leads = raw ? JSON.parse(raw) : [];
    leads.push(lead);
    localStorage.setItem(STORAGE_LEADS, JSON.stringify(leads));
  } catch {}
}

async function submitForm(form) {
  const data = new FormData(form);
  const email = String(data.get("email") || "").trim();
  const show = String(data.get("show") || "").trim();
  const errors = {};
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) errors.email = "请填一个有效邮箱。";
  if (!show) errors.show = "请写一场你要去看的演出。";
  state.formErrors = errors;
  if (Object.keys(errors).length) {
    render();
    return;
  }

  const lead = {
    id: `l_${Date.now()}`,
    at: new Date().toISOString(),
    email,
    show,
    session: getSessionId(),
  };

  state.submitting = true;
  render();

  let synced = false;
  try {
    await submitLeadToFeishu({
      email: lead.email,
      show: lead.show,
      session: lead.session,
      submitted_at: lead.at,
      source: "fake-door",
    });
    synced = true;
  } catch (err) {
    saveLeadLocally({ ...lead, syncError: err instanceof Error ? err.message : "unknown" });
    track("lead_submit_fallback", { show, error: err instanceof Error ? err.message : "unknown" });
    setToast("已本地保存，但同步飞书失败，请检查网络或配置。");
  }

  if (synced) {
    saveLeadLocally({ ...lead, synced: true });
    track("lead_submit", { show, synced: true });
  } else {
    track("lead_submit", { show, synced: false });
  }

  state.submitting = false;
  state.submitted = true;
  state.formErrors = {};
  render();
  document.getElementById("join")?.scrollIntoView({ behavior: "smooth", block: "center" });
}

// ── Event Delegation ─────────────────────────────────
document.addEventListener("click", (e) => {
  // Close-modal backdrop
  const btn = e.target.closest("button, a");

  // Scroll to section
  const scrollTarget = btn?.getAttribute("data-scroll");
  if (scrollTarget) {
    e.preventDefault();
    track("nav_click", { target: scrollTarget });
    render();
    setTimeout(() => {
      document.querySelector(scrollTarget)?.scrollIntoView({ behavior: "smooth", block: "start" });
    }, 0);
    return;
  }

  // Tab switch
  const tab = btn?.getAttribute("data-tab");
  if (tab) {
    state.tab = tab;
    track("tab_switch", { tab });
    render();
    return;
  }

  // Show selector
  const showId = btn?.getAttribute("data-show-id");
  if (showId) {
    state.activeShowId = showId;
    state.activeVideoIdx = 0;  // reset video selection on show change
    track("show_switch", { showId });
    render();
    return;
  }

  // Video index selector
  const videoIdx = btn?.getAttribute("data-video-idx");
  if (videoIdx !== null && videoIdx !== undefined) {
    state.activeVideoIdx = Number(videoIdx);
    track("video_switch", { idx: Number(videoIdx), showId: state.activeShowId });
    render();
    return;
  }

  // Fake action (save countdown)
  const fakeAction = btn?.getAttribute("data-fake-action");
  if (fakeAction === "save_countdown") {
    track("save_countdown", { showId: state.activeShowId });
    const show = selectedShow();
    const msg = show.type === "festival" ? "阵容计划已保存。" : "已保存到你的演出。内测开放后会真正提醒你。";
    setToast(msg);
    return;
  }

  // Festival artist wish toggle
  const festivalArtist = btn?.getAttribute("data-festival-artist");
  if (festivalArtist) {
    const was = state.festivalWishlist[festivalArtist];
    state.festivalWishlist = { ...state.festivalWishlist, [festivalArtist]: !was };
    writeJson("festivalWishlist", state.festivalWishlist);
    track("festival_wish", { artistId: festivalArtist, wished: !was });
    const show = selectedShow();
    const artist = show.artists?.find((a) => a.id === festivalArtist);
    setToast(was ? `已取消：${artist?.name || ""}` : `已标记想看：${artist?.name || ""} ♥`);
    return;
  }

  // Song action
  const songAction = btn?.getAttribute("data-song-action");
  if (songAction) {
    handleSongAction(btn.getAttribute("data-song-id"), songAction);
    return;
  }
});

document.addEventListener("submit", (e) => {
  if (!e.target.matches("#waitlist-form")) return;
  e.preventDefault();
  void submitForm(e.target);
});

document.addEventListener("keydown", (e) => {
  // Future modal trap
});

// ── Boot ─────────────────────────────────────────────
track("page_view", { ref: document.referrer || "direct" });
render();
