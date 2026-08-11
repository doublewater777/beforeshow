import { normalizeUrl, UnsupportedPlatformError } from "./platformDetector.js";
import { fetchDamaiDetail, parseDamaiDetail } from "./damaiParser.js";
import { fetchShowStartDetail, parseShowStartDetail } from "./showstartParser.js";
import { fetchMaoyanPerformance, parseMaoyanPerformance } from "./maoyanParser.js";
import { fetchAndParseTicketPage } from "./ticketPageParser.js";
import { fetchAndParseLiveNationPage } from "./liveNationParser.js";
import { fetchAndParsePiaoxingqiu } from "./piaoxingqiuParser.js";
import { fetchFenwandaoProjectInfo, parseFenwandaoProject } from "./fenwandaoParser.js";

const PUBLIC_PAGE_PLATFORMS = new Set([
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

  if (normalized.platform === "maoyan") {
    if (!normalized.eventId) {
      throw new UnsupportedPlatformError(url);
    }
    const detail = await fetchMaoyanPerformance({
      performanceId: normalized.eventId,
      fetch: options.fetch
    });
    return parseMaoyanPerformance(detail);
  }

  if (normalized.platform === "livenation") {
    return fetchAndParseLiveNationPage({
      url: normalized.canonicalUrl,
      fetch: options.fetch
    });
  }

  if (normalized.platform === "ticketmaster") {
    return fetchAndParseTicketPage({
      url: normalized.canonicalUrl,
      source: normalized.platform,
      fetch: options.fetch
    });
  }

  if (normalized.platform === "piaoxingqiu" && normalized.eventId) {
    return fetchAndParsePiaoxingqiu({
      eventId: normalized.eventId,
      canonicalUrl: normalized.canonicalUrl,
      fetch: options.fetch
    });
  }

  if (normalized.platform === "fenwandao" && normalized.eventId) {
    const detail = await fetchFenwandaoProjectInfo({
      projectId: normalized.eventId,
      fetch: options.fetch
    });
    return parseFenwandaoProject(detail);
  }

  if (normalized.platform === "piaoxingqiu" || PUBLIC_PAGE_PLATFORMS.has(normalized.platform)) {
    return fetchAndParseTicketPage({
      url: normalized.canonicalUrl,
      source: normalized.platform,
      fetch: options.fetch
    });
  }

  throw new UnsupportedPlatformError(url);
}
