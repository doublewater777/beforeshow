import {
  fetchPublicEventPage,
  parsePublicEventPage
} from "./publicEventParser.js";

const ENGLISH_MONTHS = new Map([
  ["jan", 1], ["january", 1],
  ["feb", 2], ["february", 2],
  ["mar", 3], ["march", 3],
  ["apr", 4], ["april", 4],
  ["may", 5],
  ["jun", 6], ["june", 6],
  ["jul", 7], ["july", 7],
  ["aug", 8], ["august", 8],
  ["sep", 9], ["sept", 9], ["september", 9],
  ["oct", 10], ["october", 10],
  ["nov", 11], ["november", 11],
  ["dec", 12], ["december", 12]
]);

const CHINESE_MONTHS = new Map([
  ["一", 1], ["二", 2], ["三", 3], ["四", 4], ["五", 5], ["六", 6],
  ["七", 7], ["八", 8], ["九", 9], ["十", 10], ["十一", 11], ["十二", 12]
]);

export async function fetchAndParseLiveNationPage({
  url,
  fetch = globalThis.fetch
} = {}) {
  const html = await fetchPublicEventPage({ url, fetch });

  try {
    return parsePublicEventPage(html, { source: "livenation" });
  } catch (structuredError) {
    try {
      return parseLiveNationVisiblePage(html);
    } catch (visibleError) {
      const error = new Error(`Unable to parse Live Nation event page: ${visibleError.message}`);
      error.cause = structuredError;
      throw error;
    }
  }
}

export function parseLiveNationVisiblePage(html) {
  if (typeof html !== "string" || html.trim().length === 0) {
    throw new Error("Live Nation page is empty");
  }

  const lines = visibleLines(html);
  const name = cleanTitle(tagText(html, "h1") || tagText(html, "title") || lines[0] || "");
  // The <title> line may embed a date (some US pages carry the year only there),
  // so resolve the date from any line. Venue, however, sits right after the h1,
  // so locate content relative to the event title rather than the date line.
  const nameIndex = name ? lines.findIndex((line) => line === name) : -1;
  const contentStart = nameIndex >= 0 ? nameIndex + 1 : 1;
  const dateLineIndex = lines.findIndex((line) => parseDateRange(line).date);
  if (!name || dateLineIndex < 0) {
    throw new Error("Live Nation page is missing a name or date");
  }

  const dateLine = lines[dateLineIndex];
  const dateRange = parseDateRange(dateLine);
  const startTime = parseClock(dateLine)
    ?? parseClock(lines[dateLineIndex + 1] ?? "")
    ?? "";
  const venue = parseVenue(lines, contentStart, name);
  const artist = fieldFollowingLabel(lines, ["Lineup", "主要演出", "该演出中的艺人"]);

  return {
    name,
    city: venue.city,
    date: dateRange.date,
    startTime,
    ...(dateRange.endDate ? { endDate: dateRange.endDate } : {}),
    venueName: venue.name,
    venueAddr: "",
    artist,
    coverImageURL: metaContent(html, "og:image"),
    artistAvatarURLs: [],
    priceRange: "",
    source: "livenation"
  };
}

function visibleLines(html) {
  return decodeHtmlEntities(
    html
      .replace(/<script\b[\s\S]*?<\/script>/gi, " ")
      .replace(/<style\b[\s\S]*?<\/style>/gi, " ")
      .replace(/<noscript\b[\s\S]*?<\/noscript>/gi, " ")
  )
    .replace(/<(?:br|\/p|\/div|\/li|\/h[1-6]|\/section|\/article|\/header|\/footer)>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .split(/\r?\n/)
    .map((line) => line.replace(/\s+/g, " ").trim())
    .filter(Boolean);
}

function parseDateRange(line) {
  const yearFirst = [...line.matchAll(/(20\d{2})[.\/\-年](\d{1,2})[.\/\-月](\d{1,2})(?:日)?/g)];
  if (yearFirst.length > 0) {
    return {
      date: dateFromParts(yearFirst[0][1], yearFirst[0][2], yearFirst[0][3]),
      endDate: yearFirst[1]
        ? dateFromParts(yearFirst[1][1], yearFirst[1][2], yearFirst[1][3])
        : null
    };
  }

  const englishMonthFirst = line.match(
    /\b(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)?\s*([A-Za-z]+)\s+(\d{1,2}),\s*(20\d{2})\b/i
  );
  if (englishMonthFirst) {
    const month = ENGLISH_MONTHS.get(englishMonthFirst[1].toLowerCase());
    return {
      date: month ? dateFromParts(englishMonthFirst[3], month, englishMonthFirst[2]) : null,
      endDate: null
    };
  }

  const localizedNumeric = line.match(/(?:^|\D)(\d{1,2})\s+(\d{1,2})月\s+(20\d{2})(?:\D|$)/);
  if (localizedNumeric) {
    return {
      date: dateFromParts(localizedNumeric[3], localizedNumeric[2], localizedNumeric[1]),
      endDate: null
    };
  }

  const chineseMonthRange = line.match(
    /(\d{1,2})\s*([一二三四五六七八九十]{1,3})月\s*[-–—至]\s*(\d{1,2})\s*\2月\s*(20\d{2})/
  );
  if (chineseMonthRange) {
    const month = CHINESE_MONTHS.get(chineseMonthRange[2]);
    return {
      date: month ? dateFromParts(chineseMonthRange[4], month, chineseMonthRange[1]) : null,
      endDate: month ? dateFromParts(chineseMonthRange[4], month, chineseMonthRange[3]) : null
    };
  }

  const chineseMonthSingle = line.match(
    /(?:^|\D)(\d{1,2})\s*([一二三四五六七八九十]{1,3})月\s*(20\d{2})(?:\D|$)/
  );
  if (chineseMonthSingle) {
    const month = CHINESE_MONTHS.get(chineseMonthSingle[2]);
    return {
      date: month ? dateFromParts(chineseMonthSingle[3], month, chineseMonthSingle[1]) : null,
      endDate: null
    };
  }

  return { date: null, endDate: null };
}

function parseClock(line) {
  const clock = line.match(/(?:^|\D)(\d{1,2})(?::(\d{2}))?\s*(am|pm)(?:\D|$)/i);
  if (clock) {
    let hour = Number(clock[1]);
    const minute = Number(clock[2] ?? 0);
    const period = clock[3].toLowerCase();
    if (hour < 1 || hour > 12 || minute > 59) return null;
    if (period === "am" && hour === 12) hour = 0;
    if (period === "pm" && hour !== 12) hour += 12;
    return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
  }

  const twentyFourHour = line.match(/(?:^|\D)([01]?\d|2[0-3])[:：](\d{2})(?:\D|$)/);
  if (!twentyFourHour || Number(twentyFourHour[2]) > 59) return null;
  return `${String(Number(twentyFourHour[1])).padStart(2, "0")}:${twentyFourHour[2]}`;
}

function parseVenue(lines, startIndex, eventName) {
  const nearby = lines.slice(startIndex, startIndex + 6);

  for (const line of nearby) {
    if (line === eventName || parseDateRange(line).date || isNavigationText(line)) continue;
    const inline = line.match(/^(.{2,100}?),\s*([A-Za-z][A-Za-z .'-]{1,50})$/);
    if (inline && looksLikeVenue(inline[1])) {
      return { name: inline[1].trim(), city: inline[2].trim() };
    }
  }

  for (let index = 0; index < nearby.length - 1; index += 1) {
    const venue = nearby[index];
    const cityLine = nearby[index + 1];
    if (!venue || !cityLine || isNavigationText(venue) || isNavigationText(cityLine)) continue;
    const city = cityLine.match(/^([^,]{2,50}),\s*(?:[A-Z]{2}|[A-Za-z ]{2,30})$/)?.[1]?.trim();
    if (city && looksLikeVenue(venue)) {
      return { name: venue.trim(), city };
    }
  }

  return { name: "", city: "" };
}

function fieldFollowingLabel(lines, labels) {
  for (let index = 0; index < lines.length; index += 1) {
    const normalized = lines[index].replace(/[：:*\s]/g, "").toLowerCase();
    if (!labels.some((label) => normalized === label.replace(/\s/g, "").toLowerCase())) continue;

    for (const candidate of lines.slice(index + 1, index + 5)) {
      if (!candidate || isNavigationText(candidate) || parseDateRange(candidate).date) continue;
      return candidate.trim();
    }
  }
  return "";
}

function looksLikeVenue(value) {
  return /(Arena|Stadium|Theatre|Theater|Hall|Auditorium|Ballroom|Pavilion|Amphitheater|Amphitheatre|Center|Centre|Club|体育场|体育馆|剧场|剧院|音乐厅|店)/i.test(value);
}

function isNavigationText(value) {
  if (/(全面开售|选择另一场次)/.test(value)) return true;
  return /^(Upgrades|待售门票|购买门票|全面开售|演出详情|分享|Lineup|主要演出|该演出中的艺人)$/i.test(value);
}

function dateFromParts(yearValue, monthValue, dayValue) {
  const year = Number(yearValue);
  const month = Number(monthValue);
  const day = Number(dayValue);
  if (!validDate(year, month, day)) return null;
  return `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

function validDate(year, month, day) {
  if (year < 2000 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31) return false;
  const value = new Date(Date.UTC(year, month - 1, day));
  return value.getUTCFullYear() === year
    && value.getUTCMonth() === month - 1
    && value.getUTCDate() === day;
}

function cleanTitle(value) {
  return decodeHtmlEntities(value)
    .replace(/\s*(?:[-|｜]\s*)?Live Nation.*$/i, "")
    .trim();
}

function tagText(html, tagName) {
  const match = html.match(new RegExp(`<${tagName}\\b[^>]*>([\\s\\S]*?)<\\/${tagName}>`, "i"));
  if (!match?.[1]) return "";
  return decodeHtmlEntities(match[1].replace(/<[^>]+>/g, " "))
    .replace(/\s+/g, " ")
    .trim();
}

function metaContent(html, property) {
  const tags = html.match(/<meta\b[^>]*>/gi) ?? [];
  for (const tag of tags) {
    const key = attribute(tag, "property") || attribute(tag, "name");
    if (key.toLowerCase() !== property.toLowerCase()) continue;
    return decodeHtmlEntities(attribute(tag, "content")).trim();
  }
  return "";
}

function attribute(tag, name) {
  return tag.match(new RegExp(`${name}\\s*=\\s*["']([^"']*)["']`, "i"))?.[1]
    ?? tag.match(new RegExp(`${name}\\s*=\\s*([^\\s>]+)`, "i"))?.[1]
    ?? "";
}

function decodeHtmlEntities(value) {
  return String(value)
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">");
}
