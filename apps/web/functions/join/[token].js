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
    if (payload.v !== 1 || shareURL.protocol !== "https:"
      || !(shareURL.hostname === "icloud.com" || shareURL.hostname.endsWith(".icloud.com"))
      || !shareURL.pathname.startsWith("/share/")
      || typeof payload.n !== "string" || !payload.n.trim() || payload.n.length > 200
      || !Number.isSafeInteger(payload.t)
      || (payload.s != null && (!Number.isInteger(payload.s) || Math.abs(payload.s) > 50400))
      || (payload.l != null && (typeof payload.l !== "string" || payload.l.length > 240))
      || (payload.o != null && (typeof payload.o !== "string" || payload.o.length > 100))) {
      return null;
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
      open: "Open invitation in BeforeShow",
      download: "Download BeforeShow",
      return: "After installing, return here to open the invitation.",
      note: "Joining happens only after you confirm in the app.",
    },
    "zh-Hant": {
      title: `一起去 ${invite.n}`,
      byline: `${owner} 邀請你一起去`,
      open: "在 BeforeShow 中開啟邀請",
      download: "下載 BeforeShow",
      return: "安裝後返回此頁，繼續開啟邀請。",
      note: "在 App 內確認後才會加入同行。",
    },
    "zh-Hans": {
      title: `一起去 ${invite.n}`,
      byline: `${owner} 邀请你一起去`,
      open: "在 BeforeShow 中打开邀请",
      download: "下载 BeforeShow",
      return: "安装后返回此页，继续打开邀请。",
      note: "在 App 内确认后才会加入同行。",
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
  const html = `<!doctype html>
<html lang="${escapeHTML(copy.locale)}">
<head>
  <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="robots" content="noindex,nofollow">
  <meta name="theme-color" content="#050508">
  <title>${escapeHTML(copy.title)} · BeforeShow</title>
  <meta name="description" content="${escapeHTML(description)}">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="BeforeShow">
  <meta property="og:title" content="${escapeHTML(copy.title)}">
  <meta property="og:description" content="${escapeHTML(description)}">
  <meta property="og:url" content="${escapeHTML(canonical)}">
  <meta property="og:image" content="https://beforeshow.doublewaterapps.com/app-icon.png">
  <meta name="twitter:card" content="summary">
  <meta name="twitter:title" content="${escapeHTML(copy.title)}">
  <meta name="twitter:description" content="${escapeHTML(description)}">
  <link rel="icon" href="/app-icon.png" type="image/png">
  <style>
    :root{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;color-scheme:dark;--bg:#050508;--text:#F5F1E9;--text-soft:#AAA5AF;--border:rgba(245,241,233,.22);--ink:#0B0B11;--radius:14px}
    *{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:var(--bg);color:var(--text);padding:24px}
    main{width:min(440px,100%);text-align:center}img{width:72px;height:72px;border-radius:18px;margin-bottom:28px}
    h1{font-size:27px;line-height:1.25;margin:0 0 18px}p{margin:0 0 12px;line-height:1.6;color:var(--text-soft)}
    .detail{font-size:16px;color:var(--text)}.byline{margin:22px 0 30px}a{display:block;padding:15px 18px;border-radius:var(--radius);text-decoration:none;font-weight:650;margin-top:12px}
    .primary{background:var(--text);color:var(--ink)}.secondary{border:1px solid var(--border);color:var(--text)}
    .hint{font-size:13px;color:var(--text-soft);margin-top:22px}
  </style>
</head>
<body><main>
  <img src="/app-icon.png" alt="BeforeShow">
  <h1>${escapeHTML(copy.title)}</h1>
  <p class="detail">${escapeHTML(detail)}</p>
  <p class="byline">${escapeHTML(copy.byline)}</p>
  <a class="primary" href="${escapeHTML(deepLink)}">${escapeHTML(copy.open)}</a>
  <a class="secondary" href="${APP_STORE_URL}">${escapeHTML(copy.download)}</a>
  <p class="hint">${escapeHTML(copy.return)}<br>${escapeHTML(copy.note)}</p>
</main></body></html>`;
  return new Response(html, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Robots-Tag": "noindex, nofollow",
    },
  });
}
