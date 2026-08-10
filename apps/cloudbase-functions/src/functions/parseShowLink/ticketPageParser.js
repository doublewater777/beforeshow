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

export async function fetchAndParseTicketPage({
  url,
  source,
  fetch = globalThis.fetch
} = {}) {
  const html = await fetchPublicEventPage({ url, fetch });

  try {
    return parsePublicEventPage(html, { source });
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
    ?? "";

  const venue = parseVenue(lines, dateLineIndex, name);
  const city = venue.city || inferCity(name) || inferCity(venue.name) || inferCity(venue.address) || "";
  const artist = fieldFollowingLabel(lines, ["主要演员", "演出艺人", "艺人", "阵容"]);
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
    .map((line) => line.replace(/\s+/g, " ").trim())
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
  return /(20\d{2})[.\/-年](\d{1,2})[.\/-月](\d{1,2})(?:日)?/.test(line);
}

function parseDateRange(line) {
  const matches = [...line.matchAll(/(20\d{2})[.\/-年](\d{1,2})[.\/-月](\d{1,2})(?:日)?/g)];
  if (matches.length === 0) return { date: null, endDate: null };

  return {
    date: formatDateMatch(matches[0]),
    endDate: matches.length > 1 ? formatDateMatch(matches[1]) : null
  };
}

function formatDateMatch(match) {
  return `${match[1]}-${match[2].padStart(2, "0")}-${match[3].padStart(2, "0")}`;
}

function firstClock(line) {
  const match = line.match(/(?:^|\D)(\d{1,2})[:：](\d{2})(?:\D|$)/);
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (hour > 23 || minute > 59) return null;
  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}

function parseVenue(lines, dateLineIndex, name) {
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
    ...lines.slice(Math.max(0, dateLineIndex - 4), dateLineIndex + 5)
  ].filter(Boolean);

  for (const candidate of candidates) {
    if (candidate === name || containsFullDate(candidate) || looksLikePrice(candidate)) continue;
    const parenthesized = candidate.match(/^(.{2,80}?)[(（]([^()（）]{3,160})[)）]$/);
    if (parenthesized) {
      return {
        city: inferCity(candidate) || "",
        name: parenthesized[1].trim(),
        address: parenthesized[2].trim()
      };
    }

    if (looksLikeVenue(candidate)) {
      return {
        city: inferCity(candidate) || "",
        name: candidate.trim(),
        address: ""
      };
    }
  }

  return { city: "", name: "", address: "" };
}

function nearbyAddress(lines, venueIndex, venueName) {
  for (const line of lines.slice(venueIndex + 1, venueIndex + 4)) {
    if (!line || line === venueName || containsFullDate(line) || looksLikePrice(line)) continue;
    if (line.includes("市") || line.includes("区") || line.includes("路") || line.includes("街") || line.includes("号")) {
      return line;
    }
  }
  return "";
}

function looksLikeVenue(line) {
  return /(体育场|体育馆|剧场|剧院|音乐厅|Livehouse|LIVEHOUSE|Arena|Stadium|Theatre|Theater|Hall)/i.test(line);
}

function fieldFollowingLabel(lines, labels) {
  for (let index = 0; index < lines.length; index += 1) {
    const compact = lines[index].replace(/[：:*\s]/g, "");
    if (!labels.some((label) => compact === label || compact.endsWith(label))) continue;

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
