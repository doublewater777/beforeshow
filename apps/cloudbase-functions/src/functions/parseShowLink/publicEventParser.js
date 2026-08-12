const EVENT_TYPE_PATTERN = /event|musicevent|festival|concert/i;
import { formatDateParts, formatTimeParts } from "./dateTime.js";

const NAME_KEYS = [
  "name",
  "title",
  "activityName",
  "projectName",
  "showName",
  "eventName",
  "itemName"
];

const START_KEYS = [
  "startDate",
  "showTime",
  "eventTime",
  "showDate",
  "date",
  "startTime"
];

const END_KEYS = ["endDate", "endTime"];
const CITY_KEYS = ["city", "cityName", "addressLocality"];
const VENUE_NAME_KEYS = ["venueName", "siteName"];
const VENUE_ADDRESS_KEYS = ["venueAddr", "venueAddress", "siteAddress"];
const IMAGE_KEYS = ["coverImageURL", "coverImage", "poster", "avatar", "image"];
const ARTIST_KEYS = ["performer", "artists", "artist", "lineup", "sessionUserInfos"];

export async function fetchPublicEventPage({ url, fetch = globalThis.fetch } = {}) {
  const response = await fetch(url, {
    headers: {
      "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
      "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
      "Accept-Language": "zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7"
    }
  });

  if (!response || response.ok === false) {
    throw new Error(`Public event page request failed: ${response?.status ?? "unknown"}`);
  }

  return response.text();
}

export async function fetchAndParsePublicEvent({
  url,
  source,
  fetch = globalThis.fetch
} = {}) {
  const html = await fetchPublicEventPage({ url, fetch });
  return parsePublicEventPage(html, { source });
}

export function parsePublicEventPage(html, { source } = {}) {
  if (typeof html !== "string" || html.trim().length === 0) {
    throw new Error("Public event page is empty");
  }

  const jsonCandidates = extractJsonScripts(html);
  const candidate = bestEventCandidate(jsonCandidates);
  const meta = extractMetaTags(html);

  if (!candidate && Object.keys(meta).length === 0) {
    throw new Error("No structured event data found");
  }

  const draft = candidate
    ? draftFromCandidate(candidate, source)
    : draftFromMeta(meta, source);

  if (!draft.name || !draft.date) {
    throw new Error("Event page is missing a name or date");
  }

  return draft;
}

function extractJsonScripts(html) {
  const values = [];
  const scriptPattern = /<script\b([^>]*)>([\s\S]*?)<\/script>/gi;
  let match;

  while ((match = scriptPattern.exec(html)) !== null) {
    const attributes = match[1] ?? "";
    const type = attributeValue(attributes, "type")?.toLowerCase() ?? "";
    const id = attributeValue(attributes, "id")?.toLowerCase() ?? "";
    const body = decodeHtmlEntities((match[2] ?? "").trim());

    const looksLikeJson = type.includes("json")
      || id === "__next_data__"
      || id === "__nuxt_data__";

    if (!looksLikeJson || !body) {
      continue;
    }

    const parsed = safeJsonParse(body);
    if (parsed !== undefined) {
      values.push(parsed);
    }
  }

  return values;
}

function safeJsonParse(value) {
  const cleaned = value
    .replace(/^<!--/, "")
    .replace(/-->$/, "")
    .trim();

  try {
    return JSON.parse(cleaned);
  } catch {
    return undefined;
  }
}

function bestEventCandidate(values) {
  let best = null;
  let bestScore = -1;

  for (const value of values) {
    walkJson(value, (object) => {
      const score = eventCandidateScore(object);
      if (score > bestScore) {
        best = object;
        bestScore = score;
      }
    });
  }

  return bestScore >= 8 ? best : null;
}

function walkJson(value, visit) {
  if (Array.isArray(value)) {
    for (const item of value) {
      walkJson(item, visit);
    }
    return;
  }

  if (!isPlainObject(value)) {
    return;
  }

  visit(value);
  for (const nested of Object.values(value)) {
    walkJson(nested, visit);
  }
}

function eventCandidateScore(object) {
  let score = 0;
  const type = arrayify(object["@type"]).join(" ");

  if (EVENT_TYPE_PATTERN.test(type)) score += 8;
  if (firstString(object, NAME_KEYS)) score += 5;
  if (firstTemporalValue(object, START_KEYS) !== undefined) score += 5;
  if (object.location || object.venue || object.site || firstString(object, VENUE_NAME_KEYS)) score += 2;
  if (firstValue(object, IMAGE_KEYS) !== undefined) score += 1;
  if (firstValue(object, ARTIST_KEYS) !== undefined) score += 1;

  return score;
}

function draftFromCandidate(object, source) {
  const location = firstObject(object.location, object.venue, object.site);
  const address = firstObject(location?.address, object.address);
  const start = parseDateTime(firstTemporalValue(object, START_KEYS));
  const end = parseDateTime(firstTemporalValue(object, END_KEYS));
  const timeZoneIdentifier = firstString(object, ["timeZone", "timezone"]);
  const inlineRangeEnd = parseSecondDateTime(firstTemporalValue(object, START_KEYS));

  if (!start.time) {
    const explicitClock = firstClockValue(object, ["startTime", "time"]);
    if (explicitClock) start.time = explicitClock;
  }

  const finalEnd = end.date || end.time ? end : inlineRangeEnd;
  const artists = extractArtists(firstValue(object, ARTIST_KEYS));
  const coverImageURL = extractImage(firstValue(object, IMAGE_KEYS));
  const artistAvatarURLs = uniqueStrings(artists.flatMap((artist) => artist.images));

  const venueName = firstString(object, VENUE_NAME_KEYS)
    || stringValue(location?.name)
    || stringValue(location?.venueName)
    || "";

  const city = firstString(object, CITY_KEYS)
    || firstString(location ?? {}, CITY_KEYS)
    || firstString(address ?? {}, CITY_KEYS)
    || "";

  const venueAddr = firstString(object, VENUE_ADDRESS_KEYS)
    || addressString(location?.address)
    || addressString(object.address)
    || stringValue(location?.address)
    || "";

  return {
    name: firstString(object, NAME_KEYS) ?? "",
    city,
    date: start.date ?? "",
    startTime: start.time ?? "",
    ...(start.dateTime ? { startDateTime: start.dateTime } : {}),
    ...(timeZoneIdentifier ? { timeZoneIdentifier } : {}),
    ...(finalEnd.date ? { endDate: finalEnd.date } : {}),
    ...(finalEnd.time ? { endTime: finalEnd.time } : {}),
    ...(finalEnd.dateTime ? { endDateTime: finalEnd.dateTime } : {}),
    venueName,
    venueAddr,
    artist: artists.map((artist) => artist.name).filter(Boolean).join(", "),
    coverImageURL,
    artistAvatarURLs,
    priceRange: extractPriceRange(object),
    source: source ?? "public"
  };
}

function draftFromMeta(meta, source) {
  const start = parseDateTime(meta["event:start_time"] ?? meta["event:startdate"]);
  const end = parseDateTime(meta["event:end_time"] ?? meta["event:enddate"]);
  const title = meta["og:title"] ?? meta["twitter:title"] ?? meta.title ?? "";

  return {
    name: cleanTitle(title),
    city: meta["event:location:locality"] ?? "",
    date: start.date ?? "",
    startTime: start.time ?? "",
    ...(start.dateTime ? { startDateTime: start.dateTime } : {}),
    ...(end.date ? { endDate: end.date } : {}),
    ...(end.time ? { endTime: end.time } : {}),
    ...(end.dateTime ? { endDateTime: end.dateTime } : {}),
    venueName: meta["event:location"] ?? "",
    venueAddr: meta["event:location:address"] ?? "",
    artist: "",
    coverImageURL: meta["og:image"] ?? meta["twitter:image"] ?? "",
    artistAvatarURLs: [],
    priceRange: "",
    source: source ?? "public"
  };
}

function extractMetaTags(html) {
  const meta = {};
  const tagPattern = /<meta\b[^>]*>/gi;
  let match;

  while ((match = tagPattern.exec(html)) !== null) {
    const tag = match[0];
    const key = attributeValue(tag, "property") ?? attributeValue(tag, "name");
    const content = attributeValue(tag, "content");
    if (key && content) {
      meta[key.toLowerCase()] = decodeHtmlEntities(content).trim();
    }
  }

  const titleMatch = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  if (titleMatch?.[1]) {
    meta.title = decodeHtmlEntities(titleMatch[1]).trim();
  }

  return meta;
}

function attributeValue(text, name) {
  const quoted = text.match(new RegExp(`${name}\\s*=\\s*["']([^"']*)["']`, "i"));
  if (quoted) return quoted[1];
  const unquoted = text.match(new RegExp(`${name}\\s*=\\s*([^\\s>]+)`, "i"));
  return unquoted?.[1];
}

function parseDateTime(value) {
  const text = temporalString(value);
  if (!text) return { date: null, time: null };

  const dateMatch = text.match(/(\d{4})[.\/\-年](\d{1,2})[.\/\-月](\d{1,2})(?:日)?/);
  const timeMatch = text.match(/(?:T|\s|周[^\s]*\s*)(\d{1,2})[:：](\d{2})/)
    ?? text.match(/(\d{1,2})[:：](\d{2})/);

  const date = dateMatch
    ? formatDateParts(dateMatch[1], dateMatch[2], dateMatch[3])
    : null;
  const time = timeMatch ? formatTimeParts(timeMatch[1], timeMatch[2]) : null;
  const dateTime = isoDateTime(text, date, time);

  return { date, time, dateTime };
}

function parseSecondDateTime(value) {
  const text = temporalString(value);
  if (!text) return { date: null, time: null };

  const datePattern = /(\d{4})[.\/\-年](\d{1,2})[.\/\-月](\d{1,2})(?:日)?/g;
  const matches = [...text.matchAll(datePattern)];
  if (matches.length < 2) return { date: null, time: null };

  const second = matches[1];
  const tail = text.slice(second.index ?? 0);
  const time = tail.match(/(\d{1,2})[:：](\d{2})/);
  return {
    date: formatDateParts(second[1], second[2], second[3]),
    time: time ? formatTimeParts(time[1], time[2]) : null,
    dateTime: null
  };
}

function isoDateTime(value, date, time) {
  if (!date || !time) return null;

  const match = String(value).match(
    /^(?:\s*)(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?(?:\.(\d{1,9}))?(Z|[+-]\d{2}:\d{2})(?:\s*)$/
  );
  if (!match || date !== `${match[1]}-${match[2]}-${match[3]}`
    || time !== `${match[4]}:${match[5]}`) {
    return null;
  }

  const offset = match[8];
  if (offset !== "Z") {
    const offsetHour = Number(offset.slice(1, 3));
    const offsetMinute = Number(offset.slice(4, 6));
    if (offsetHour > 23 || offsetMinute > 59) return null;
  }

  const seconds = match[6] ?? "00";
  if (Number(seconds) > 59) return null;
  const fraction = match[7] ? `.${match[7]}` : "";
  return `${date}T${time}:${seconds}${fraction}${offset}`;
}

function firstClockValue(object, keys) {
  for (const key of keys) {
    const value = object?.[key];
    const text = temporalString(value);
    if (!text) continue;
    const match = text.match(/(\d{1,2})[:：](\d{2})/);
    const formatted = match ? formatTimeParts(match[1], match[2]) : null;
    if (formatted) return formatted;
  }
  return null;
}

function temporalString(value) {
  if (typeof value === "string" || typeof value === "number") {
    return String(value);
  }
  if (isPlainObject(value)) {
    return stringValue(value.value) || stringValue(value.text) || "";
  }
  return "";
}

function firstTemporalValue(object, keys) {
  for (const key of keys) {
    if (object?.[key] !== undefined && object?.[key] !== null && object?.[key] !== "") {
      return object[key];
    }
  }
  return undefined;
}

function firstString(object, keys) {
  for (const key of keys) {
    const value = stringValue(object?.[key]);
    if (value) return value;
  }
  return null;
}

function firstValue(object, keys) {
  for (const key of keys) {
    const value = object?.[key];
    if (value !== undefined && value !== null && value !== "") return value;
  }
  return undefined;
}

function firstObject(...values) {
  return values.find((value) => isPlainObject(value)) ?? null;
}

function stringValue(value) {
  if (typeof value === "string") return decodeHtmlEntities(value).trim();
  if (typeof value === "number") return String(value);
  return "";
}

function addressString(value) {
  if (typeof value === "string") return stringValue(value);
  if (!isPlainObject(value)) return "";

  const parts = [
    value.streetAddress,
    value.addressLocality,
    value.addressRegion,
    value.postalCode,
    value.addressCountry?.name ?? value.addressCountry
  ].map(stringValue).filter(Boolean);

  return uniqueStrings(parts).join(", ");
}

function extractArtists(value) {
  const found = [];

  function visit(item) {
    if (Array.isArray(item)) {
      item.forEach(visit);
      return;
    }
    if (typeof item === "string") {
      const name = stringValue(item);
      if (name) found.push({ name, images: [] });
      return;
    }
    if (!isPlainObject(item)) return;

    const directName = firstString(item, ["name", "artistName", "userName", "nickname"]);
    if (directName) {
      found.push({
        name: directName,
        images: uniqueStrings([
          extractImage(item.image),
          extractImage(item.avatar),
          extractImage(item.picUrl),
          extractImage(item.avatarURL)
        ])
      });
    }

    for (const key of ["userInfos", "artists", "performers", "lineup", "items"]) {
      if (item[key] !== undefined) visit(item[key]);
    }
  }

  visit(value);

  const deduped = new Map();
  for (const artist of found) {
    if (!deduped.has(artist.name)) {
      deduped.set(artist.name, artist);
    }
  }
  return [...deduped.values()];
}

function extractImage(value) {
  if (typeof value === "string") return stringValue(value);
  if (Array.isArray(value)) {
    for (const item of value) {
      const image = extractImage(item);
      if (image) return image;
    }
    return "";
  }
  if (isPlainObject(value)) {
    return firstString(value, ["url", "contentUrl", "src", "picUrl", "avatar"] ) ?? "";
  }
  return "";
}

function extractPriceRange(object) {
  const explicit = firstString(object, ["priceRange", "price"]);
  if (explicit) return explicit.replace(/^¥\s*/, "");

  const offers = Array.isArray(object.offers) ? object.offers[0] : object.offers;
  if (!isPlainObject(offers)) return "";

  const currency = stringValue(offers.priceCurrency);
  const low = stringValue(offers.lowPrice ?? offers.price);
  const high = stringValue(offers.highPrice);
  const amount = low && high && low !== high ? `${low}-${high}` : low || high;
  if (!amount) return "";
  return currency ? `${currency} ${amount}` : amount;
}

function arrayify(value) {
  if (Array.isArray(value)) return value;
  return value === undefined || value === null ? [] : [value];
}

function uniqueStrings(values) {
  return [...new Set(values.map(stringValue).filter(Boolean))];
}

function cleanTitle(value) {
  return stringValue(value)
    .replace(/\s*[|｜-]\s*(Ticketmaster|DICE|AXS|猫眼|票星球|纷玩岛).*$/i, "")
    .trim();
}

function decodeHtmlEntities(value) {
  return String(value)
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
