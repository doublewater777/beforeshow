"use client";

import { useEffect, useRef, useState } from "react";

const STORAGE_EVENTS = "beforeshow.events.v2";
const STORAGE_SESSION = "beforeshow.session.v2";

const show = {
  id: "jay",
  type: "concert",
  label: "演唱会",
  artist: "周杰伦",
  venue: "南京奥体中心体育场",
  date: "2026-09-24T19:30:00+08:00",
  accent: "#84BFFF",
  song: "晴天",
};

const useFlowSteps = [
  ["放入下一场", "粘贴票务链接、上传截图，或手动添加。把下一场先落到本地。"],
  ["准备开场", "看现场倒计时，收好票根和时刻表，出门前把关键信息准备齐。"],
  ["留下现场记录", "散场后把现场记录留在本地，之后还能回头翻看这一场。"],
];

const audienceItems = [
  "适合需要现场准备的人",
  "适合想把票根、时刻表留在本地的人",
  "适合演唱会、Livehouse、音乐节",
];

function getSessionId() {
  const existing = localStorage.getItem(STORAGE_SESSION);
  if (existing) return existing;
  const id = `s_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;
  localStorage.setItem(STORAGE_SESSION, id);
  return id;
}

function track(type, detail = {}) {
  try {
    const event = {
      id: `e_${Date.now().toString(36)}`,
      at: new Date().toISOString(),
      session: getSessionId(),
      type,
      ...detail,
    };
    const raw = localStorage.getItem(STORAGE_EVENTS);
    const events = raw ? JSON.parse(raw) : [];
    events.push(event);
    localStorage.setItem(STORAGE_EVENTS, JSON.stringify(events.slice(-300)));
  } catch {}
}

function daysUntil(iso) {
  return Math.max(0, Math.ceil((new Date(iso) - Date.now()) / 86400000));
}

function formatDate(iso) {
  return new Intl.DateTimeFormat("zh-CN", {
    month: "long",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "Asia/Shanghai",
  }).format(new Date(iso));
}

export default function HomePage() {
  const [ambientMode, setAmbientMode] = useState(false);
  const [toast, setToast] = useState("");
  const toastTimer = useRef();
  const days = daysUntil(show.date);

  useEffect(() => {
    track("page_view", { ref: document.referrer || "direct" });
    return () => clearTimeout(toastTimer.current);
  }, []);

  useEffect(() => {
    if (!ambientMode) return undefined;
    const closeOnEscape = (event) => {
      if (event.key === "Escape") closeAmbient();
    };
    document.addEventListener("keydown", closeOnEscape);
    return () => document.removeEventListener("keydown", closeOnEscape);
  }, [ambientMode]);

  function openAmbient() {
    track("ambient_mode_enter", { showId: show.id });
    setAmbientMode(true);
  }

  function closeAmbient() {
    track("ambient_mode_exit", { showId: show.id });
    setAmbientMode(false);
  }

  function saveCountdown() {
    track("save_countdown", { showId: show.id });
    setToast("已放进你的开场前。");
    clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setToast(""), 2800);
  }

  return (
    <>
      <a href="#main-content" className="skip-link">跳到主要内容</a>
      <nav className="site-nav" aria-label="主导航">
        <div className="nav-logo">
          <img className="nav-logo-mark" src="/app-icon.png" alt="开场前 BeforeShow 图标" width="32" height="32" />
          <span className="nav-brand">开场前</span>
        </div>
      </nav>

      <main id="main-content">
        <section className="hero" aria-labelledby="hero-title">
          <div className="hero-bg" aria-hidden="true">
            <div className="hero-bg-base" />
            <div className="beam beam-1" />
            <div className="beam beam-2" />
            <div className="beam beam-3" />
            <div className="beam beam-4" />
            <div className="stage-orb" />
            <div className="hero-crowd" />
          </div>
          <div className="hero-content">
            <div className="hero-eyebrow fade-up"><span className="hero-eyebrow-dot" />现场准备 · 本地记录</div>
            <h1 id="hero-title" className="hero-title fade-up fade-up-delay-1">
              <span className="hero-title-line">现场准备与</span>
              <span className="hero-title-line hero-title-accent">本地记录工具。</span>
            </h1>
            <p className="hero-sub fade-up fade-up-delay-2">
              开场前 BeforeShow 用于现场准备与本地记录，提供现场倒计时、记录票根、记录时刻表、现场记录等功能。
            </p>
            <div className="hero-feature-list fade-up fade-up-delay-2" aria-label="BeforeShow 可做的事">
              <span>现场倒计时</span><span>记录票根</span><span>记录时刻表</span><span>现场记录</span>
            </div>
          </div>
        </section>

        <section id="experience" aria-labelledby="experience-title">
          <div className="section">
            <p className="section-label">开场前两周</p>
            <h2 className="section-title" id="experience-title">先把下一场放进来，<br />再把准备做齐。</h2>
            <p className="section-desc">现场倒计时帮你盯住开场时间；票根、时刻表和现场记录都留在本地。</p>
            <div className="feature-modules" aria-label="BeforeShow 核心体验">
              <article className="feature-module">
                <div className="feature-module-head">
                  <span className="feature-module-num">01</span>
                  <div>
                    <h3 className="feature-module-title">现场倒计时</h3>
                    <p className="feature-module-desc">把下一场放进来，每天知道离开场还有多久。</p>
                  </div>
                </div>
                <div className="countdown-card" style={{ "--show-accent": show.accent }}>
                  <div className="countdown-top">
                    <span className="countdown-kicker">我的下一场</span>
                    <span className="single-show-chip"><span className={`show-type-dot show-type-${show.type}`} />{show.label} · {show.artist}</span>
                  </div>
                  <div className="countdown-main-area">
                    <div className="countdown-left">
                      <div className="countdown-glow" />
                      <p className="countdown-days-label">距离开场</p>
                      <span className="countdown-days-number" aria-label={`${days} 天`} suppressHydrationWarning>{days}</span>
                      <span className="countdown-days-unit">天</span>
                      <button className="btn-ambient" type="button" onClick={openAmbient}>✨ 现场前夕氛围</button>
                    </div>
                    <div className="countdown-right">
                      <div>
                        <h3 className="countdown-artist">{show.artist} · {show.venue}</h3>
                        <p className="countdown-meta">{formatDate(show.date)}</p>
                        <div className="countdown-suggestion">
                          <p className="suggestion-label">今天先靠近一点</p>
                          <p className="suggestion-text">先听一遍<strong>《{show.song}》</strong>现场版，让身体记得这场演出的节奏。</p>
                        </div>
                      </div>
                      <button className="btn btn-primary" type="button" onClick={saveCountdown}>放进我的开场前</button>
                    </div>
                  </div>
                </div>
              </article>
            </div>
          </div>
        </section>

        <section id="use-flow" className="use-flow" aria-labelledby="use-flow-title">
          <div className="section">
            <p className="section-label">使用流程</p>
            <h2 className="section-title" id="use-flow-title">从准备开场，<br />到留下这场记录。</h2>
            <div className="how-grid" aria-label="BeforeShow 使用流程">
              {useFlowSteps.map(([title, description], index) => (
                <article className="how-card" style={{ "--line-color": "var(--accent)" }} key={title}>
                  <p className="how-num">{String(index + 1).padStart(2, "0")}</p>
                  <h3 className="how-title">{title}</h3>
                  <p className="how-desc">{description}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section id="audience" className="audience" aria-labelledby="audience-title">
          <div className="section">
            <p className="section-label">适合谁</p>
            <h2 className="section-title" id="audience-title">给需要把现场准备好，<br />也想把记录留在本地的人。</h2>
            <div className="audience-list" aria-label="BeforeShow 适合的人群">
              {audienceItems.map((item) => (
                <article className="audience-item" key={item}>
                  <span className="audience-check" aria-hidden="true">✓</span>
                  <h3 className="audience-text">{item}</h3>
                </article>
              ))}
            </div>
          </div>
        </section>
      </main>

      <footer className="footer">
        <span>开场前 · BeforeShow</span>
        <span>现场准备与本地记录工具。</span>
        <nav className="footer-links" aria-label="页脚链接">
          <a className="footer-link" href="https://beian.miit.gov.cn/" target="_blank" rel="noopener noreferrer">浙ICP备2026041359号-2</a>
          <a className="footer-link" href="/privacy/">隐私政策</a>
          <a className="footer-link" href="/terms/">用户协议</a>
          <a className="footer-link" href="/link-guide/">如何获取票务链接</a>
        </nav>
      </footer>

      {toast && <div className="toast" role="status">{toast}</div>}
      {ambientMode && (
        <div className="ambient-modal" style={{ "--show-accent": show.accent }} onClick={(event) => event.target === event.currentTarget && closeAmbient()}>
          <div className="ambient-modal-bg" style={{ backgroundImage: "url('https://img.alicdn.com/bao/uploaded/https://img.alicdn.com/imgextra/i2/2251059038/O1CN01nWPQm82GdSnG5tWAW_!!2251059038.jpg_q60.jpg_.webp')" }} />
          <div className="ambient-modal-overlay" />
          <button className="ambient-close-btn" type="button" aria-label="关闭氛围模式" onClick={closeAmbient}>✕</button>
          <div className="ambient-container">
            <div className="ambient-header">
              <p className="ambient-venue-label">现场前夕 · {show.venue}</p>
              <h2 className="ambient-show-artist">{show.artist}</h2>
            </div>
            <div className="ambient-glow-ring">
              <svg className="ambient-ring-svg" viewBox="0 0 100 100" aria-hidden="true">
                <circle className="ambient-ring-bg" cx="50" cy="50" r="45" />
                <circle className="ambient-ring-active" cx="50" cy="50" r="45" style={{ strokeDasharray: 283, strokeDashoffset: 60, stroke: show.accent }} />
              </svg>
              <div className="ambient-countdown-content">
                <span className="ambient-countdown-days" suppressHydrationWarning>{days}</span>
                <span className="ambient-countdown-unit">天</span>
              </div>
            </div>
            <div className="ambient-player">
              <div className="visualizer" aria-hidden="true">
                {[1, 2, 3, 4, 5].map((bar) => <div className={`bar bar-${bar}`} key={bar} />)}
              </div>
              <div className="ambient-song-info">
                <span className="ambient-song-title">正在播放预演单曲：《{show.song}》</span>
                <span className="ambient-song-desc">感受这一刻，走到门口时，你已经在那场演出了。</span>
              </div>
            </div>
            <button className="btn btn-ghost ambient-exit" type="button" onClick={closeAmbient}>返回网页</button>
          </div>
        </div>
      )}
    </>
  );
}
