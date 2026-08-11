const TICKETMASTER_API_ORIGIN = "https://app.ticketmaster.com";
export const TICKETMASTER_DISCOVERY_API =
  `${TICKETMASTER_API_ORIGIN}/discovery/v2/events`;

export async function fetchTicketmasterEvent({
  eventId,
  canonicalUrl = "",
  apiKey = process.env.TICKETMASTER_API_KEY,
  fetch = globalThis.fetch
} = {}) {
  const id = stringValue(eventId);
  if (!id) {
    throw new Error("Ticketmaster event ID is required");
  }

  const key = stringValue(apiKey);
  if (!key) {
    throw new Error("Ticketmaster API key is not configured");
  }

  if (typeof fetch !== "function") {
    throw new Error("Fetch API is not available");
  }

  const url = buildTicketmasterEventUrl({
    eventId: id,
    apiKey: key,
    canonicalUrl
  });
  const response = await fetchJson(url, fetch);

  if (response.status === 404 && canonicalUrl) {
    const resolvedEvent = await searchTicketmasterEvent({
      eventId: id,
      canonicalUrl,
      apiKey: key,
      fetch
    });
    if (resolvedEvent) return resolvedEvent;
  }

  assertSuccessfulResponse(response);
  return parseTicketmasterResponse(response.body);
}

export function buildTicketmasterEventUrl({ eventId, apiKey, canonicalUrl = "" } = {}) {
  const id = stringValue(eventId);
  const key = stringValue(apiKey);
  if (!id) {
    throw new Error("Ticketmaster event ID is required");
  }
  if (!key) {
    throw new Error("Ticketmaster API key is not configured");
  }

  const params = new URLSearchParams({ apikey: key });
  return `${TICKETMASTER_API_ORIGIN}/discovery/v2/events/${encodeURIComponent(id)}.json?${params}`;
}

async function searchTicketmasterEvent({ eventId, canonicalUrl, apiKey, fetch }) {
  const keywords = ticketmasterSearchKeywords(canonicalUrl, eventId);
  for (const keyword of keywords) {
    const url = new URL(`${TICKETMASTER_API_ORIGIN}/discovery/v2/events.json`);
    url.searchParams.set("apikey", apiKey);
    url.searchParams.set("keyword", keyword);
    url.searchParams.set("size", "50");

    const response = await fetchJson(url.toString(), fetch);
    if (response.status < 200 || response.status >= 300) continue;

    const events = response.body?._embedded?.events ?? [];
    const directMatch = events.find((event) => stringValue(event?.id) === eventId);
    if (directMatch) return directMatch;

    const pathMatch = events.find((event) => {
      try {
        return new URL(event?.url).pathname.includes(`/event/${eventId}`);
      } catch {
        return false;
      }
    });
    if (pathMatch) return pathMatch;
  }

  return null;
}

function ticketmasterSearchKeywords(canonicalUrl, eventId) {
  const keywords = [eventId];
  try {
    const pathname = new URL(canonicalUrl).pathname;
    const slug = pathname
      .replace(/\/event\/[^/]+\/?$/i, "")
      .split("/")
      .filter(Boolean)
      .pop()
      ?.replace(/[-_]+/g, " ")
      .replace(/\b\d{1,2} \d{1,2} \d{4}\b/g, "")
      .trim();
    if (slug && slug !== eventId) keywords.unshift(slug);
  } catch {
    // The event ID remains a valid search keyword when the canonical URL is malformed.
  }
  return keywords;
}

async function fetchJson(url, fetch) {
  const response = await fetch(url, {
    headers: {
      Accept: "application/json",
      "User-Agent": "BeforeShow/1.0"
    }
  });
  const status = Number(response?.status);

  if (
    !response
    || response.ok === false
    || (Number.isFinite(status) && (status < 200 || status >= 300))
  ) {
    return { response, status, body: null };
  }

  let body;
  try {
    body = await response.json();
  } catch {
    throw new Error("Ticketmaster API returned invalid JSON");
  }

  return { response, status, body };
}

function assertSuccessfulResponse({ response, status, body }) {
  if (
    !response
    || response.ok === false
    || (Number.isFinite(status) && (status < 200 || status >= 300))
  ) {
    throw new Error(`Ticketmaster API request failed: ${response?.status ?? "unknown"}`);
  }

  const providerError = ticketmasterErrorMessage(body);
  if (providerError) {
    throw new Error(`Ticketmaster API error: ${providerError}`);
  }
}

function parseTicketmasterResponse(body) {
  const event = extractEvent(body);
  if (!event) {
    throw new Error("Ticketmaster API response is missing event data");
  }
  return event;
}

export function parseTicketmasterEvent(event) {
  if (!event || typeof event !== "object" || Array.isArray(event)) {
    throw new Error("Ticketmaster event data is invalid");
  }

  const start = event.dates?.start ?? {};
  const end = event.dates?.end ?? {};
  const venue = event._embedded?.venues?.[0] ?? event.venues?.[0] ?? {};
  const attractions = event._embedded?.attractions ?? event.attractions ?? [];
  const artists = uniqueStrings(
    attractions.map((attraction) => attraction?.name ?? attraction).map(stringValue)
  );
  const artistAvatarURLs = uniqueStrings(
    attractions.flatMap((attraction) => imageUrls(attraction?.images ?? attraction?.image))
  );
  const image = imageUrls(event.images)[0] ?? "";

  return {
    name: stringValue(event.name),
    city: stringValue(venue.city?.name ?? venue.city),
    date: normalizeDate(start.localDate),
    startTime: normalizeTime(start.localTime),
    ...(normalizeDate(end.localDate) ? { endDate: normalizeDate(end.localDate) } : {}),
    ...(normalizeTime(end.localTime) ? { endTime: normalizeTime(end.localTime) } : {}),
    venueName: stringValue(venue.name),
    venueAddr: formatVenueAddress(venue),
    artist: artists.join(", "),
    coverImageURL: image,
    artistAvatarURLs,
    priceRange: formatPriceRange(event.priceRanges),
    source: "ticketmaster"
  };
}

function extractEvent(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) return null;
  if (body.name || body.dates || body._embedded?.venues) return body;
  return body._embedded?.events?.[0] ?? null;
}

function ticketmasterErrorMessage(body) {
  if (!body || typeof body !== "object") return "";
  return stringValue(
    body.fault?.faultstring
      ?? body.fault?.detail?.errorcode
      ?? body.error?.message
      ?? body.errors?.[0]?.detail
      ?? body.errors?.[0]?.title
  );
}

function formatVenueAddress(venue) {
  const address = venue?.address;
  if (typeof address === "string") return address.trim();
  if (!address || typeof address !== "object") return "";

  return [
    address.line1,
    address.line2,
    address.streetAddress,
    venue.postalCode
  ].map(stringValue).filter(Boolean).filter((value, index, values) => (
    values.indexOf(value) === index
  )).join(", ");
}

function formatPriceRange(priceRanges) {
  if (!Array.isArray(priceRanges) || priceRanges.length === 0) return "";

  const firstCurrency = priceRanges.map((range) => stringValue(range?.currency)).find(Boolean);
  const ranges = priceRanges
    .filter((range) => !firstCurrency || stringValue(range?.currency) === firstCurrency)
    .flatMap((range) => [range?.min, range?.max])
    .map((value) => Number(value))
    .filter(Number.isFinite);

  if (ranges.length === 0) return "";
  const min = Math.min(...ranges);
  const max = Math.max(...ranges);
  const amount = min === max ? formatAmount(min) : `${formatAmount(min)}-${formatAmount(max)}`;
  return firstCurrency ? `${firstCurrency} ${amount}` : amount;
}

function imageUrls(value) {
  if (!Array.isArray(value)) value = value ? [value] : [];
  return uniqueStrings(value.map((image) => (
    typeof image === "string" ? image : image?.url
  )));
}

function normalizeDate(value) {
  const match = stringValue(value).match(/^(20\d{2})-(\d{2})-(\d{2})/);
  if (!match) return "";

  const date = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
  if (
    date.getUTCFullYear() !== Number(match[1])
    || date.getUTCMonth() !== Number(match[2]) - 1
    || date.getUTCDate() !== Number(match[3])
  ) {
    return "";
  }

  return `${match[1]}-${match[2]}-${match[3]}`;
}

function normalizeTime(value) {
  const match = stringValue(value).match(/^(\d{1,2}):(\d{2})/);
  if (!match || Number(match[1]) > 23 || Number(match[2]) > 59) return "";
  return `${String(Number(match[1])).padStart(2, "0")}:${match[2]}`;
}

function formatAmount(value) {
  return Number.isInteger(value) ? String(value) : String(value).replace(/0+$/, "").replace(/\.$/, "");
}

function uniqueStrings(values) {
  return [...new Set(values.map(stringValue).filter(Boolean))];
}

function stringValue(value) {
  if (typeof value === "string") return value.trim();
  if (typeof value === "number") return String(value);
  return "";
}
