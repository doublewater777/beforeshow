import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { parseShowLink } from "../src/functions/parseShowLink/index.js";
import {
  detectPlatform,
  normalizeUrl,
  UnsupportedPlatformError
} from "../src/functions/parseShowLink/platformDetector.js";
import { parseVisibleEventPage } from "../src/functions/parseShowLink/ticketPageParser.js";

const OFFICIAL_LIVE_NATION_DOMAINS = [
  "livenation.com",
  "livenation.asia",
  "livenation.com.au",
  "livenation.be",
  "livenation.ca",
  "livenation.cn",
  "livenation.cz",
  "livenation.dk",
  "livenation.ee",
  "livenation.fi",
  "livenation.fr",
  "livenation.de",
  "livenation.hk",
  "livenation.hu",
  "livenation.co.il",
  "livenation.it",
  "livenation.co.jp",
  "livenation.lt",
  "livenation.nl",
  "livenation.co.nz",
  "livenation.no",
  "livenation.pl",
  "livenation.qa",
  "livenation.sg",
  "livenation.co.za",
  "livenation.kr",
  "livenation.es",
  "livenation.se",
  "livenation.com.tw",
  "livenation.co.th",
  "livenation.ae",
  "livenation.co.uk",
  "livenation.app.link"
];

describe("Live Nation platform detection", () => {
  for (const domain of OFFICIAL_LIVE_NATION_DOMAINS) {
    it(`accepts ${domain}`, () => {
      assert.equal(detectPlatform(`https://www.${domain}/event/example`), "livenation");
    });
  }

  it("normalizes current China and US event URL shapes", () => {
    const china = normalizeUrl(
      "https://www.livenation.cn/event/lany-soft-world-tour-beijing-tickets-edp1672890?utm_source=share"
    );
    assert.equal(china.platform, "livenation");
    assert.equal(china.eventId, "1672890");
    assert.equal(
      china.canonicalUrl,
      "https://www.livenation.cn/event/lany-soft-world-tour-beijing-tickets-edp1672890"
    );

    const us = normalizeUrl(
      "https://www.livenation.com/event/G5eYZblQoH8xr/lil-wayne-tha-carter-vi-tour?utm_source=share"
    );
    assert.equal(us.platform, "livenation");
    assert.equal(us.eventId, "G5eYZblQoH8xr");
    assert.equal(
      us.canonicalUrl,
      "https://www.livenation.com/event/G5eYZblQoH8xr/lil-wayne-tha-carter-vi-tour"
    );
  });

  it("rejects Live Nation lookalike domains", () => {
    for (const url of [
      "https://livenation.com.evil.example/event/test",
      "https://livenation.cn.evil.example/event/test",
      "https://livenation.app.link.evil.example/test"
    ]) {
      assert.throws(
        () => detectPlatform(url),
        (error) => error instanceof UnsupportedPlatformError
      );
    }
  });
});

describe("Live Nation visible-page fallback", () => {
  it("parses the current US event-page shape including hour-only PM time", () => {
    const html = `
      <html>
        <head><title>Lil Wayne: Tha Carter VI Tour - Live Nation</title></head>
        <body>
          <h1>Lil Wayne: Tha Carter VI Tour</h1>
          <div>Fri Sep 12, 2026 ▪︎ 8PM</div>
          <div>Crypto.com Arena</div>
          <div>Los Angeles, CA</div>
          <h2>Lineup</h2>
          <div>Lil Wayne</div>
        </body>
      </html>`;

    const draft = parseVisibleEventPage(html, { source: "livenation" });
    assert.equal(draft.name, "Lil Wayne: Tha Carter VI Tour");
    assert.equal(draft.date, "2026-09-12");
    assert.equal(draft.startTime, "20:00");
    assert.equal(draft.venueName, "Crypto.com Arena");
    assert.equal(draft.city, "Los Angeles");
    assert.equal(draft.artist, "Lil Wayne");
    assert.equal(draft.source, "livenation");
  });

  it("parses the current China day-month-year and venue-city shape", () => {
    const html = `
      <html>
        <head><title>LANY: soft world tour - Live Nation</title></head>
        <body>
          <h1>LANY: soft world tour</h1>
          <div>周日, 20 9月 2026</div>
          <div>蛙厂RMMF·798店, Beijing</div>
          <h2>主要演出</h2>
          <div>LANY</div>
        </body>
      </html>`;

    const draft = parseVisibleEventPage(html, { source: "livenation" });
    assert.equal(draft.name, "LANY: soft world tour");
    assert.equal(draft.date, "2026-09-20");
    assert.equal(draft.venueName, "蛙厂RMMF·798店");
    assert.equal(draft.city, "Beijing");
    assert.equal(draft.artist, "LANY");
    assert.equal(draft.source, "livenation");
  });
});

describe("Live Nation dispatch", () => {
  it("uses the shared public-page adapter without following Buy Tickets links", async () => {
    let requestedUrl = "";
    const fetch = async (requestUrl) => {
      requestedUrl = requestUrl;
      return {
        ok: true,
        status: 200,
        url: requestUrl,
        text: async () => `
          <script type="application/ld+json">
          {
            "@context": "https://schema.org",
            "@type": "MusicEvent",
            "name": "LANY: soft world tour",
            "startDate": "2026-09-20T19:30:00+08:00",
            "location": {
              "@type": "Place",
              "name": "蛙厂RMMF·798店",
              "address": {"addressLocality": "Beijing"}
            },
            "performer": [{"@type": "MusicGroup", "name": "LANY"}]
          }
          </script>`
      };
    };

    const draft = await parseShowLink(
      "https://www.livenation.cn/event/lany-soft-world-tour-beijing-tickets-edp1672890?utm_source=share",
      { fetch }
    );

    assert.equal(
      requestedUrl,
      "https://www.livenation.cn/event/lany-soft-world-tour-beijing-tickets-edp1672890"
    );
    assert.equal(draft.source, "livenation");
    assert.equal(draft.name, "LANY: soft world tour");
    assert.equal(draft.date, "2026-09-20");
    assert.equal(draft.startTime, "19:30");
    assert.equal(draft.artist, "LANY");
  });
});
