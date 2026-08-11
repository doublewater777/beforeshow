import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { parseShowLink } from "../src/functions/parseShowLink/index.js";
import {
  detectPlatform,
  normalizeUrl,
  UnsupportedPlatformError
} from "../src/functions/parseShowLink/platformDetector.js";
import { parseLiveNationVisiblePage } from "../src/functions/parseShowLink/liveNationParser.js";

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
      "https://www.livenation.com/event/G5vYZ_kMttMwl/lil-wayne-20-years-of-carter-classics-with-the-game?utm_source=share"
    );
    assert.equal(us.platform, "livenation");
    assert.equal(us.eventId, "G5vYZ_kMttMwl");
    assert.equal(
      us.canonicalUrl,
      "https://www.livenation.com/event/G5vYZ_kMttMwl/lil-wayne-20-years-of-carter-classics-with-the-game"
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
  it("parses the current US page where the year is in the title and venue/city are separate lines", () => {
    const html = `
      <html>
        <head>
          <title>LIL WAYNE: 20 YEARS OF CARTER CLASSICS WITH THE GAME at Save Mart Center on Fri, Aug 28, 2026, 8:30 PM - Live Nation</title>
        </head>
        <body>
          <div>Fri, Aug 28 ▪︎ 8:30 PM</div>
          <h1>LIL WAYNE: 20 YEARS OF CARTER CLASSICS WITH THE GAME</h1>
          <div>Save Mart Center</div>
          <div>Fresno, CA</div>
          <h2>Lineup</h2>
          <div>Lil Wayne</div>
          <div>The Game</div>
        </body>
      </html>`;

    const draft = parseLiveNationVisiblePage(html);
    assert.equal(draft.name, "LIL WAYNE: 20 YEARS OF CARTER CLASSICS WITH THE GAME");
    assert.equal(draft.date, "2026-08-28");
    assert.equal(draft.startTime, "20:30");
    assert.equal(draft.venueName, "Save Mart Center");
    assert.equal(draft.city, "Fresno");
    assert.equal(draft.artist, "Lil Wayne");
    assert.equal(draft.source, "livenation");
  });

  it("parses the current US hour-only PM page shape", () => {
    const html = `
      <html>
        <head>
          <title>LIL WAYNE: 20 YEARS OF CARTER CLASSICS at Brandon Amphitheater on Sat, Aug 15, 2026, 8:00 PM - Live Nation</title>
        </head>
        <body>
          <div>Sat, Aug 15 ▪︎ 8 PM</div>
          <h1>LIL WAYNE: 20 YEARS OF CARTER CLASSICS</h1>
          <div>Brandon Amphitheater</div>
          <div>Brandon, MS</div>
          <h2>Lineup</h2>
          <div>Lil Wayne</div>
        </body>
      </html>`;

    const draft = parseLiveNationVisiblePage(html);
    assert.equal(draft.name, "LIL WAYNE: 20 YEARS OF CARTER CLASSICS");
    assert.equal(draft.date, "2026-08-15");
    assert.equal(draft.startTime, "20:00");
    assert.equal(draft.venueName, "Brandon Amphitheater");
    assert.equal(draft.city, "Brandon");
    assert.equal(draft.artist, "Lil Wayne");
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

    const draft = parseLiveNationVisiblePage(html);
    assert.equal(draft.name, "LANY: soft world tour");
    assert.equal(draft.date, "2026-09-20");
    assert.equal(draft.venueName, "蛙厂RMMF·798店");
    assert.equal(draft.city, "Beijing");
    assert.equal(draft.artist, "LANY");
    assert.equal(draft.source, "livenation");
  });

  it("parses a China page whose title embeds a date and whose sales-status text appears before the real artist", () => {
    const html = `
      <html>
        <head><title>LANY: soft world tour, Beijing, 周日, 20 9月 2026, , Tickets – www.livenation.cn</title></head>
        <body>
          <h1>LANY: soft world tour</h1>
          <div>周日, 20 9月 2026 + 2 dates</div>
          <div>蛙厂RMMF·798店, Beijing</div>
          <div>待售门票</div>
          <div>演出详情</div>
          <div>该演出中的艺人</div>
          <div>待售门票</div>
          <div>购买门票</div>
          <div>全面开售</div>
          <div>全面开售 全面开售 - 全面开售</div>
          <div>选择另一场次</div>
          <div>该演出中的艺人</div>
          <div>主要演出</div>
          <div>LANY</div>
        </body>
      </html>`;

    const draft = parseLiveNationVisiblePage(html);
    assert.equal(draft.name, "LANY: soft world tour");
    assert.equal(draft.date, "2026-09-20");
    assert.equal(draft.venueName, "蛙厂RMMF·798店");
    assert.equal(draft.city, "Beijing");
    assert.equal(draft.artist, "LANY");
  });

  it("parses the current China Chinese-month date-range shape", () => {
    const html = `
      <html>
        <body>
          <h1>Chris James \"LET THE LIGHT IN!\" TOUR 2026</h1>
          <div>12 八月 - 13 八月 2026</div>
          <div>星在文化中心 梦想剧场, Shanghai</div>
          <h2>主要演出</h2>
          <div>Chris James</div>
        </body>
      </html>`;

    const draft = parseLiveNationVisiblePage(html);
    assert.equal(draft.date, "2026-08-12");
    assert.equal(draft.endDate, "2026-08-13");
    assert.equal(draft.venueName, "星在文化中心 梦想剧场");
    assert.equal(draft.city, "Shanghai");
    assert.equal(draft.artist, "Chris James");
  });
});

describe("Live Nation dispatch", () => {
  it("uses the public-page adapter without following Buy Tickets links", async () => {
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
