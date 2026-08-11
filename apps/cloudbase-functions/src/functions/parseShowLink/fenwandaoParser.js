const FENWANDAO_PROJECT_API =
  "https://mobile.livelab.com.cn/api/performance/app/project/h5/get_project_info";

export async function fetchFenwandaoProjectInfo({
  projectId,
  fetch = globalThis.fetch
} = {}) {
  if (!projectId) {
    throw new Error("Fenwandao project ID is required");
  }

  const id = String(projectId);
  const params = new URLSearchParams({ project_id: id });
  const url = `${FENWANDAO_PROJECT_API}?${params.toString()}`;
  const response = await fetch(url, {
    headers: {
      "Accept": "application/json, text/plain, */*",
      "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    }
  });

  if (!response || response.ok === false) {
    throw new Error(`Fenwandao project request failed: ${response?.status ?? "unknown"}`);
  }

  const body = await response.json();
  if (Number(body?.code) !== 10000 || !body?.data) {
    throw new Error(`Fenwandao API error: ${body?.msg ?? "missing project data"}`);
  }

  return body.data;
}

export function parseFenwandaoProject(data) {
  const { startTime, endTime } = parseTimeDisplay(data?.timeDisplay);

  return {
    name: stringValue(data?.projectName) || stringValue(data?.nameDisplay),
    city: (stringValue(data?.projectCity) || stringValue(data?.venueInfo?.city)).replace(/市$/, ""),
    date: formatDate(stringValue(data?.projectStartDate)),
    startTime,
    ...(formatDate(stringValue(data?.projectEndDate)) ? { endDate: formatDate(stringValue(data?.projectEndDate)) } : {}),
    ...(endTime ? { endTime } : {}),
    venueName: stringValue(data?.venueInfo?.name),
    venueAddr: stringValue(data?.venueInfo?.address),
    artist: findArtist(data?.watchNotices),
    coverImageURL: stringValue(data?.poster),
    artistAvatarURLs: [],
    priceRange: formatPriceRange(data?.lowPrice, data?.highPrice),
    source: "fenwandao"
  };
}

function findArtist(notices) {
  if (!Array.isArray(notices)) return "";
  const artists = notices.find((notice) =>
    notice?.tag === "artists" || notice?.name === "主要演员"
  );
  return stringValue(artists?.content);
}

function parseTimeDisplay(value) {
  const text = stringValue(value);
  const timeMatches = [...text.matchAll(/(?:^|\D)(\d{1,2})[:：](\d{2})(?:\D|$)/g)];
  const startTime = timeMatches[0] ? formatTime(timeMatches[0]) : "";
  const endTime = timeMatches[1] ? formatTime(timeMatches[1]) : "";
  return { startTime, endTime };
}

function formatDate(value) {
  const text = stringValue(value);
  const match = text.match(/(20\d{2})[.\/年\-](\d{1,2})[.\/月\-](\d{1,2})(?:日)?/);
  if (!match) return "";
  return `${match[1]}-${match[2].padStart(2, "0")}-${match[3].padStart(2, "0")}`;
}

function formatTime(match) {
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (hour > 23 || minute > 59) return "";
  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}

function formatPriceRange(low, high) {
  const min = formatPrice(low);
  const max = formatPrice(high);
  if (min && max && min !== max) return `${min} - ${max}`;
  return min || max;
}

function formatPrice(value) {
  const text = stringValue(value).replace(/^¥\s*/, "");
  if (!text) return "";
  return `${Number(text)}`;
}

function stringValue(value) {
  if (typeof value === "string") return value.trim();
  if (typeof value === "number") return String(value);
  return "";
}