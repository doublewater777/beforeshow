const PIAOXINGQIU_API_ORIGIN = "https://e.piaoxingqiu.com";
const PIAOXINGQIU_API_VERSION = "4.64.11";
const PIAOXINGQIU_USER_AGENT =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
  "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
  "Version/17.0 Mobile/15E148 Safari/604.1";

export async function fetchAndParsePiaoxingqiu({
  eventId,
  canonicalUrl,
  fetch = globalThis.fetch,
  cityId = ""
} = {}) {
  const showId = stringValue(eventId);
  if (!showId) {
    throw new Error("Piaoxingqiu show ID is required");
  }

  const url = buildPiaoxingqiuStaticUrl({ showId, cityId });
  const response = await fetch(url, {
    headers: {
      Accept: "application/json, text/plain, */*",
      Origin: PIAOXINGQIU_API_ORIGIN,
      Referer: canonicalUrl || `${PIAOXINGQIU_API_ORIGIN}/`,
      "User-Agent": PIAOXINGQIU_USER_AGENT
    }
  });

  const status = Number(response?.status);
  if (
    !response
    || response.ok === false
    || (Number.isFinite(status) && (status < 200 || status >= 300))
  ) {
    throw new Error(
      `Piaoxingqiu API request failed: ${response?.status ?? "unknown"}`
    );
  }

  let body;
  try {
    body = await response.json();
  } catch {
    throw new Error("Piaoxingqiu API returned invalid JSON");
  }

  if (Number(body?.data?.rsCode) !== 200 || !body?.data?.basicInfo) {
    throw new Error(
      `Piaoxingqiu API error: ${body?.comments || body?.result || "missing show data"}`
    );
  }

  return parsePiaoxingqiuStatic(body);
}

export function buildPiaoxingqiuStaticUrl({ showId, cityId = "" } = {}) {
  const id = stringValue(showId);
  if (!id) {
    throw new Error("Piaoxingqiu show ID is required");
  }

  const params = new URLSearchParams({
    currency: "CNY",
    lang: "zh",
    terminalSrc: "WEB",
    utcOffset: "480",
    ver: PIAOXINGQIU_API_VERSION,
    src: "WEB",
    source: "FROM_QUICK_ORDER"
  });
  if (stringValue(cityId)) {
    params.set("cityId", stringValue(cityId));
  }

  return `${PIAOXINGQIU_API_ORIGIN}/cyy_gatewayapi/show/pub/v5/show/` +
    `${encodeURIComponent(id)}/static?${params.toString()}`;
}

export function parsePiaoxingqiuStatic(body) {
  const basicInfo = body?.data?.basicInfo;
  if (!basicInfo) {
    throw new Error("Piaoxingqiu API response is missing basicInfo");
  }

  const { date, startTime } = parseShowDate(basicInfo.showDate);
  const artist = findObservationValue(
    body?.data?.descInfo?.observationInstructions,
    "MAIN_ACTOR"
  );

  return {
    name: stringValue(basicInfo.showName),
    city: stringValue(basicInfo.cityName).replace(/市$/, ""),
    date,
    startTime,
    venueName: stringValue(basicInfo.venueName),
    venueAddr: stringValue(basicInfo.venueAddress),
    artist,
    coverImageURL: stringValue(basicInfo.posterUrl),
    artistAvatarURLs: [],
    priceRange: formatPriceRange(
      basicInfo.minOriginalPriceInfo,
      basicInfo.maxOriginalPriceInfo
    ),
    source: "piaoxingqiu"
  };
}

function parseShowDate(value) {
  const text = stringValue(value);
  const dateMatch = text.match(
    /(20\d{2})[.\-/年](\d{1,2})[.\-/月](\d{1,2})(?:日)?/
  );
  if (!dateMatch) {
    return { date: "", startTime: "" };
  }

  const year = Number(dateMatch[1]);
  const month = Number(dateMatch[2]);
  const day = Number(dateMatch[3]);
  const parsedDate = new Date(Date.UTC(year, month - 1, day));
  if (
    year < 2000
    || year > 2100
    || parsedDate.getUTCFullYear() !== year
    || parsedDate.getUTCMonth() !== month - 1
    || parsedDate.getUTCDate() !== day
  ) {
    return { date: "", startTime: "" };
  }

  const timeText = text.slice((dateMatch.index ?? 0) + dateMatch[0].length);
  const timeMatch = timeText.match(/(?:^|\s|T)(\d{1,2})[:：](\d{2})/);
  if (!timeMatch) {
    return {
      date: `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`,
      startTime: ""
    };
  }

  const hour = Number(timeMatch[1]);
  const minute = Number(timeMatch[2]);
  if (hour > 23 || minute > 59) {
    return { date: "", startTime: "" };
  }

  return {
    date: `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`,
    startTime: `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`
  };
}

function findObservationValue(instructions, key) {
  if (!Array.isArray(instructions)) return "";
  const item = instructions.find((instruction) => instruction?.key === key);
  return stringValue(item?.value);
}

function formatPriceRange(minInfo, maxInfo) {
  const min = formatPrice(minInfo);
  const max = formatPrice(maxInfo);
  if (min && max && min !== max) return `${min} - ${max}`;
  return min || max;
}

function formatPrice(info) {
  if (!info || typeof info !== "object") return "";

  const yuan = stringValue(info.yuanNum);
  const cents = stringValue(info.centNum);
  if (!yuan && !cents) return "";
  if (!cents || /^0+$/.test(cents)) return yuan;

  return `${yuan || "0"}.${cents.padStart(2, "0").slice(-2)}`;
}

function stringValue(value) {
  if (typeof value === "string") return value.trim();
  if (typeof value === "number") return String(value);
  return "";
}
