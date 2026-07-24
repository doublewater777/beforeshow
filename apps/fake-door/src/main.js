import "./styles.css";

// ── Data ────────────────────────────────────────────
const STORAGE_LEADS = "beforeshow.leads.v2";
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
    title: "导入你的演出",
    desc: "粘贴票务信息、上传截图，或手动添加。演唱会、Livehouse、音乐节都可以。",
  },
  {
    title: "选中这一场",
    desc: "如果你有不止一场演出，开场前会帮你聚焦当前最想期待的那一场。",
  },
  {
    title: "每天看见倒数",
    desc: "离开场越来越近时，打开就知道还要等多久。",
  },
];

const audienceItems = [
  "适合已经买票、正在等开场的人",
  "适合演唱会、Livehouse、音乐节",
  "适合想把下一场放在心上的人",
];

// ── State ────────────────────────────────────────────
const state = {
  activeShowId: "jay",
  formErrors: {},
  submitting: false,
  submitted: false,
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
          倒数提醒、AI 预测歌单和出行方案等功能。
        </p>
        <div class="hero-feature-list fade-up fade-up-delay-2" aria-label="BeforeShow 可做的事">
          <span>倒数提醒</span>
          <span>AI 预测歌单</span>
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
          把下一场放进来，
          每次打开都能看见离灯光亮起还有多久。
        </p>

        <div class="feature-modules" aria-label="BeforeShow 核心体验">
          ${renderFeatureModule("01", "倒数提醒", "把五月天上海演唱会放进来，每天知道离开场还有多久。", renderCountdownDemo())}
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

  saveLeadLocally(lead);
  track("lead_submit", { show });

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

  // Fake action (save countdown)
  const fakeAction = btn?.getAttribute("data-fake-action");
  if (fakeAction === "save_countdown") {
    track("save_countdown", { showId: state.activeShowId });
    setToast("已放进你的开场前。内测开放后会真正提醒你。");
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
