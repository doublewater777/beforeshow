import crypto from "node:crypto";

export const DAMAI_APP_KEY = "12574478";
export const DAMAI_API = "mtop.damai.item.detail.getdetail";
export const DAMAI_API_VERSION = "1.0";

export function computeMtopSign({ token, t, appKey, data }) {
  const signString = `${token}&${t}&${appKey}&${data}`;
  return crypto.createHash("md5").update(signString).digest("hex");
}

export async function fetchMtopToken({ fetch = globalThis.fetch } = {}) {
  const url = buildMtopUrl({
    token: "",
    t: Date.now().toString(),
    sign: "a".repeat(32),
    data: buildMtopData("1054603723374")
  });

  const response = await fetch(url, {
    headers: {
      "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    }
  });

  const setCookie = response.headers.get("set-cookie") ?? "";
  const match = setCookie.match(/_m_h5_tk=([a-f0-9]+)_/);

  if (!match) {
    throw new Error("Failed to obtain Damai mtop token");
  }

  return {
    token: match[1],
    cookies: extractRelevantCookies(setCookie)
  };
}

export async function fetchDamaiDetail({ itemId, fetch = globalThis.fetch } = {}) {
  const { token, cookies } = await fetchMtopToken({ fetch });
  const t = Date.now().toString();
  const data = buildMtopData(itemId);
  const sign = computeMtopSign({ token, t, appKey: DAMAI_APP_KEY, data });

  const url = buildMtopUrl({ token, t, sign, data });
  const response = await fetch(url, {
    headers: {
      "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
      "Cookie": cookies
    }
  });

  if (!response.ok) {
    throw new Error(`Damai detail request failed: ${response.status}`);
  }

  const body = await response.text();
  const json = JSON.parse(body);

  if (json.ret && json.ret.some((r) => String(r).includes("FAIL"))) {
    throw new Error(`Damai API error: ${json.ret.join(", ")}`);
  }

  return json.data;
}

function extractRelevantCookies(setCookie) {
  const cookies = [];
  const relevant = ["_m_h5_tk", "_m_h5_tk_enc"];

  for (const name of relevant) {
    const match = setCookie.match(new RegExp(`${name}=[^;]+`));
    if (match) {
      cookies.push(match[0]);
    }
  }

  return cookies.join("; ");
}

export function parseDamaiDetail(data) {
  const item = data.item ?? {};
  const venue = data.venue ?? {};
  const price = data.price ?? {};
  const guide = data.guide ?? {};
  const artists = guide.artists ?? [];
  const coverImageURL = item.itemPics?.itemPicList?.[0]?.picUrl ?? "";
  const artistAvatarURLs = artists
    .map((artist) => artist.picUrl)
    .filter((url) => typeof url === "string" && url.trim().length > 0);

  const title = item.itemName ?? "";
  const cleanName = title
    .replace(/^【[^】]+】/, "")
    .replace(/【网上订票】.*$/, "")
    .replace(/- 大麦网$/, "")
    .trim();

  const city = (item.cityName ?? "").replace(/市$/, "");
  const venueName = venue.venueName ?? "";
  const venueAddr = venue.venueAddr ?? "";

  const { date, startTime } = parseShowTime(item.showTime ?? "");
  const type = mapDamaiType(guide.guideCat ?? "");
  const artist = artists.map((a) => a.name).join(", ") || "";

  return {
    name: cleanName,
    city,
    date,
    startTime,
    venueName,
    venueAddr,
    artist,
    coverImageURL,
    artistAvatarURLs,
    priceRange: price.range ?? "",
    type,
    source: "damai",
    rawType: guide.guideCat ?? ""
  };
}

function buildMtopData(itemId) {
  return JSON.stringify({
    itemId,
    platform: "8",
    comboChannel: "2",
    dmChannel: "damai@damaih5_h5"
  });
}

function buildMtopUrl({ token, t, sign, data }) {
  const baseUrl = "https://mtop.damai.cn/h5/mtop.damai.item.detail.getdetail/1.0/";
  const params = new URLSearchParams({
    jsv: "2.7.5",
    appKey: DAMAI_APP_KEY,
    t,
    sign,
    api: DAMAI_API,
    v: DAMAI_API_VERSION,
    H5Request: "true",
    type: "json",
    timeout: "10000",
    dataType: "json",
    valueType: "string",
    data
  });

  return `${baseUrl}?${params.toString()}`;
}

function parseShowTime(showTime) {
  if (!showTime) {
    return { date: "", startTime: "" };
  }

  const match = showTime.match(/(\d{4})\.(\d{1,2})\.(\d{1,2})(?:[^\d]*)(\d{1,2}):(\d{2})?/);
  if (match) {
    const [, year, month, day, hour, minute] = match;
    return {
      date: `${year}-${month.padStart(2, "0")}-${day.padStart(2, "0")}`,
      startTime: hour && minute ? `${hour.padStart(2, "0")}:${minute}` : ""
    };
  }

  const dateOnlyMatch = showTime.match(/(\d{4})\.(\d{1,2})\.(\d{1,2})/);
  if (dateOnlyMatch) {
    const [, year, month, day] = dateOnlyMatch;
    return {
      date: `${year}-${month.padStart(2, "0")}-${day.padStart(2, "0")}`,
      startTime: ""
    };
  }

  return { date: "", startTime: "" };
}

function mapDamaiType(guideCat) {
  const lower = guideCat.toLowerCase();

  if (lower.includes("音乐节")) {
    return "musicFestival";
  }

  if (lower.includes("livehouse")) {
    return "livehouse";
  }

  return "concert";
}
