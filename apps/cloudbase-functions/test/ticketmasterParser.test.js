import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { parseShowLink } from "../src/functions/parseShowLink/index.js";
import {
  buildTicketmasterEventUrl,
  fetchTicketmasterEvent,
  parseTicketmasterEvent
} from "../src/functions/parseShowLink/ticketmasterParser.js";

const EVENT_ID = "0D0060EABACB3E23";
const EVENT_URL = `https://www.ticketmaster.com/example-tour/event/${EVENT_ID}?CAMEFROM=share`;

const EVENT = {
  id: EVENT_ID,
  name: "Example Tour",
  dates: {
    start: { localDate: "2026-09-19", localTime: "20:00:00" },
    end: { localDate: "2026-09-19", localTime: "22:30:00" }
  },
  images: [{ url: "https://example.com/cover.jpg" }],
  priceRanges: [
    { type: "standard", currency: "USD", min: 45, max: 120 },
    { type: "standard", currency: "USD", min: 60, max: 100 }
  ],
  _embedded: {
    venues: [{
      name: "Example Arena",
      city: { name: "Los Angeles" },
      state: { name: "California" },
      country: { name: "United States" },
      address: { line1: "100 Main Street" },
      postalCode: "90001"
    }],
    attractions: [{
      name: "Example Artist",
      images: [{ url: "https://example.com/artist.jpg" }]
    }]
  }
};

describe("Ticketmaster Discovery API parser", () => {
  it("builds the event endpoint with the API key only in the request URL", () => {
    const url = new URL(buildTicketmasterEventUrl({
      eventId: EVENT_ID,
      apiKey: "test-key",
      canonicalUrl: EVENT_URL
    }));

    assert.equal(url.pathname, `/discovery/v2/events/${EVENT_ID}.json`);
    assert.equal(url.origin, "https://app.ticketmaster.com");
    assert.equal(url.searchParams.get("apikey"), "test-key");
  });

  it("uses the same Discovery API origin for regional Ticketmaster sites", () => {
    for (const domain of ["ticketmaster.co.uk", "ticketmaster.de", "ticketmaster.fr"]) {
      const url = new URL(buildTicketmasterEventUrl({
        eventId: EVENT_ID,
        apiKey: "test-key",
        canonicalUrl: `https://www.${domain}/tour/event/${EVENT_ID}`
      }));

      assert.equal(url.origin, "https://app.ticketmaster.com");
    }
  });

  it("maps a Discovery event into the BeforeShow draft contract", () => {
    assert.deepEqual(parseTicketmasterEvent(EVENT), {
      name: "Example Tour",
      city: "Los Angeles",
      date: "2026-09-19",
      startTime: "20:00",
      endDate: "2026-09-19",
      endTime: "22:30",
      venueName: "Example Arena",
      venueAddr: "100 Main Street, 90001",
      artist: "Example Artist",
      coverImageURL: "https://example.com/cover.jpg",
      artistAvatarURLs: ["https://example.com/artist.jpg"],
      priceRange: "USD 45-120",
      source: "ticketmaster"
    });
  });

  it("preserves Discovery event instants when the API provides dateTime", () => {
    const event = structuredClone(EVENT);
    event.dates.start.dateTime = "2026-09-19T20:00:00-07:00";
    event.dates.end.dateTime = "2026-09-19T22:30:00-07:00";

    const draft = parseTicketmasterEvent(event);

    assert.equal(draft.startDateTime, "2026-09-19T20:00:00-07:00");
    assert.equal(draft.endDateTime, "2026-09-19T22:30:00-07:00");
  });

  it("preserves the IANA timezone when the API provides it", () => {
    const event = structuredClone(EVENT);
    event.dates.timezone = "America/Los_Angeles";

    assert.equal(parseTicketmasterEvent(event).timeZoneIdentifier, "America/Los_Angeles");
  });

  it("uses injected fetch and validates the response", async () => {
    let requestedUrl = "";
    let requestedOptions;
    const fetch = async (url, options) => {
      requestedUrl = url;
      requestedOptions = options;
      return { ok: true, status: 200, json: async () => EVENT };
    };

    const event = await fetchTicketmasterEvent({
      eventId: EVENT_ID,
      apiKey: "test-key",
      fetch
    });

    assert.equal(event.id, EVENT_ID);
    assert.equal(new URL(requestedUrl).searchParams.get("apikey"), "test-key");
    assert.equal(requestedOptions.headers.Accept, "application/json");
  });

  it("routes Ticketmaster IDs to the public page parser without an API key", async () => {
    let requestedUrl = "";
    const fetch = async (url) => {
      requestedUrl = url;
      return {
        ok: true,
        status: 200,
        text: async () => `<script type="application/ld+json">${JSON.stringify({
          "@type": "MusicEvent",
          name: "Page Event",
          startDate: "2026-09-19T20:00:00+00:00",
          location: { "@type": "Place", name: "Page Arena", address: { addressLocality: "London" } }
        })}</script>`
      };
    };

    const draft = await parseShowLink(EVENT_URL, { fetch });

    assert.equal(draft.source, "ticketmaster");
    assert.equal(draft.name, "Page Event");
    assert.equal(new URL(requestedUrl).hostname, "www.ticketmaster.com");
  });
  it("rejects missing configuration without leaking a key", async () => {
    await assert.rejects(
      fetchTicketmasterEvent({ eventId: EVENT_ID, apiKey: "", fetch: async () => ({}) }),
      /API key is not configured/
    );
  });

  it("reports HTTP, invalid JSON, provider, and missing-event errors", async () => {
    await assert.rejects(
      fetchTicketmasterEvent({
        eventId: EVENT_ID,
        apiKey: "test-key",
        fetch: async () => ({ ok: false, status: 401 })
      }),
      /request failed: 401/
    );

    await assert.rejects(
      fetchTicketmasterEvent({
        eventId: EVENT_ID,
        apiKey: "test-key",
        fetch: async () => ({ ok: true, status: 200, json: async () => { throw new Error("bad"); } })
      }),
      /invalid JSON/
    );

    await assert.rejects(
      fetchTicketmasterEvent({
        eventId: EVENT_ID,
        apiKey: "test-key",
        fetch: async () => ({ ok: true, status: 200, json: async () => ({ fault: { faultstring: "Invalid API key" } }) })
      }),
      /Ticketmaster API error: Invalid API key/
    );

    await assert.rejects(
      fetchTicketmasterEvent({
        eventId: EVENT_ID,
        apiKey: "test-key",
        fetch: async () => ({ ok: true, status: 200, json: async () => ({}) })
      }),
      /missing event data/
    );
  });
});
