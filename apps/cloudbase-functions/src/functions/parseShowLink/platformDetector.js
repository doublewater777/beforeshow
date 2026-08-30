import { isLiveNationHost, liveNationEventId } from "./liveNationDomains.js";

const TICKETMASTER_DOMAINS = [
  "ticketmaster.com",
  "ticketmaster.ca",
  "ticketmaster.co.uk",
  "ticketmaster.ie",
  "ticketmaster.com.au",
  "ticketmaster.co.nz",
  "ticketmaster.com.mx",
  "ticketmaster.at",
  "ticketmaster.be",
  "ticketmaster.com.br",
  "ticketmaster.ch",
  "ticketmaster.cl",
  "ticketmaster.co",
  "ticketmaster.cy",
  "ticketmaster.cz",
  "ticketmaster.de",
  "ticketmaster.dk",
  "ticketmaster.es",
  "ticketmaster.fi",
  "ticketmaster.fr",
  "ticketmaster.gr",
  "ticketmaster.it",
  "ticketmaster.nl",
  "ticketmaster.no",
  "ticketmaster.pe",
  "ticketmaster.ph",
  "ticketmaster.pl",
  "ticketmaster.se",
  "ticketmaster.sg",
  "ticketmaster.co.za",
  "ticketmaster.ae"
];

const REDIRECT_DOMAINS = ["dpurl.cn"];

export class UnsupportedPlatformError extends Error {
  constructor(url) {
    super(`Unsupported show link platform: ${url}`);
    this.name = "UnsupportedPlatformError";
    this.code = "UNSUPPORTED_PLATFORM";
  }
}

/**
 * 基于 hostname 严格识别平台，拒绝仿冒域名与查询参数里的关键字误报。
 * 国内：大麦、秀动、猫眼、票星球、纷玩岛、网易云。
 * 海外：Ticketmaster、DICE、AXS、Live Nation。
 */
export function detectPlatform(urlString) {
  const host = hostnameOf(urlString);
  if (!host) {
    throw new UnsupportedPlatformError(urlString);
  }

  if (matchesDomain(host, "damai.cn")) return "damai";
  if (matchesDomain(host, "showstart.com")) return "showstart";
  if (matchesDomain(host, "maoyan.com")) return "maoyan";
  if (matchesDomain(host, "piaoxingqiu.com")) return "piaoxingqiu";
  if (matchesDomain(host, "livelab.com.cn")) return "fenwandao";
  if (host === "st.music.163.com") return "neteasemusic";
  if (TICKETMASTER_DOMAINS.some((domain) => matchesDomain(host, domain))) return "ticketmaster";
  if (matchesDomain(host, "dice.fm")) return "dice";
  if (matchesDomain(host, "axs.com")) return "axs";
  if (isLiveNationHost(host)) return "livenation";

  throw new UnsupportedPlatformError(urlString);
}

export function normalizeUrl(urlString) {
  const extractedUrl = extractShowUrl(urlString);
  let url;
  try {
    url = new URL(extractedUrl);
  } catch {
    throw new UnsupportedPlatformError(urlString);
  }
  const platform = detectPlatform(extractedUrl);

  if (platform === "damai") {
    const itemId = url.searchParams.get("itemId")
      ?? url.searchParams.get("id")
      ?? extractedUrl.match(/(?:itemId|id)\D*(\d{6,})/i)?.[1];
    if (!itemId) {
      throw new UnsupportedPlatformError(urlString);
    }

    return {
      platform,
      itemId,
      canonicalUrl: `https://detail.damai.cn/item.htm?id=${itemId}`
    };
  }

  if (platform === "showstart") {
    const activityId = url.searchParams.get("activityId")
      ?? extractedUrl.match(/activityId\D*(\d{6,})/i)?.[1];
    if (!activityId) {
      throw new UnsupportedPlatformError(urlString);
    }

    return {
      platform,
      activityId,
      canonicalUrl: `https://wap.showstart.com/pages/activity/detail/detail?activityId=${activityId}`
    };
  }

  if (platform === "maoyan") {
    const eventId = url.pathname.match(/\/detail\/(\d+)/i)?.[1]
      ?? url.hash.match(/\/detail\/(\d+)/i)?.[1]
      ?? url.searchParams.get("id")
      ?? url.searchParams.get("projectId");

    return {
      platform,
      ...(eventId ? { eventId } : {}),
      canonicalUrl: eventId
        ? `https://show.maoyan.com/qqw#/detail/${eventId}`
        : httpsUrlWithoutHash(url)
    };
  }

  if (platform === "piaoxingqiu") {
    const pathEventId = url.pathname.match(/\/content\/([a-f0-9]{16,32})\/?$/i)?.[1];
    const eventId = url.searchParams.get("showId") ?? pathEventId;
    const shareToken = url.searchParams.get("lssId");

    if (eventId) {
      return {
        platform,
        eventId,
        canonicalUrl: `https://m.piaoxingqiu.com/content/${encodeURIComponent(eventId)}?showId=${encodeURIComponent(eventId)}`
      };
    }

    return {
      platform,
      ...(shareToken ? { shareToken } : {}),
      canonicalUrl: shareToken
        ? `https://e.piaoxingqiu.com/?lssId=${encodeURIComponent(shareToken)}`
        : httpsUrlWithoutHash(url)
    };
  }

  if (platform === "fenwandao") {
    const eventId = url.searchParams.get("id") ?? url.searchParams.get("project_id") ?? url.searchParams.get("projectId");

    if (eventId && /\/buyTickets\/step1\/?$/i.test(url.pathname)) {
      const type = url.searchParams.get("type");
      const params = new URLSearchParams({ id: eventId });
      if (type) params.set("type", type);
      return {
        platform,
        eventId,
        canonicalUrl: `https://mobile.livelab.com.cn${url.pathname}?${params.toString()}`
      };
    }

    return {
      platform,
      ...(eventId ? { eventId } : {}),
      canonicalUrl: httpsUrlWithoutHash(url)
    };
  }

  if (platform === "neteasemusic") {
    const rawEventId = /^\/g\/show\/detail\/?$/i.test(url.pathname)
      ? url.searchParams.get("concertId")
      : null;
    const eventId = /^\d+$/.test(rawEventId ?? "") ? rawEventId : null;
    return {
      platform,
      ...(eventId ? { eventId } : {}),
      canonicalUrl: eventId
        ? `https://st.music.163.com/g/show/detail?concertId=${encodeURIComponent(eventId)}`
        : "https://st.music.163.com/g/show"
    };
  }

  if (platform === "ticketmaster") {
    const eventId = url.pathname.match(/\/event\/([^/?#]+)/i)?.[1];
    return {
      platform,
      ...(eventId ? { eventId } : {}),
      canonicalUrl: httpsUrlWithoutQuery(url)
    };
  }

  if (platform === "dice") {
    return {
      platform,
      canonicalUrl: httpsUrlWithoutQuery(url)
    };
  }

  if (platform === "axs") {
    const eventId = url.pathname.match(/\/events\/(\d+)/i)?.[1];
    return {
      platform,
      ...(eventId ? { eventId } : {}),
      canonicalUrl: httpsUrlWithoutQuery(url)
    };
  }

  if (platform === "livenation") {
    const eventId = liveNationEventId(url.pathname);
    return {
      platform,
      ...(eventId ? { eventId } : {}),
      canonicalUrl: httpsUrlWithoutQuery(url)
    };
  }

  throw new UnsupportedPlatformError(urlString);
}

/**
 * 解析受信任短链的第一跳，保留 Location 中的 hash 路由。
 * Node fetch 自动跟随重定向时会丢掉 hash，猫眼分享链接的现场 ID 正在 hash 中。
 */
export async function resolveRedirectUrl(urlString, { fetch = globalThis.fetch } = {}) {
  const extractedUrl = extractShowUrl(urlString);
  if (!isRedirectDomain(extractedUrl)) {
    return extractedUrl;
  }

  let currentUrl = extractedUrl;
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const response = await fetch(currentUrl, { redirect: "manual" });
    const location = response?.headers?.get?.("location");
    if (!location) {
      throw new UnsupportedPlatformError(urlString);
    }

    const nextUrl = new URL(location, currentUrl).toString();
    if (!isRedirectDomain(nextUrl)) {
      return nextUrl;
    }
    currentUrl = nextUrl;
  }

  throw new UnsupportedPlatformError(urlString);
}

/**
 * 从粘贴文本中取出可解析的票务 URL。
 * 无协议的域名路径会补上 https://，与客户端来源 chip 行为一致。
 */
export function extractShowUrl(input) {
  const trimmed = normalizeFullWidthAscii(input).trim();
  const match = trimmed.match(/https?:\/\/[^\s【】"'<>]+/i);
  const raw = stripNaturalLanguageTerminator(match?.[0] ?? trimmed);
  return ensureAbsoluteUrl(raw);
}

function stripNaturalLanguageTerminator(value) {
  let result = value;
  const naturalPunctuation = /[.,;:!?，。；：！？、]/u;
  for (let index = 0; index < result.length; index += 1) {
    if (!naturalPunctuation.test(result[index])) continue;
    const next = result[index + 1] ?? "";
    if (!next || /[\u3400-\u9fff]/u.test(next)) {
      result = result.slice(0, index);
      break;
    }
  }
  result = result.replace(/[.,;:!?，。；：！？、]+$/u, "");
  while (result.endsWith(")") && !hasBalancedParentheses(result)) {
    result = result.slice(0, -1);
  }
  return result;
}

function hasBalancedParentheses(value) {
  let depth = 0;
  for (const character of value) {
    if (character === "(") depth += 1;
    if (character === ")") depth -= 1;
    if (depth < 0) return false;
  }
  return depth === 0;
}

function hostnameOf(urlString) {
  try {
    return new URL(ensureAbsoluteUrl(extractShowUrl(urlString))).hostname.toLowerCase();
  } catch {
    return null;
  }
}

function matchesDomain(host, domain) {
  return host === domain || host.endsWith(`.${domain}`);
}

function isRedirectDomain(urlString) {
  const host = hostnameOf(urlString);
  return Boolean(host && REDIRECT_DOMAINS.some((domain) => matchesDomain(host, domain)));
}

function httpsUrlWithoutQuery(url) {
  return `https://${url.host}${url.pathname}`;
}

function httpsUrlWithoutHash(url) {
  return `https://${url.host}${url.pathname}${url.search}`;
}

function ensureAbsoluteUrl(urlString) {
  if (!urlString) {
    return urlString;
  }
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(urlString)) {
    return urlString;
  }
  if (urlString.startsWith("//")) {
    return `https:${urlString}`;
  }
  return `https://${urlString}`;
}

function normalizeFullWidthAscii(input) {
  return input
    .replace(/\u3000/g, " ")
    .replace(/[\uFF01-\uFF5E]/g, (char) => (
      String.fromCharCode(char.charCodeAt(0) - 0xFEE0)
    ));
}
