const MAOYAN_PERFORMANCE_API = "https://wx.maoyan.com/maoyansh/myshow/ajax/v2/performance";

export async function fetchMaoyanPerformance({
  performanceId,
  fetch = globalThis.fetch
} = {}) {
  if (!performanceId) {
    throw new Error("Maoyan performance ID is required");
  }

  const id = String(performanceId);
  const params = new URLSearchParams({
    sellChannel: "7",
    performanceId: id
  });
  const url = `${MAOYAN_PERFORMANCE_API}/${encodeURIComponent(id)}?${params.toString()}`;
  const response = await fetch(url, {
    headers: {
      "Accept": "application/json, text/plain, */*",
      "Referer": "https://show.maoyan.com/",
      "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    }
  });

  if (!response || response.ok === false) {
    throw new Error(`Maoyan performance request failed: ${response?.status ?? "unknown"}`);
  }

  const body = await response.json();
  if (![0, 200].includes(Number(body?.code)) || !body?.data) {
    throw new Error(`Maoyan API error: ${body?.msg ?? "missing performance data"}`);
  }

  return body.data;
}

export function parseMaoyanPerformance(data) {
  const { date, startTime, endDate, endTime } = parseShowTimeRange(data?.showTimeRange ?? "");

  return {
    name: stringValue(data?.name),
    city: stringValue(data?.cityName).replace(/市$/, ""),
    date,
    startTime,
    ...(endDate ? { endDate } : {}),
    ...(endTime ? { endTime } : {}),
    venueName: stringValue(data?.shopName),
    venueAddr: stringValue(data?.address),
    artist: "",
    coverImageURL: stringValue(data?.posterUrl),
    artistAvatarURLs: [],
    priceRange: stringValue(data?.lowestPrice).replace(/^¥\s*/, ""),
    source: "maoyan"
  };
}

function parseShowTimeRange(value) {
  const text = stringValue(value);
  const dateMatches = [...text.matchAll(/(20\d{2})[.\/\-年](\d{1,2})[.\/\-月](\d{1,2})(?:日)?/g)];
  const timeMatches = [...text.matchAll(/(?:^|\D)(\d{1,2})[:：](\d{2})(?:\D|$)/g)];

  const date = dateMatches[0] ? formatDate(dateMatches[0]) : "";
  const endDate = dateMatches[1] ? formatDate(dateMatches[1]) : "";
  const startTime = timeMatches[0] ? formatTime(timeMatches[0]) : "";
  const endTime = timeMatches[1] ? formatTime(timeMatches[1]) : "";

  return { date, startTime, endDate, endTime };
}

function formatDate(match) {
  return `${match[1]}-${match[2].padStart(2, "0")}-${match[3].padStart(2, "0")}`;
}

function formatTime(match) {
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (hour > 23 || minute > 59) return "";
  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}

function stringValue(value) {
  if (typeof value === "string") return value.trim();
  if (typeof value === "number") return String(value);
  return "";
}
