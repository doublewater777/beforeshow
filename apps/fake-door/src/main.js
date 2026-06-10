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
    songs: [
      { id: "s1", title: "突然好想你", weight: 95, status: "很可能会唱" },
      { id: "s2", title: "派对动物",   weight: 86, status: "重点预测" },
      { id: "s3", title: "知足",       weight: 81, status: "已经听过" },
      { id: "s4", title: "爱情万岁",   weight: 73, status: "待判断" },
      { id: "s5", title: "终结孤单",   weight: 68, status: "待判断" },
      { id: "s6", title: "而我知道",   weight: 59, status: "待判断" },
    ],
  },
];

const useFlowSteps = [
  {
    title: "导入你的演出",
    desc: "粘贴票务信息、上传截图，或手动添加。演唱会、Livehouse、音乐节都可以。",
  },
  {
    title: "选中这一场",
    desc: "如果你有不止一场演出，开场前会帮你聚焦当前最想期待的那一场。",
  },
  {
    title: "两周慢慢预习",
    desc: "每天一首歌，一段现场视频，一点点靠近灯光亮起的瞬间。",
  },
  {
    title: "当天只留必要工具",
    desc: "歌单参考、场馆提示、音乐节装备、离场攻略，都在你需要的时候出现。",
  },
  {
    title: "演后，把这场收起来",
    desc: "留下一句话、几张照片、一张情绪卡片，把余音保存下来。",
  },
];

const audienceItems = [
  "适合已经买票、正在等开场的人",
  "适合演唱会、Livehouse、音乐节",
  "适合想提前熟悉歌单和现场氛围的人",
];

// ── Helpers ────────────────────────────────────────────
function defaultSongsFor(showId) {
  return shows.find((s) => s.id === showId)?.songs || [];
}

function buildSongsMap(saved) {
  // Merge saved per-show customizations over defaults
  const map = {};
  for (const show of shows) {
    map[show.id] = saved?.[show.id] && Array.isArray(saved[show.id])
      ? saved[show.id]
      : [...show.songs];
  }
  return map;
}

function currentSongs() {
  return state.songs[state.activeShowId] || [];
}

// ── State ────────────────────────────────────────────
const state = {
  activeVideoIdx: 0,
  activeShowId: "mayday",
  songs: buildSongsMap(readJson("songs", null)),
  formErrors: {},
  submitting: false,
  submitted: false,
  toast: "",
  ambientMode: false,
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
  document.title = `开场前 BeforeShow`;
  app.innerHTML = `
    <a href="#main-content" class="skip-link">跳到主要内容</a>
    ${renderNav()}
    <main id="main-content">
      ${renderHero()}
      ${renderExperience()}
      ${renderUseFlow()}
      ${renderAudience()}
      ${renderJoin()}
    </main>
    ${renderFooter()}
    ${state.toast ? `<div class="toast" role="status">${esc(state.toast)}</div>` : ""}
    ${state.ambientMode ? renderAmbientModal() : ""}
  `;
}

// ── Nav ──────────────────────────────────────────────
function renderNav() {
  return `
    <nav class="site-nav" aria-label="主导航">
      <div class="nav-logo">
        <div class="nav-logo-mark" aria-hidden="true">
          <svg viewBox="0 0 18 18" xmlns="http://www.w3.org/2000/svg" role="img" aria-labelledby="logo-title">
            <title id="logo-title">开场前 BeforeShow</title>
            <path d="M9 2.2C9 2.2 4.4 4.9 4.4 10a4.6 4.6 0 0 0 9.2 0C13.6 4.9 9 2.2 9 2.2Z"/>
            <circle cx="9" cy="10" r="2.1" fill="var(--accent)"/>
            <path d="M9 5.2 10.45 9H7.55L9 5.2Z" fill="currentColor"/>
            <circle cx="9" cy="10" r=".5" fill="currentColor"/>
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
          距开场还有一段日子
        </div>
        <h1 id="hero-title" class="hero-title fade-up fade-up-delay-1">
          <span class="hero-title-line">下一场演出，</span>
          <span class="hero-title-line hero-title-accent">提前进入状态。</span>
        </h1>
        <p class="hero-sub fade-up fade-up-delay-2">
          输入你要看的演出，BeforeShow 会生成一份开场前 14 天预习清单：
          倒数提醒、AI 预测歌单、现场视频和出行方案等功能。
        </p>
        <div class="hero-feature-list fade-up fade-up-delay-2" aria-label="BeforeShow 可做的事">
          <span>倒数提醒</span>
          <span>AI 预测歌单</span>
          <span>现场视频</span>
          <span>出行方案</span>
        </div>
        <div class="hero-cta-group fade-up fade-up-delay-3">
          <button class="btn btn-primary" data-scroll="#join" id="hero-cta-main">
            加入内测
          </button>
          <button class="btn btn-ghost" data-scroll="#experience" id="hero-cta-try">
            感受一下
          </button>
        </div>
        <div class="hero-social-proof fade-up fade-up-delay-4">
          <div class="proof-avatars" aria-hidden="true">
            <div class="proof-avatar" style="background:#e86c4a">音</div>
            <div class="proof-avatar" style="background:#b05bff">乐</div>
            <div class="proof-avatar" style="background:#1db954">节</div>
            <div class="proof-avatar" style="background:#f0bd72">客</div>
          </div>
          <span>已经有买到票的人在等开场了</span>
        </div>
      </div>
    </section>
  `;
}

// ── Use Flow ─────────────────────────────────────────
function renderUseFlow() {
  return `
    <section id="use-flow" class="use-flow" aria-labelledby="use-flow-title">
      <div class="section">
        <p class="section-label">使用流程</p>
        <h2 class="section-title" id="use-flow-title">
          买到票之后，<br>真正的现场就已经开始了。
        </h2>
        <div class="how-grid" aria-label="BeforeShow 使用流程">
          ${useFlowSteps.map((step, i) => `
            <article class="how-card" style="--line-color:${i === 4 ? "var(--accent-purple)" : i === 3 ? "var(--accent-warm)" : "var(--accent)"}">
              <p class="how-num">${String(i + 1).padStart(2, "0")}</p>
              <h3 class="how-title">${esc(step.title)}</h3>
              <p class="how-desc">${esc(step.desc)}</p>
            </article>
          `).join("")}
        </div>
      </div>
    </section>
  `;
}

// ── Audience ─────────────────────────────────────────
function renderAudience() {
  return `
    <section id="audience" class="audience" aria-labelledby="audience-title">
      <div class="section">
        <p class="section-label">适合谁</p>
        <h2 class="section-title" id="audience-title">
          给那些已经有一张票，<br>也有一段期待的人。
        </h2>
        <div class="audience-list" aria-label="BeforeShow 适合的人群">
          ${audienceItems.map((item) => `
            <article class="audience-item">
              <span class="audience-check" aria-hidden="true">✓</span>
              <h3 class="audience-text">${esc(item)}</h3>
            </article>
          `).join("")}
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
        <p class="section-label">开场前两周</p>
        <h2 class="section-title" id="experience-title">
          演出越接近开始，<br>越值得期待。
        </h2>
        <p class="section-desc">
          倒数、预测歌单、现场视频，帮你在开场前一点点沉浸进那场演出；
          出行方案让你到了当天也能从容不迫。
        </p>

        <div class="feature-modules" aria-label="BeforeShow 四个模块">
          ${renderFeatureModule("01", "倒数提醒", "把五月天上海演唱会放进来，每天知道离开场还有多久。", renderCountdownDemo())}
          ${renderFeatureModule("02", "AI 预测歌单", "预测可能会唱的曲目，并导入网易云音乐或 QQ 音乐提前听。", renderSetlistDemo())}
          ${renderFeatureModule("03", "现场回顾", "提前看几段代表现场，把舞台、合唱和情绪找回来。", renderVideoDemo())}
          ${renderFeatureModule("04", "出行方案", "提前看好去程、入场口和散场交通，演出当天从容不迫。", renderTrafficDemo())}
        </div>
      </div>
    </section>
  `;
}

function renderFeatureModule(num, title, desc, body) {
  return `
    <article class="feature-module">
      <div class="feature-module-head">
        <span class="feature-module-num">${num}</span>
        <div>
          <h3 class="feature-module-title">${esc(title)}</h3>
          <p class="feature-module-desc">${esc(desc)}</p>
        </div>
      </div>
      ${body}
    </article>
  `;
}

function renderCountdownDemo() {
  const show = selectedShow();
  const days = daysUntil(show.date);

  return `
    <div class="countdown-card" style="--show-accent: ${esc(show.accent)}">
      <div class="countdown-top">
        <span style="font-size:14px; font-weight:700; color:var(--text-soft)">我的下一场</span>
        <span class="single-show-chip"><span class="show-type-dot show-type-${show.type}"></span>${esc(show.label)} · ${esc(show.artist)}</span>
      </div>
      <div class="countdown-main-area">
        <div class="countdown-left">
          <div class="countdown-glow"></div>
          <p class="countdown-days-label">距离开场</p>
          <span class="countdown-days-number" aria-label="${days} 天">${days}</span>
          <span class="countdown-days-unit">天</span>
          <button class="btn-ambient" id="btn-ambient-trigger" style="z-index: 2;">
            ✨ 现场前夕氛围
          </button>
        </div>
        ${renderConcertCountdownRight(show)}
      </div>
    </div>
  `;
}

// ── Ambient Modal ────────────────────────────────────
function renderAmbientModal() {
  const show = selectedShow();
  const days = daysUntil(show.date);
  let bgImg = "";
  if (show.id === "mayday") bgImg = "/concert-before-lights-3.png";

  return `
    <div class="ambient-modal" id="ambient-modal-overlay" style="--show-accent: ${esc(show.accent)}">
      <div class="ambient-modal-bg" style="background-image: url('${bgImg}')"></div>
      <div class="ambient-modal-overlay"></div>
      
      <button class="ambient-close-btn" id="ambient-close-btn" aria-label="关闭氛围模式">✕</button>
      
      <div class="ambient-container">
        <div class="ambient-header">
          <p class="ambient-venue-label">现场前夕 · ${esc(show.venue)}</p>
          <h2 class="ambient-show-artist">${esc(show.artist)}</h2>
        </div>
        
        <div class="ambient-glow-ring">
          <svg class="ambient-ring-svg" viewBox="0 0 100 100">
            <circle class="ambient-ring-bg" cx="50" cy="50" r="45"></circle>
            <circle class="ambient-ring-active" cx="50" cy="50" r="45" style="stroke-dasharray: 283; stroke-dashoffset: 60; stroke: ${esc(show.accent)}"></circle>
          </svg>
          <div class="ambient-countdown-content">
            <span class="ambient-countdown-days">${days}</span>
            <span class="ambient-countdown-unit">天</span>
          </div>
        </div>

        <div class="ambient-player">
          <div class="visualizer">
            <div class="bar bar-1"></div>
            <div class="bar bar-2"></div>
            <div class="bar bar-3"></div>
            <div class="bar bar-4"></div>
            <div class="bar bar-5"></div>
          </div>
          <div class="ambient-song-info">
            <span class="ambient-song-title">正在播放预演单曲：《${esc(show.song)}》</span>
            <span class="ambient-song-desc">感受这一刻，走到门口时，你已经在那场演出了。</span>
          </div>
        </div>
        
        <button class="btn btn-ghost" id="ambient-exit-trigger" style="margin-top: 32px; border-color: rgba(255,255,255,0.2); color: rgba(255,255,255,0.8);">
          返回网页
        </button>
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
          <p class="suggestion-label">今天先靠近一点</p>
          <p class="suggestion-text">先听一遍<strong>《${esc(show.song)}》</strong>现场版，让身体记得这场演出的节奏。</p>
        </div>
      </div>
      <button class="btn btn-primary" data-fake-action="save_countdown" id="btn-save-countdown">
        放进我的开场前
      </button>
    </div>
  `;
}

function renderSetlistDemo() {
  const show = selectedShow();
  const songs = currentSongs();
  return `
    <div class="setlist-card">
      <div class="setlist-header">
        <span class="setlist-ai-badge">✦ AI 预测</span>
        <span class="setlist-title">${esc(show.artist)} · 可能会唱这些歌</span>
      </div>
      <div class="setlist-body" role="list" aria-label="歌单列表">
        ${songs.map((song, i) => `
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
              <button class="song-action-btn ${song.status === "很可能会唱" ? "active" : ""}" data-song-action="likely" data-song-id="${song.id}">会唱</button>
              <button class="song-action-btn ${song.status === "重点预测" ? "active" : ""}" data-song-action="priority" data-song-id="${song.id}">重点</button>
              <button class="song-action-btn ${song.status === "已经听过" ? "active" : ""}" data-song-action="heard" data-song-id="${song.id}">听过</button>
              <button class="song-action-btn ${song.status === "移除" ? "active" : ""}" data-song-action="remove" data-song-id="${song.id}">移除</button>
            </div>
          </div>
        `).join("")}
      </div>
      <div class="setlist-imports" aria-label="导入预测歌单">
        <button class="music-import-btn music-import-netease" data-import-platform="netease">导入网易云音乐</button>
        <button class="music-import-btn music-import-qq" data-import-platform="qq">导入 QQ 音乐</button>
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
          <span class="video-artist-label">先看一眼现场</span>
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
      <p class="traffic-footnote">先知道怎么走，开场那天就少一点临时慌张。</p>
    </div>
  `;
}


// ── Join / Waitlist ───────────────────────────────────
function renderJoin() {
  return `
    <section id="join" aria-labelledby="join-title">
      <div class="join-inner">
        <p class="section-label" style="justify-content:center">加入内测</p>
        <h2 class="join-title" id="join-title">
          你下一场要走进哪里？
        </h2>
        <p class="join-sub">
          告诉我们你在等哪一场。<br>内测开放时，还在等开场的人会先收到邀请。
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
      <h3 class="success-title">下一场，帮你记住了</h3>
      <p class="success-desc">已经记下了。<br>内测一开放就告诉你——在那之前，这段日子我们陪你一起过。</p>
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
        <label class="form-label" for="field-show">下一场要看的演出 <span aria-hidden="true">*</span></label>
        <input
          id="field-show"
          class="form-input ${showError ? "error" : ""}"
          name="show"
          type="text"
          placeholder="例：五月天上海演唱会"
          aria-required="true"
          aria-describedby="${showError ? "show-error" : ""}"
        />
        ${showError ? `<span id="show-error" class="form-error" role="alert">${esc(showError)}</span>` : ""}
      </div>
      <button class="btn btn-primary form-submit" type="submit" id="btn-join-submit" ${state.submitting ? "disabled" : ""}>
        ${state.submitting ? "提交中…" : "存下我的下一场 →"}
      </button>
      <p class="form-footnote">
        不频繁打扰。只在开场前，提醒你那些值得期待的事。
      </p>
    </form>
  `;
}

// ── Footer ───────────────────────────────────────────
function renderFooter() {
  return `
    <footer class="footer">
      <span>开场前 · BeforeShow</span>
      <span>给买了票、正在等开场的人。</span>
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
  const labels = { likely: "很可能会唱", priority: "重点预测", heard: "已经听过", remove: "移除" };
  const showId = state.activeShowId;
  const list = [...(state.songs[showId] || [])];
  state.songs[showId] = list.map((s) =>
    s.id === songId
      ? { ...s, status: labels[action] || s.status, weight: Math.min(99, s.weight + 3) }
      : s,
  );
  if (action === "priority") {
    const target = state.songs[showId].find((s) => s.id === songId);
    state.songs[showId] = [target, ...state.songs[showId].filter((s) => s.id !== songId)];
  }
  writeJson("songs", state.songs);
  track("song_action", { songId, action, showId });
  setToast("预测歌单已更新。");
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
  // Ambient Trigger Enter
  if (e.target.closest("#btn-ambient-trigger")) {
    state.ambientMode = true;
    track("ambient_mode_enter", { showId: state.activeShowId });
    render();
    return;
  }

  // Ambient Trigger Exit
  if (e.target.closest("#ambient-close-btn") || e.target.closest("#ambient-exit-trigger") || e.target.id === "ambient-modal-overlay") {
    state.ambientMode = false;
    track("ambient_mode_exit", { showId: state.activeShowId });
    render();
    return;
  }

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
    setToast("已放进你的开场前。内测开放后会真正提醒你。");
    return;
  }

  const importPlatform = btn?.getAttribute("data-import-platform");
  if (importPlatform) {
    const platformName = importPlatform === "netease" ? "网易云音乐" : "QQ 音乐";
    track("setlist_import_click", { platform: importPlatform, showId: state.activeShowId });
    setToast(`内测开放后，可将 AI 预测歌单导入${platformName}。`);
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
  if (e.key === "Escape" && state.ambientMode) {
    state.ambientMode = false;
    track("ambient_mode_exit", { showId: state.activeShowId });
    render();
  }
});

// ── Boot ─────────────────────────────────────────────
track("page_view", { ref: document.referrer || "direct" });
render();
