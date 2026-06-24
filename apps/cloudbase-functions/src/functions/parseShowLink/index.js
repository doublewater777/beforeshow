import { normalizeUrl, UnsupportedPlatformError } from "./platformDetector.js";
import { fetchDamaiDetail, parseDamaiDetail } from "./damaiParser.js";
import { fetchShowStartDetail, parseShowStartDetail } from "./showstartParser.js";

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

  throw new UnsupportedPlatformError(url);
}
