const APP_STORE_URL = "https://apps.apple.com/app/id6780078298";

function escapeHTML(value) {
  return String(value).replace(/[&<>"']/g, character => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[character]);
}

function invitationFromToken(token) {
  if (!/^[A-Za-z0-9_-]{1,8191}$/.test(token)) return null;
  try {
    const padded = token.replace(/-/g, "+").replace(/_/g, "/")
      + "=".repeat((4 - token.length % 4) % 4);
    const payload = JSON.parse(new TextDecoder().decode(
      Uint8Array.from(atob(padded), character => character.charCodeAt(0))
    ));
    const shareURL = new URL(payload.u);
    const host = shareURL.hostname.toLowerCase();
    const isValidHost = host === "icloud.com" || host.endsWith(".icloud.com")
      || host === "icloud.com.cn" || host.endsWith(".icloud.com.cn")
      || host === "apple.com" || host.endsWith(".apple.com");
    const hasValidPath = shareURL.pathname.startsWith("/share/") || host.includes("share.");
    if (payload.v !== 1 || shareURL.protocol !== "https:"
      || !isValidHost
      || !hasValidPath
      || typeof payload.n !== "string" || !payload.n.trim() || payload.n.length > 200
      || !Number.isSafeInteger(payload.t)
      || (payload.s != null && (!Number.isInteger(payload.s) || Math.abs(payload.s) > 50400))
      || (payload.l != null && (typeof payload.l !== "string" || payload.l.length > 240))
      || (payload.o != null && (typeof payload.o !== "string" || payload.o.length > 100))) {
      return null;
    }
    if (payload.c != null) {
      if (typeof payload.c !== "string" || !payload.c.trim() || payload.c.length > 1024) return null;
      try {
        const coverURL = new URL(payload.c);
        if (coverURL.protocol !== "https:" && coverURL.protocol !== "http:") return null;
      } catch {
        return null;
      }
    }
    return payload;
  } catch {
    return null;
  }
}

function copyFor(request, invite) {
  const language = request.headers.get("Accept-Language") || "";
  const locale = /^zh-(TW|HK|Hant)/i.test(language) ? "zh-Hant"
    : /^en/i.test(language) ? "en" : "zh-Hans";
  const date = new Date((invite.t + (invite.z ? 0 : (invite.s || 0))) * 1000);
  if (Number.isNaN(date.getTime())) return null;
  let when;
  try {
    when = new Intl.DateTimeFormat(locale, {
      month: "long", day: "numeric", hour: "2-digit", minute: "2-digit",
      timeZone: invite.z || "UTC",
    }).format(date);
  } catch {
    return null;
  }
  const owner = invite.o?.trim() || ({ en: "A friend", "zh-Hant": "朋友", "zh-Hans": "朋友" })[locale];
  const words = {
    en: {
      title: `Let's go to ${invite.n}`,
      byline: `${owner} invited you to go together`,
      companionTag: "Companion Invite",
      open: "Open in BeforeShow",
      openInBrowser: "Open in Browser",
      download: "Download BeforeShow",
      wechatTip: "Tap ··· at top right and choose \"Open in Browser\"",
      note: "Confirm in BeforeShow to join",
    },
    "zh-Hant": {
      title: `一起去 ${invite.n}`,
      byline: `${owner} 邀請你一起去`,
      companionTag: "同行邀請",
      open: "在 BeforeShow 中開啟",
      openInBrowser: "在瀏覽器中開啟",
      download: "下載 BeforeShow",
      wechatTip: "點擊右上角「···」，選擇在瀏覽器中開啟",
      note: "在 App 內確認後加入同行",
    },
    "zh-Hans": {
      title: `一起去 ${invite.n}`,
      byline: `${owner} 邀请你一起去`,
      companionTag: "同行邀请",
      open: "在 BeforeShow 中打开",
      openInBrowser: "在浏览器中打开",
      download: "下载 BeforeShow",
      wechatTip: "点击右上角「···」，选择在浏览器中打开",
      note: "在 App 内确认后加入同行",
    },
  }[locale];
  return { locale, when, ...words };
}

export function onRequestGet({ request, params }) {
  const token = params.token;
  const invite = typeof token === "string" && invitationFromToken(token);
  const copy = invite && copyFor(request, invite);
  if (!copy) {
    return new Response("Invalid invitation", { status: 404 });
  }
  const canonical = `https://beforeshow.doublewaterapps.com/join/${token}`;
  const deepLink = `beforeshow://join/${token}`;
  const detail = [copy.when, invite.l?.trim()].filter(Boolean).join(" · ");
  const description = [detail, copy.byline, "BeforeShow"].filter(Boolean).join(" · ");
  const coverURL = invite.c?.trim();
  const shareImage = coverURL || "https://beforeshow.doublewaterapps.com/app-icon.png";
  const twitterCard = coverURL ? "summary_large_image" : "summary";
  const userAgent = request.headers.get("User-Agent") || "";
  const isWechat = /MicroMessenger/i.test(userAgent);
  const html = `<!doctype html>
<html lang="${escapeHTML(copy.locale)}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
  <meta name="robots" content="noindex,nofollow">
  <meta name="theme-color" content="#050508">
  <title>${escapeHTML(copy.title)} · BeforeShow</title>
  <meta name="description" content="${escapeHTML(description)}">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="BeforeShow">
  <meta property="og:title" content="${escapeHTML(copy.title)}">
  <meta property="og:description" content="${escapeHTML(description)}">
  <meta property="og:url" content="${escapeHTML(canonical)}">
  <meta property="og:image" content="${escapeHTML(shareImage)}">
  <meta name="twitter:card" content="${escapeHTML(twitterCard)}">
  <meta name="twitter:title" content="${escapeHTML(copy.title)}">
  <meta name="twitter:description" content="${escapeHTML(description)}">
  <meta name="twitter:image" content="${escapeHTML(shareImage)}">
  <link rel="icon" href="/app-icon.png" type="image/png">
  <link rel="apple-touch-icon" href="/app-icon.png">
  <style>
    :root {
      color-scheme: dark;
      --bg: #050508;
      --surface: rgba(255, 255, 255, 0.05);
      --surface-lifted: rgba(255, 255, 255, 0.09);
      --border: rgba(245, 241, 233, 0.12);
      --border-strong: rgba(245, 241, 233, 0.22);
      --text: #F5F1E9;
      --text-soft: #AAA5AF;
      --text-faint: #75707C;
      --accent: #84BFFF;
      --accent-warm: #FFB36B;
      --radius-card: 26px;
      --radius-btn: 14px;
      --radius-pill: 999px;
      --shadow-card: 0 24px 64px rgba(0, 0, 0, 0.65);
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      min-height: 100vh;
      min-height: 100dvh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      background: var(--bg);
      color: var(--text);
      padding: 24px 16px env(safe-area-inset-bottom, 24px);
      position: relative;
      overflow-x: hidden;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Helvetica Neue", sans-serif;
      -webkit-font-smoothing: antialiased;
    }
    /* Stage Glow */
    body::before {
      content: "";
      position: fixed;
      top: -60px;
      left: 50%;
      transform: translateX(-50%);
      width: min(640px, 120vw);
      height: 420px;
      background: radial-gradient(ellipse at 50% 10%, rgba(132, 191, 255, 0.22) 0%, rgba(255, 179, 107, 0.08) 45%, transparent 72%);
      pointer-events: none;
      z-index: 0;
    }
    /* Subtle Grain */
    body::after {
      content: "";
      position: fixed;
      inset: 0;
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='180' height='180'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.8' numOctaves='3' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='180' height='180' filter='url(%23n)' opacity='0.035'/%3E%3C/svg%3E");
      pointer-events: none;
      z-index: 0;
      opacity: 0.65;
    }
    main {
      width: min(400px, 100%);
      position: relative;
      z-index: 1;
      display: flex;
      flex-direction: column;
      gap: 16px;
    }

    /* App Header */
    .app-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 0 4px;
    }
    .app-brand {
      display: flex;
      align-items: center;
      gap: 10px;
    }
    .app-icon {
      width: 34px;
      height: 34px;
      border-radius: 9px;
      border: 1px solid rgba(255, 255, 255, 0.15);
      box-shadow: 0 4px 14px rgba(0, 0, 0, 0.4);
    }
    .app-name {
      font-size: 15px;
      font-weight: 700;
      letter-spacing: -0.01em;
      color: var(--text);
      line-height: 1.2;
    }
    .companion-chip {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 4px 11px;
      border-radius: var(--radius-pill);
      background: rgba(132, 191, 255, 0.12);
      border: 1px solid rgba(132, 191, 255, 0.26);
      color: var(--accent);
      font-size: 12px;
      font-weight: 600;
    }
    .pulse-dot {
      width: 6px;
      height: 6px;
      border-radius: 50%;
      background: var(--accent);
      box-shadow: 0 0 8px var(--accent);
    }

    /* Ticket Card */
    .ticket-card {
      background: linear-gradient(175deg, rgba(255, 255, 255, 0.07) 0%, rgba(255, 255, 255, 0.02) 100%);
      border: 1px solid var(--border);
      border-radius: var(--radius-card);
      box-shadow: var(--shadow-card);
      backdrop-filter: blur(24px);
      -webkit-backdrop-filter: blur(24px);
      overflow: hidden;
    }
    .ticket-cover-wrap {
      width: 100%;
      aspect-ratio: 16 / 10;
      position: relative;
      overflow: hidden;
      background: rgba(255, 255, 255, 0.04);
    }
    .ticket-cover {
      width: 100%;
      height: 100%;
      object-fit: cover;
      display: block;
    }
    .ticket-cover-wrap::after {
      content: "";
      position: absolute;
      inset: 0;
      background: linear-gradient(180deg, transparent 65%, rgba(5, 5, 8, 0.65) 100%);
      pointer-events: none;
    }
    .ticket-head {
      padding: 24px 22px 20px;
      display: flex;
      flex-direction: column;
      gap: 14px;
    }
    .ticket-inviter {
      display: inline-flex;
      align-items: center;
      gap: 7px;
      font-size: 13px;
      font-weight: 600;
      color: var(--accent-warm);
    }
    .inviter-icon { display: flex; }
    .show-title {
      font-size: 22px;
      font-weight: 750;
      line-height: 1.32;
      letter-spacing: -0.015em;
      color: var(--text);
    }
    .ticket-meta {
      display: flex;
      flex-direction: column;
      gap: 10px;
      padding-top: 4px;
    }
    .meta-row {
      display: flex;
      align-items: flex-start;
      gap: 9px;
      font-size: 14px;
      line-height: 1.4;
      color: var(--text-soft);
    }
    .meta-icon {
      color: var(--accent);
      flex-shrink: 0;
      margin-top: 2px;
      display: flex;
    }
    .meta-text {
      color: var(--text);
      font-weight: 550;
    }

    /* Rip Separator */
    .ticket-rip {
      position: relative;
      height: 20px;
      display: flex;
      align-items: center;
    }
    .rip-notch {
      position: absolute;
      width: 18px;
      height: 18px;
      border-radius: 50%;
      background: var(--bg);
      top: 1px;
    }
    .rip-left {
      left: -9px;
      box-shadow: inset -1px 0 0 var(--border);
    }
    .rip-right {
      right: -9px;
      box-shadow: inset 1px 0 0 var(--border);
    }
    .rip-line {
      width: 100%;
      height: 1px;
      border-top: 1px dashed var(--border);
      margin: 0 16px;
    }

    /* Ticket Action */
    .ticket-action {
      padding: 18px 20px 22px;
      display: flex;
      flex-direction: column;
      gap: 10px;
    }
    .btn {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      padding: 14px 18px;
      border-radius: var(--radius-btn);
      text-decoration: none;
      font-size: 15px;
      font-weight: 650;
      letter-spacing: -0.01em;
      transition: all 0.18s cubic-bezier(.16,1,.3,1);
      -webkit-tap-highlight-color: transparent;
    }
    .btn:active {
      transform: scale(0.985);
    }
    .btn-primary {
      background: var(--text);
      color: #050508;
      box-shadow: 0 6px 20px rgba(245, 241, 233, 0.18);
    }
    .btn-primary:hover {
      background: #FFFFFF;
    }
    .btn-secondary {
      background: var(--surface);
      color: var(--text);
      border: 1px solid var(--border);
    }
    .btn-secondary:hover {
      background: var(--surface-lifted);
      border-color: var(--border-strong);
    }
    .btn-icon { display: flex; flex-shrink: 0; }

    /* Footer */
    .page-footer {
      text-align: center;
      padding: 4px 12px;
    }
    .privacy-note {
      font-size: 12px;
      color: var(--text-faint);
    }

    /* Minimalist Single WeChat Guide */
    .wechat-overlay {
      display: none;
      position: fixed;
      inset: 0;
      z-index: 9999;
      background: rgba(5, 5, 8, 0.88);
      backdrop-filter: blur(12px);
      -webkit-backdrop-filter: blur(12px);
      padding: 16px 20px;
      text-decoration: none;
    }
    #wechat-guide:target {
      display: block;
    }
    .guide-pointer-box {
      position: absolute;
      top: max(16px, env(safe-area-inset-top, 16px));
      right: 20px;
      display: flex;
      flex-direction: column;
      align-items: flex-end;
      gap: 8px;
    }
    .guide-arrow {
      animation: pointUp 1.2s infinite ease-in-out;
    }
    @keyframes pointUp {
      0%, 100% { transform: translateY(0); }
      50% { transform: translateY(-6px); }
    }
    .guide-bubble {
      background: #15151E;
      border: 1px solid var(--border-strong);
      border-radius: 16px;
      padding: 14px 18px;
      color: var(--text);
      font-size: 14px;
      font-weight: 600;
      line-height: 1.4;
      max-width: 260px;
      text-align: left;
      box-shadow: 0 16px 40px rgba(0, 0, 0, 0.7);
    }
    .guide-bubble strong {
      color: var(--accent-warm);
    }
    .guide-bubble-hint {
      display: block;
      font-size: 11.5px;
      font-weight: 400;
      color: var(--text-soft);
      margin-top: 6px;
    }
  </style>
</head>
<body class="${isWechat ? "is-wechat" : ""}">
  <main>
    <header class="app-header">
      <div class="app-brand">
        <img src="https://beforeshow.doublewaterapps.com/app-icon.png" alt="BeforeShow" class="app-icon">
        <span class="app-name">BeforeShow</span>
      </div>
      <span class="companion-chip">
        <span class="pulse-dot"></span>
        ${escapeHTML(copy.companionTag)}
      </span>
    </header>

    <article class="ticket-card">
      ${coverURL ? `
      <div class="ticket-cover-wrap">
        <img class="ticket-cover" src="${escapeHTML(coverURL)}" alt="${escapeHTML(invite.n)}" loading="eager" decoding="async">
      </div>` : ""}
      <div class="ticket-head">
        <div class="ticket-inviter">
          <span class="inviter-icon">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"></path><circle cx="12" cy="7" r="4"></circle></svg>
          </span>
          <span>${escapeHTML(copy.byline)}</span>
        </div>
        <h1 class="show-title">${escapeHTML(invite.n)}</h1>
        <div class="ticket-meta">
          <div class="meta-row">
            <span class="meta-icon">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2" ry="2"></rect><line x1="16" y1="2" x2="16" y2="6"></line><line x1="8" y1="2" x2="8" y2="6"></line><line x1="3" y1="10" x2="21" y2="10"></line></svg>
            </span>
            <span class="meta-text">${escapeHTML(copy.when)}</span>
          </div>
          ${invite.l?.trim() ? `
          <div class="meta-row">
            <span class="meta-icon">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"></path><circle cx="12" cy="10" r="3"></circle></svg>
            </span>
            <span class="meta-text">${escapeHTML(invite.l.trim())}</span>
          </div>` : ""}
        </div>
      </div>

      <div class="ticket-rip">
        <div class="rip-notch rip-left"></div>
        <div class="rip-line"></div>
        <div class="rip-notch rip-right"></div>
      </div>

      <div class="ticket-action">
        <a class="btn btn-primary" href="${isWechat ? "#wechat-guide" : escapeHTML(deepLink)}">
          <svg class="btn-icon" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"></path><polyline points="15 3 21 3 21 9"></polyline><line x1="10" y1="14" x2="21" y2="3"></line></svg>
          <span>${isWechat ? escapeHTML(copy.openInBrowser) : escapeHTML(copy.open)}</span>
        </a>

        <a class="btn btn-secondary" href="${APP_STORE_URL}" target="_blank" rel="noopener">
          <svg class="btn-icon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path><polyline points="7 10 12 15 17 10"></polyline><line x1="12" y1="15" x2="12" y2="3"></line></svg>
          <span>${escapeHTML(copy.download)}</span>
        </a>
      </div>
    </article>

    <footer class="page-footer">
      <p class="privacy-note">${escapeHTML(copy.note)}</p>
    </footer>
  </main>

  <a href="#" class="wechat-overlay" id="wechat-guide" aria-label="关闭指引">
    <div class="guide-pointer-box">
      <svg class="guide-arrow" width="56" height="56" viewBox="0 0 60 60" fill="none">
        <path d="M10 50 C 20 30, 36 18, 50 10" stroke="#FFB36B" stroke-width="3" stroke-linecap="round" stroke-dasharray="4 4"/>
        <polyline points="38,10 50,10 50,22" stroke="#FFB36B" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>
      <div class="guide-bubble">
        <div>点击右上角 <strong>「 ··· 」</strong><br>选择在浏览器中打开</div>
        <span class="guide-bubble-hint">轻触任意处关闭</span>
      </div>
    </div>
  </a>
</body>
</html>`;
  return new Response(html, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Robots-Tag": "noindex, nofollow",
    },
  });
}
