import { normalizeUrl, UnsupportedPlatformError } from "./platformDetector.js";
import { fetchDamaiDetail, parseDamaiDetail } from "./damaiParser.js";
import { fetchShowStartDetail, parseShowStartDetail } from "./showstartParser.js";
import { fetchAndParsePublicEvent } from "./publicEventParser.js";

const PUBLIC_PAGE_PLATFORMS = new Set([
  "maoyan",
  "piaoxingqiu",
  "fenwandao",
  "ticketmaster",
  "dice",
  "axs"
]);

export { UnsupportedPlatformError };

export async function parseShowLink(url, options = {}) {
  const normalized = normalizeUrl(url);

  if (normalized.platform === "damai") {
    const detail = await fetchDamaiDetail({
      itemId: normalized.itemId,
      fetch: options.fetch
    });
    return parseDamaiDetail(detail);
  }

  if (normalized.platform === "showstart") {
    const detail = await fetchShowStartDetail({
      activityId: normalized.activityId,
      fetch: options.fetch
    });
    return parseShowStartDetail(detail);
  }

  if (PUBLIC_PAGE_PLATFORMS.has(normalized.platform)) {
    return fetchAndParsePublicEvent({
      url: normalized.canonicalUrl,
      source: normalized.platform,
      fetch: options.fetch
    });
  }

  throw new UnsupportedPlatformError(url);
}
