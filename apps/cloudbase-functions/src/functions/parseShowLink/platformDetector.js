export class UnsupportedPlatformError extends Error {
  constructor(url) {
    super(`Unsupported show link platform: ${url}`);
    this.name = "UnsupportedPlatformError";
    this.code = "UNSUPPORTED_PLATFORM";
  }
}

export function detectPlatform(urlString) {
  const lower = urlString.toLowerCase();

  if (lower.includes("damai.cn")) {
    return "damai";
  }

  if (lower.includes("showstart.com")) {
    return "showstart";
  }

  throw new UnsupportedPlatformError(urlString);
}

export function normalizeUrl(urlString) {
  const extractedUrl = extractShowUrl(urlString);
  const url = new URL(extractedUrl);
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

export function extractShowUrl(input) {
  const trimmed = normalizeFullWidthAscii(input).trim();
  const match = trimmed.match(/https?:\/\/[^\s【】"'<>]+/i);
  return match?.[0] ?? trimmed;
}

function normalizeFullWidthAscii(input) {
  return input
    .replace(/\u3000/g, " ")
    .replace(/[\uFF01-\uFF5E]/g, (char) => (
      String.fromCharCode(char.charCodeAt(0) - 0xFEE0)
    ));
}
