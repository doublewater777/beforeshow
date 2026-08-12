import {
  fetchPublicEventPage,
  parsePublicEventPage
} from "./publicEventParser.js";

const CITY_NAMES = [
  "北京", "上海", "天津", "重庆", "深圳", "广州", "杭州", "成都", "南京", "武汉",
  "西安", "长沙", "苏州", "厦门", "青岛", "宁波", "无锡", "佛山", "东莞", "郑州",
  "济南", "合肥", "福州", "南昌", "昆明", "贵阳", "南宁", "海口", "三亚", "沈阳",
  "大连", "长春", "哈尔滨", "石家庄", "太原", "兰州", "西宁", "银川", "乌鲁木齐",
  "香港", "澳门", "台北", "高雄"
];

const MONTHS = new Map([
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

export async function fetchAndParseTicketPage({
  url,
  source,
  fetch = globalThis.fetch
} = {}) {
  const html = await fetchPublicEventPage({ url, fetch });

  try {
    const draft = parsePublicEventPage(html, { source });
    return supplementVisibleFields(html, draft);
  } catch (structuredError) {
    try {
      return parseVisibleEventPage(html, { source });
    } catch (visibleError) {
      const error = new Error(
        `Unable to parse ${source ?? "ticket"} event page: ${visibleError.message}`
      );
      error.cause = structuredError;
      throw error;
    }
  }
}

// Some SSR pages (e.g. DICE) ship a JSON-LD MusicEvent with correct
// name/date/venue but omit both the city (address is a single string) and the
// performer. Fill those two gaps from visible text when the structured draft
// left them empty. Other platforms are unaffected because their drafts already
// carry city and artist.
function supplementVisibleFields(html, draft) {
  if (!draft || (draft.city && draft.artist)) return draft;

  const lines = visibleLines(html);
  const next = { ...draft };
  if (!next.city) next.city = inferEnglishCity(lines);
  if (!next.artist) next.artist = extractLineup(lines);
  return next;
}

function inferEnglishCity(lines) {
  const gigs = lines.map((line) => line.match(/^Gigs\s+(.+)$/i)).find(Boolean);
  if (gigs?.[1]) return cleanCityToken(gigs[1]);

  const venueLine = lines.find((line) => /^Venue\s+/i.test(line));
  const parts = venueLine?.split(",").map((part) => part.trim()).filter(Boolean) ?? [];
  if (parts.length >= 3) return cleanCityToken(parts[parts.length - 3]);
  return "";
}

function extractLineup(lines) {
  for (let index = 0; index < lines.length; index += 1) {
    if (!/^lineup\s*:?$/i.test(lines[index])) continue;
    for (const candidate of lines.slice(index + 1, index + 4)) {
      if (!candidate || /^\d+$/.test(candidate)) continue;
      if (/^show more$/i.test(candidate)) continue;
      return candidate.replace(/\s+and\s+\d+\s+more\s*$/i, "").trim();
    }
  }
  return "";
}

function cleanCityToken(value) {
  return value.replace(/\s*[|｜].*$/, "").trim();
}

export function parseVisibleEventPage(html, { source } = {}) {
  if (typeof html !== "string" || html.trim().length === 0) {
    throw new Error("Ticket page is empty");
  }

  const lines = visibleLines(html);
  const h1 = tagText(html, "h1");
  const title = tagText(html, "title");
  const name = cleanTitle(h1 || title || lines[0] || "");

  const dateLineIndex = lines.findIndex((line) => containsFullDate(line));
  if (!name || dateLineIndex < 0) {
    throw new Error("Visible ticket page is missing a name or date");
  }

  const dateLine = lines[dateLineIndex];
  const dateRange = parseDateRange(dateLine);
  if (!dateRange.date) {
    throw new Error("Visible ticket page date is invalid");
  }

  const startTime = firstClock(dateLine)
    ?? firstClock(lines[dateLineIndex + 1] ?? "")
    ?? firstClock(lines[dateLineIndex - 1] ?? "")
    ?? firstClock(lines.find((line) => containsMonthName(line) && firstClock(line)) ?? "")
    ?? "";

  const venue = parseVenue(lines, dateLineIndex, name);
  const city = venue.city || inferCity(name) || inferCity(venue.name) || inferCity(venue.address) || "";
  const artist = fieldFollowingLabel(lines, ["主要演员", "演出艺人", "艺人", "阵容", "Lineup"]);
  const priceRange = parsePriceRange(lines);

  return {
    name,
    city,
    date: dateRange.date,
    startTime,
    ...(dateRange.endDate ? { endDate: dateRange.endDate } : {}),
    venueName: venue.name,
    venueAddr: venue.address,
    artist,
    coverImageURL: metaContent(html, "og:image") || "",
    artistAvatarURLs: [],
    priceRange,
    source: source ?? "public"
  };
}

function visibleLines(html) {
  const withoutScripts = html
    .replace(/<script\b[\s\S]*?<\/script>/gi, " ")
    .replace(/<style\b[\s\S]*?<\/style>/gi, " ")
    .replace(/<noscript\b[\s\S]*?<\/noscript>/gi, " ");

  return decodeHtmlEntities(withoutScripts)
    .replace(/<(?:br|\/p|\/div|\/li|\/h[1-6]|\/section|\/article|\/header|\/footer)>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .split(/\r?\n/)
    .map((line) => line
      .replace(/\b(Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+\([^)]+\)\s+([A-Za-z]+)\s+\([^)]+\)/i, "$1 $2")
      .replace(/\s+/g, " ")
      .trim())
    .filter(Boolean);
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
    if (key?.toLowerCase() !== property.toLowerCase()) continue;
    return decodeHtmlEntities(attribute(tag, "content") || "").trim();
  }
  return "";
}

function attribute(tag, name) {
  return tag.match(new RegExp(`${name}\\s*=\\s*["']([^"']*)["']`, "i"))?.[1]
    ?? tag.match(new RegExp(`${name}\\s*=\\s*([^\\s>]+)`, "i"))?.[1]
    ?? "";
}

function containsFullDate(line) {
  return /(20\d{2})[.\/\-年](\d{1,2})[.\/\-月](\d{1,2})(?:日)?/.test(line)
    || /\b(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t|tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{1,2},\s*20\d{2}\b/i.test(line)
    || /\b\d{1,2}(?:st|nd|rd|th)?\s+(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t|tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?),?\s+20\d{2}\b/i.test(line)
    || /\b\d{1,2}\/\d{1,2}\/20\d{2}\b/.test(line);
}

function containsMonthName(line) {
  return /\b(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t|tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\b/i.test(line);
}

function parseDateRange(line) {
  const yearFirstMatches = [...line.matchAll(/(20\d{2})[.\/\-年](\d{1,2})[.\/\-月](\d{1,2})(?:日)?/g)];
  if (yearFirstMatches.length > 0) {
    return {
      date: formatYearFirstMatch(yearFirstMatches[0]),
      endDate: yearFirstMatches.length > 1 ? formatYearFirstMatch(yearFirstMatches[1]) : null
    };
  }

  const monthFirst = line.match(/\b([A-Za-z]+)\s+(\d{1,2}),\s*(20\d{2})\b/i);
  if (monthFirst) {
    const month = monthNumber(monthFirst[1]);
    return {
      date: month ? formatDate(Number(monthFirst[3]), month, Number(monthFirst[2])) : null,
      endDate: null
    };
  }

  const dayFirst = line.match(/\b(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]+),?\s+(20\d{2})\b/i);
  if (dayFirst) {
    const month = monthNumber(dayFirst[2]);
    return {
      date: month ? formatDate(Number(dayFirst[3]), month, Number(dayFirst[1])) : null,
      endDate: null
    };
  }

  // International fallback pages served in en-US commonly expose M/D/YYYY.
  // Structured JSON-LD remains the preferred path, so this is only used when that is unavailable.
  const numericUS = line.match(/\b(\d{1,2})\/(\d{1,2})\/(20\d{2})\b/);
  if (numericUS) {
    return {
      date: formatDate(Number(numericUS[3]), Number(numericUS[1]), Number(numericUS[2])),
      endDate: null
    };
  }

  return { date: null, endDate: null };
}

function formatYearFirstMatch(match) {
  return formatDate(Number(match[1]), Number(match[2]), Number(match[3]));
}

function formatDate(year, month, day) {
  if (!isValidDateParts(year, month, day)) return null;
  return `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

function isValidDateParts(year, month, day) {
  if (year < 2000 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31) return false;
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year
    && date.getUTCMonth() === month - 1
    && date.getUTCDate() === day;
}

function monthNumber(value) {
  return MONTHS.get(value.toLowerCase()) ?? null;
}

function firstClock(line) {
  const match = line.match(/(?:^|\D)(\d{1,2})[:：](\d{2})\s*(am|pm)?(?:\D|$)/i);
  if (!match) return null;

  let hour = Number(match[1]);
  const minute = Number(match[2]);
  const period = match[3]?.toLowerCase();

  if (minute > 59) return null;
  if (period) {
    if (hour < 1 || hour > 12) return null;
    if (period === "am" && hour === 12) hour = 0;
    if (period === "pm" && hour !== 12) hour += 12;
  } else if (hour > 23) {
    return null;
  }

  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}

function parseVenue(lines, dateLineIndex, name) {
  const dateLine = lines[dateLineIndex] ?? "";
  const ticketmasterInline = dateLine.match(/\b(?:AM|PM)\s*(.+?),\s*([^,]+),\s*([A-Z]{2})(?:\b|$)/i);
  if (ticketmasterInline && looksLikeVenue(ticketmasterInline[1])) {
    return {
      city: ticketmasterInline[2].trim(),
      name: ticketmasterInline[1].trim(),
      address: ""
    };
  }

  const venueLabelIndex = lines.findIndex((line) => /^venue\s*:?$/i.test(line));
  if (venueLabelIndex >= 0) {
    const venueName = lines[venueLabelIndex + 1]?.trim() ?? "";
    if (venueName && !containsFullDate(venueName) && !looksLikePrice(venueName)) {
      return {
        city: "",
        name: venueName,
        address: nearbyAddress(lines, venueLabelIndex + 1, venueName)
      };
    }
  }

  const pipeCandidate = lines
    .map((line, index) => ({ line, index, match: line.match(/^([^|｜]{1,16})\s*[|｜]\s*(.+)$/) }))
    .find(({ match }) => match && inferCity(match[1]));

  if (pipeCandidate?.match) {
    const address = nearbyAddress(lines, pipeCandidate.index, pipeCandidate.match[2]);
    return {
      city: cleanCity(pipeCandidate.match[1]),
      name: pipeCandidate.match[2].trim(),
      address
    };
  }

  const candidates = [
    lines[dateLineIndex - 1],
    lines[dateLineIndex + 1],
    ...lines.slice(Math.max(0, dateLineIndex - 5), dateLineIndex + 7),
    ...lines.slice(0, 6)
  ].filter(Boolean);

  for (const candidate of candidates) {
    if (candidate === name || containsFullDate(candidate) || looksLikePrice(candidate)) continue;

    const englishVenue = candidate.match(/^(.+?),\s*([^,]+),\s*([^,]+),\s*(United States|USA|United Kingdom|Canada|Australia|New Zealand)\b/i);
    if (englishVenue && looksLikeVenue(englishVenue[1])) {
      const originalIndex = lines.indexOf(candidate);
      return {
        city: englishVenue[2].trim(),
        name: englishVenue[1].trim(),
        address: nearbyAddress(lines, originalIndex, englishVenue[1])
      };
    }

    const parenthesized = candidate.match(/^(.{2,80}?)[(（]([^()（）]{3,160})[)）]$/);
    if (parenthesized) {
      return {
        city: inferCity(candidate) || "",
        name: parenthesized[1].trim(),
        address: parenthesized[2].trim()
      };
    }

    if (looksLikeVenue(candidate)) {
      const originalIndex = lines.indexOf(candidate);
      return {
        city: inferCity(candidate) || "",
        name: candidate.trim(),
        address: nearbyAddress(lines, originalIndex, candidate)
      };
    }
  }

  return { city: "", name: "", address: "" };
}

function nearbyAddress(lines, venueIndex, venueName) {
  if (venueIndex < 0) return "";
  for (const line of lines.slice(venueIndex + 1, venueIndex + 4)) {
    if (!line || line === venueName || containsFullDate(line) || looksLikePrice(line)) continue;
    if (looksLikeAddress(line)) return line;
  }
  return "";
}

function looksLikeVenue(line) {
  return /(体育场|体育馆|剧场|剧院|音乐厅|Livehouse|LIVEHOUSE|Arena|Stadium|Theatre|Theater|Hall|Auditorium|Ballroom|Pavilion|Amphitheater|Amphitheatre|Center|Centre|Club)/i.test(line);
}

function looksLikeAddress(line) {
  return line.includes("市")
    || line.includes("区")
    || line.includes("路")
    || line.includes("街")
    || line.includes("号")
    || /\b(?:Street|St\.?|Avenue|Ave\.?|Road|Rd\.?|Boulevard|Blvd\.?|Drive|Dr\.?|Lane|Ln\.?)\b/i.test(line)
    || /\b\d{5}(?:-\d{4})?\b/.test(line);
}

function fieldFollowingLabel(lines, labels) {
  for (let index = 0; index < lines.length; index += 1) {
    const compact = lines[index].replace(/[：:*\s]/g, "");
    if (!labels.some((label) => compact.toLowerCase() === label.toLowerCase() || compact.toLowerCase().endsWith(label.toLowerCase()))) continue;

    for (const candidate of lines.slice(index + 1, index + 4)) {
      if (!candidate || containsFullDate(candidate) || looksLikePrice(candidate)) continue;
      if (/^(查看详情|展开更多|购票须知|观演须知)$/.test(candidate)) continue;
      return candidate.replace(/^[：:\s]+/, "").trim();
    }
  }
  return "";
}

function parsePriceRange(lines) {
  const line = lines.find(looksLikePrice);
  if (!line) return "";
  return line
    .replace(/^[¥￥]\s*/, "")
    .replace(/\s*元.*$/, "")
    .trim();
}

function looksLikePrice(line) {
  return /^[¥￥]\s*\d[\d,.]*(?:\.\d+)?(?:\s*[-~—–至]\s*(?:[¥￥]\s*)?\d[\d,.]*(?:\.\d+)?)?/.test(line);
}

function inferCity(value) {
  if (!value) return "";
  const bracketed = value.match(/[【\[]([^】\]]{2,8})[】\]]/)?.[1];
  if (bracketed) {
    const matched = CITY_NAMES.find((city) => bracketed.includes(city));
    if (matched) return matched;
  }

  return CITY_NAMES.find((city) => value.includes(city)) ?? "";
}

function cleanCity(value) {
  const city = inferCity(value);
  return city || value.trim().replace(/市$/, "");
}

function cleanTitle(value) {
  return decodeHtmlEntities(value)
    .replace(/\s*[|｜-]\s*(猫眼|票星球|纷玩岛|Ticketmaster|DICE|AXS).*$/i, "")
    .trim();
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
