// A show shared from the app's countdown card. The show travels inside the token (see ShowShareLink.swift);
// where the app is installed the link opens it, so this page is for everyone else.

const APP_STORE_URL = "https://apps.apple.com/app/id6780078298";
const SITE = "https://beforeshow.doublewaterapps.com";

function escapeHTML(value) {
  return String(value).replace(/[&<>"']/g, character => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[character]);
}

function isText(value, limit) {
  return typeof value === "string" && value.trim() !== "" && value.length <= limit;
}

function isOptionalText(value, limit) {
  return value == null || isText(value, limit);
}

export function showFromToken(token) {
  if (typeof token !== "string" || !/^[A-Za-z0-9_-]{1,4095}$/.test(token)) return null;
  let show;
  try {
    const padded = token.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - token.length % 4) % 4);
    show = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(padded), character => character.charCodeAt(0))));
  } catch {
    return null;
  }
  if (!show || show.v !== 1 || !isText(show.n, 200)
    || !Number.isSafeInteger(show.d) || !Number.isSafeInteger(show.t)
    || (show.e != null && !Number.isSafeInteger(show.e))
    || (show.s != null && (!Number.isInteger(show.s) || Math.abs(show.s) > 64800))
    || !isOptionalText(show.z, 64) || !isOptionalText(show.c, 200) || !isOptionalText(show.l, 200)) {
    return null;
  }
  if (show.p != null) {
    try {
      const cover = new URL(show.p);
      if (cover.protocol !== "https:" && cover.protocol !== "http:") show.p = null;
    } catch {
      show.p = null;
    }
  }
  return show;
}

function localeFor(request) {
  const language = request.headers.get("Accept-Language") || "";
  if (/^zh-(TW|HK|MO|Hant)/i.test(language)) return "zh-Hant";
  if (!language || /^zh/i.test(language)) return "zh-Hans";
  return "en";
}

const WORDS = {
  "zh-Hans": {
    app: "开场前",
    open: "在开场前中添加这场",
    openInBrowser: "在浏览器中打开",
    download: "还没有开场前？前往 App Store",
    note: "安装后再扫一次码，就能把这场加进开场前",
    wechatTip: "点击右上角「···」，选择在浏览器中打开",
    closeGuide: "轻触任意处关闭",
    invalidTitle: "打不开这场现场",
    invalidMessage: "链接不完整。下载开场前，自己添加这场现场。",
    home: "返回首页",
  },
  "zh-Hant": {
    app: "開場前",
    open: "在開場前中加入這場",
    openInBrowser: "在瀏覽器中開啟",
    download: "還沒有開場前？前往 App Store",
    note: "安裝後再掃一次碼，就能把這場加進開場前",
    wechatTip: "點擊右上角「···」，選擇在瀏覽器中開啟",
    closeGuide: "輕觸任意處關閉",
    invalidTitle: "無法開啟這場現場",
    invalidMessage: "連結不完整。下載開場前，自己加入這場現場。",
    home: "返回首頁",
  },
  en: {
    app: "BeforeShow",
    open: "Add to BeforeShow",
    openInBrowser: "Open in Browser",
    download: "Don’t have BeforeShow? Get it on the App Store",
    note: "After installing, scan the code again to add this show",
    wechatTip: "Tap ··· at top right and choose \"Open in Browser\"",
    closeGuide: "Tap anywhere to close",
    invalidTitle: "Show unavailable",
    invalidMessage: "This link is incomplete. Download BeforeShow to add the show yourself.",
    home: "Back to home",
  },
};

function formatDate(seconds, show, locale, options) {
  let timeZone = show.z;
  let offset = 0;
  if (!timeZone) {
    timeZone = "UTC";
    offset = show.s ?? (locale.startsWith("zh") ? 28800 : 0);
  }
  const date = new Date((seconds + offset) * 1000);
  if (date.getUTCFullYear() !== new Date().getUTCFullYear()) options = { ...options, year: "numeric" };
  try {
    return new Intl.DateTimeFormat(locale, { ...options, timeZone }).format(date);
  } catch {
    return new Intl.DateTimeFormat(locale, { ...options, timeZone: "UTC" }).format(new Date((seconds + (show.s || 0)) * 1000));
  }
}

function whenText(show, locale) {
  const start = formatDate(show.t, show, locale, { month: "long", day: "numeric", weekday: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
  if (show.e == null) return start;
  const startDay = formatDate(show.d, show, locale, { month: "long", day: "numeric" });
  const endDay = formatDate(show.e, show, locale, { month: "long", day: "numeric" });
  return startDay === endDay ? start : `${start} – ${endDay}`;
}

function invalidResponse(words, locale) {
  return new Response(`<!doctype html>
<html lang="${locale}"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="robots" content="noindex,nofollow"><title>${escapeHTML(words.invalidTitle)} · ${escapeHTML(words.app)}</title>
<link rel="icon" href="/app-icon.png">
<style>
:root { color-scheme: dark; --bg: #050508; --text: #F5F1E9; --text-soft: #AAA5AF; }
* { box-sizing: border-box; margin: 0; padding: 0; }
body { min-height: 100dvh; display: grid; place-items: center; padding: 24px 16px; background: var(--bg); color: var(--text); font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif; -webkit-font-smoothing: antialiased; }
main { width: min(400px, 100%); text-align: center; }
img { width: 88px; height: 88px; border-radius: 22px; margin-bottom: 20px; }
h1 { font-size: 24px; font-weight: 700; margin-bottom: 12px; }
p { color: var(--text-soft); line-height: 1.6; font-size: 15px; }
a { display: block; margin-top: 28px; padding: 13px 20px; border-radius: 14px; background: var(--text); color: var(--bg); text-decoration: none; font-weight: 650; font-size: 15px; }
</style></head><body><main><img src="/app-icon.png" alt="">
<h1>${escapeHTML(words.invalidTitle)}</h1><p>${escapeHTML(words.invalidMessage)}</p><a href="/">${escapeHTML(words.home)}</a></main></body></html>`, {
    status: 404,
    headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store", "X-Robots-Tag": "noindex, nofollow" },
  });
}

export function onRequestGet({ request, params }) {
  const locale = localeFor(request);
  const words = WORDS[locale];
  const token = params.token;
  const show = showFromToken(token);
  if (!show) return invalidResponse(words, locale);

  const canonical = `${SITE}/s/${token}`;
  const deepLink = `beforeshow://s/${token}`;
  const when = whenText(show, locale);
  const place = [show.l?.trim(), show.c?.trim()].filter(Boolean).filter((part, index, parts) => index === 0 || !parts[0].includes(part)).join(" · ");
  const description = [when, place].filter(Boolean).join(" · ");
  const cover = show.p?.trim();
  const isWechat = /MicroMessenger/i.test(request.headers.get("User-Agent") || "");
  const openHref = isWechat ? "#wechat-guide" : deepLink;

  const html = `<!doctype html>
<html lang="${locale}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
  <meta name="robots" content="noindex,nofollow">
  <meta name="theme-color" content="#050508">
  <title>${escapeHTML(show.n)} · ${escapeHTML(words.app)}</title>
  <meta name="description" content="${escapeHTML(description)}">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="${escapeHTML(words.app)}">
  <meta property="og:title" content="${escapeHTML(show.n)}">
  <meta property="og:description" content="${escapeHTML(description)}">
  <meta property="og:url" content="${escapeHTML(canonical)}">
  <meta property="og:image" content="${escapeHTML(cover || `${SITE}/app-icon.png`)}">
  <meta name="apple-itunes-app" content="app-id=6780078298, app-argument=${escapeHTML(deepLink)}">
  <link rel="icon" href="/app-icon.png" type="image/png">
  <link rel="apple-touch-icon" href="/app-icon.png">
  <style>
    :root { color-scheme: dark; --bg: #050508; --surface: rgba(255,255,255,0.05); --border: rgba(245,241,233,0.12); --text: #F5F1E9; --text-soft: #AAA5AF; --text-faint: #75707C; --accent: #84BFFF; }
    [hidden] { display: none !important; }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { min-height: 100dvh; display: flex; align-items: center; justify-content: center; padding: 20px 16px max(20px, env(safe-area-inset-bottom)); background: var(--bg); color: var(--text); font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Helvetica Neue", sans-serif; -webkit-font-smoothing: antialiased; overflow-x: hidden; }
    body::before { content: ""; position: fixed; top: -80px; left: 50%; transform: translateX(-50%); width: min(640px, 120vw); height: 440px; background: radial-gradient(ellipse at 50% 10%, rgba(132,191,255,0.2) 0%, rgba(255,179,107,0.08) 45%, transparent 72%); pointer-events: none; }
    main { position: relative; width: min(390px, 100%); display: flex; flex-direction: column; gap: 14px; }
    .brand { display: flex; align-items: center; gap: 10px; font-size: 15px; font-weight: 700; }
    .brand img { width: 32px; height: 32px; border-radius: 8px; border: 1px solid rgba(255,255,255,0.15); }
    .card { border: 1px solid var(--border); border-radius: 26px; background: linear-gradient(175deg, rgba(255,255,255,0.08), rgba(255,255,255,0.02)); box-shadow: 0 24px 64px rgba(0,0,0,0.65); overflow: hidden; padding: 20px 18px 18px; display: flex; flex-direction: column; gap: 16px; }
    .poster { align-self: center; width: min(180px, 48vw); aspect-ratio: 3 / 4; max-height: 32vh; border-radius: 14px; overflow: hidden; border: 1px solid rgba(255,255,255,0.16); box-shadow: 0 10px 28px rgba(0,0,0,0.65); }
    .poster img { width: 100%; height: 100%; object-fit: cover; display: block; }
    h1 { font-size: 21px; font-weight: 750; line-height: 1.32; letter-spacing: -0.015em; }
    .meta { display: flex; flex-direction: column; gap: 6px; font-size: 14px; color: var(--text-soft); line-height: 1.4; }
    .meta strong { color: var(--text); font-weight: 600; }
    .btn { display: flex; align-items: center; justify-content: center; padding: 13px 16px; border-radius: 14px; background: var(--text); color: #050508; font-size: 15px; font-weight: 650; text-decoration: none; }
    .btn:active { transform: scale(0.985); }
    .sublink { display: block; text-align: center; font-size: 13px; color: var(--text-soft); text-decoration: none; padding: 4px; }
    .note { text-align: center; font-size: 12px; color: var(--text-faint); }
    .guide { display: none; position: fixed; inset: 0; z-index: 10; background: rgba(5,5,8,0.88); text-decoration: none; }
    #wechat-guide:target { display: block; }
    .bubble { position: absolute; top: max(16px, env(safe-area-inset-top)); right: 20px; max-width: 260px; padding: 14px 18px; border-radius: 16px; background: #15151E; border: 1px solid rgba(245,241,233,0.22); color: var(--text); font-size: 14px; font-weight: 600; line-height: 1.4; }
    .bubble span { display: block; margin-top: 6px; font-size: 11.5px; font-weight: 400; color: var(--text-soft); }
  </style>
</head>
<body>
  <main>
    <div class="brand"><img src="${SITE}/app-icon.png" alt="">${escapeHTML(words.app)}</div>
    <article class="card">
      ${cover ? `<div class="poster"><img src="${escapeHTML(cover)}" alt="" referrerpolicy="no-referrer"></div>` : ""}
      <h1>${escapeHTML(show.n)}</h1>
      <div class="meta">
        <strong>${escapeHTML(when)}</strong>
        ${place ? `<span>${escapeHTML(place)}</span>` : ""}
      </div>
      <a id="open" class="btn" href="${escapeHTML(openHref)}">${escapeHTML(isWechat ? words.openInBrowser : words.open)}</a>
      <a class="sublink" href="${isWechat ? "#wechat-guide" : APP_STORE_URL}">${escapeHTML(words.download)}</a>
    </article>
    <p class="note">${escapeHTML(words.note)}</p>
  </main>
  <a href="#" class="guide" id="wechat-guide" aria-label="${escapeHTML(words.closeGuide)}">
    <div class="bubble">${escapeHTML(words.wechatTip)}<span>${escapeHTML(words.closeGuide)}</span></div>
  </a>
</body>
</html>`;
  return new Response(html, {
    headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store", "X-Robots-Tag": "noindex, nofollow" },
  });
}
