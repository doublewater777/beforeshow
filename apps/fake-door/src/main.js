import "./styles.css";

// ── Data ────────────────────────────────────────────
const STORAGE_EVENTS = "beforeshow.events.v2";
const STORAGE_SESSION = "beforeshow.session.v2";

const shows = [
  {
    id: "jay",
    type: "concert",
    label: "演唱会",
    artist: "周杰伦",
    venue: "南京奥体中心体育场",
    date: "2026-09-24T19:30:00+08:00",
    accent: "#84BFFF",
    song: "晴天",
  },
];

const useFlowSteps = [
  {
    title: "放入下一场",
    desc: "粘贴票务链接、上传截图，或手动添加。把下一场先落到本地。",
  },
  {
    title: "准备开场",
    desc: "看现场倒计时，收好票根和时刻表，出门前把关键信息准备齐。",
  },
  {
    title: "留下现场记录",
    desc: "散场后把现场记录留在本地，之后还能回头翻看这一场。",
  },
];

const audienceItems = [
  "适合需要现场准备的人",
  "适合想把票根、时刻表留在本地的人",
  "适合演唱会、Livehouse、音乐节",
];

// ── State ────────────────────────────────────────────
const state = {
  activeShowId: "jay",
  toast: "",
  ambientMode: false,
};

// ── Storage helpers ──────────────────────────────────
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
        <img class="nav-logo-mark" src="/app-icon.png" alt="开场前 BeforeShow 图标" width="32" height="32" />
        <span class="nav-brand">开场前</span>
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
          现场准备 · 本地记录
        </div>
        <h1 id="hero-title" class="hero-title fade-up fade-up-delay-1">
          <span class="hero-title-line">现场准备与</span>
          <span class="hero-title-line hero-title-accent">本地记录工具。</span>
        </h1>
        <p class="hero-sub fade-up fade-up-delay-2">
          开场前 BeforeShow 用于现场准备与本地记录，
          提供现场倒计时、记录票根、记录时刻表、现场记录等功能。
        </p>
        <div class="hero-feature-list fade-up fade-up-delay-2" aria-label="BeforeShow 可做的事">
          <span>现场倒计时</span>
          <span>记录票根</span>
          <span>记录时刻表</span>
          <span>现场记录</span>
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
          从准备开场，<br>到留下这场记录。
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
          给需要把现场准备好，<br>也想把记录留在本地的人。
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
          先把下一场放进来，<br>再把准备做齐。
        </h2>
        <p class="section-desc">
          现场倒计时帮你盯住开场时间；
          票根、时刻表和现场记录都留在本地。
        </p>

        <div class="feature-modules" aria-label="BeforeShow 核心体验">
          ${renderFeatureModule("01", "现场倒计时", "把下一场放进来，每天知道离开场还有多久。", renderCountdownDemo())}
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
  if (show.id === "jay") bgImg = "https://img.alicdn.com/bao/uploaded/https://img.alicdn.com/imgextra/i2/2251059038/O1CN01nWPQm82GdSnG5tWAW_!!2251059038.jpg_q60.jpg_.webp";

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

// ── Footer ───────────────────────────────────────────
function renderFooter() {
  return `
    <footer class="footer">
      <span>开场前 · BeforeShow</span>
      <span>现场准备与本地记录工具。</span>
      <nav class="footer-links" aria-label="页脚链接">
        <a class="footer-link" href="https://beian.miit.gov.cn/" target="_blank" rel="noopener noreferrer">浙ICP备2026041359号-2</a>
        <a class="footer-link" href="/privacy/">隐私政策</a>
        <a class="footer-link" href="/terms/">用户协议</a>
        <a class="footer-link" href="/link-guide/">如何获取票务链接</a>
      </nav>
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

  // Fake action (save countdown)
  const fakeAction = btn?.getAttribute("data-fake-action");
  if (fakeAction === "save_countdown") {
    track("save_countdown", { showId: state.activeShowId });
    setToast("已放进你的开场前。");
    return;
  }

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
