const NETEASE_MUSIC_CONCERT_API = "https://st.music.163.com/api/concert/detail/v3";
const CHINA_TIME_ZONE = "Asia/Shanghai";

export async function fetchNetEaseMusicConcert({
  concertId,
  fetch = globalThis.fetch
} = {}) {
  const id = stringValue(concertId);
  if (!id) {
    throw new Error("NetEase Music concert ID is required");
  }

  const response = await fetch(NETEASE_MUSIC_CONCERT_API, {
    method: "POST",
    headers: {
      "Accept": "application/json, text/plain, */*",
      "Content-Type": "application/x-www-form-urlencoded",
      "Referer": `https://st.music.163.com/g/show/detail?concertId=${encodeURIComponent(id)}`,
      "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    },
    body: new URLSearchParams({ concertId: id }).toString()
  });

  if (!response || response.ok === false) {
    throw new Error(`NetEase Music concert request failed: ${response?.status ?? "unknown"}`);
  }

  let body;
  try {
    body = await response.json();
  } catch {
    throw new Error("NetEase Music API returned invalid JSON");
  }

  if (Number(body?.code) !== 200 || !body?.data) {
    throw new Error(`NetEase Music API error: ${body?.msg ?? "missing concert data"}`);
  }

  return body.data;
}

export function parseNetEaseMusicConcert(data) {
  const start = formatChinaDateTime(data?.startTime);
  const end = formatChinaDateTime(data?.endTime);
  const artists = Array.isArray(data?.artistInfoList)
    ? data.artistInfoList.map(parseArtist).filter((artist) => artist.name)
    : [];

  return {
    name: stringValue(data?.title),
    city: stringValue(data?.city).replace(/市$/, ""),
    date: start.date,
    startTime: start.time,
    ...(start.iso ? { startDateTime: start.iso } : {}),
    ...(end.date ? { endDate: end.date } : {}),
    ...(end.time ? { endTime: end.time } : {}),
    ...(end.iso ? { endDateTime: end.iso } : {}),
    timeZoneIdentifier: CHINA_TIME_ZONE,
    venueName: stringValue(data?.venue),
    venueAddr: stringValue(data?.address),
    artist: artists.map((artist) => artist.name).join(", "),
    coverImageURL: stringValue(data?.cover),
    artistAvatarURLs: artists.map((artist) => artist.avatar).filter(Boolean),
    priceRange: formatPriceRange(data?.minPrice, data?.maxPrice),
    source: "neteasemusic"
  };
}

function formatChinaDateTime(value) {
  const timestamp = Number(value);
  if (!Number.isFinite(timestamp) || timestamp <= 0) {
    return { date: "", time: "", iso: "" };
  }

  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: CHINA_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23"
  }).formatToParts(new Date(timestamp));
  const part = (type) => parts.find((item) => item.type === type)?.value ?? "";
  const date = `${part("year")}-${part("month")}-${part("day")}`;
  const time = `${part("hour")}:${part("minute")}`;
  const iso = `${date}T${time}:${part("second")}+08:00`;

  return { date, time, iso };
}

function parseArtist(value) {
  return {
    name: stringValue(value?.artistName ?? value?.name),
    avatar: stringValue(value?.img ?? value?.avatar ?? value?.picUrl ?? value?.image)
  };
}

function formatPriceRange(minValue, maxValue) {
  const min = stringValue(minValue);
  const max = stringValue(maxValue);
  if (min && max && min !== max) return `${min} - ${max}`;
  return min || max;
}

function stringValue(value) {
  if (typeof value === "string") return value.trim();
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  return "";
}
