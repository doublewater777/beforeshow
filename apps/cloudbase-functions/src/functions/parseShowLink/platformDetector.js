export class UnsupportedPlatformError extends Error {
  constructor(url) {
    super(`Unsupported show link platform: ${url}`);
    this.name = "UnsupportedPlatformError";
    this.code = "UNSUPPORTED_PLATFORM";
  }
}

/**
 * 基于 hostname 严格识别平台，拒绝仿冒域名与查询参数里的关键字误报。
 * 只认官方域及其子域：damai.cn / *.damai.cn、showstart.com / *.showstart.com。
 */
export function detectPlatform(urlString) {
  const host = hostnameOf(urlString);
  if (!host) {
    throw new UnsupportedPlatformError(urlString);
  }

  if (host === "damai.cn" || host.endsWith(".damai.cn")) {
    return "damai";
  }

  if (host === "showstart.com" || host.endsWith(".showstart.com")) {
    return "showstart";
  }

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

  throw new UnsupportedPlatformError(urlString);
}

/**
 * 从粘贴文本中取出可解析的票务 URL。
 * 无协议的域名路径会补上 https://，与客户端来源 chip 行为一致。
 */
export function extractShowUrl(input) {
  const trimmed = normalizeFullWidthAscii(input).trim();
  const match = trimmed.match(/https?:\/\/[^\s【】"'<>]+/i);
  const raw = match?.[0] ?? trimmed;
  return ensureAbsoluteUrl(raw);
}

function hostnameOf(urlString) {
  try {
    return new URL(ensureAbsoluteUrl(extractShowUrl(urlString))).hostname.toLowerCase();
  } catch {
    return null;
  }
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
