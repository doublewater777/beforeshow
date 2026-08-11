import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { parseShowLink } from "../src/functions/parseShowLink/index.js";
import {
  detectPlatform,
  normalizeUrl,
  UnsupportedPlatformError
} from "../src/functions/parseShowLink/platformDetector.js";
import { parsePublicEventPage } from "../src/functions/parseShowLink/publicEventParser.js";

const PLATFORM_CASES = [
  {
    platform: "maoyan",
    url: "https://show.maoyan.com/qqw#/detail/316942",
    source: "maoyan"
  },
  {
    platform: "piaoxingqiu",
    url: "https://e.piaoxingqiu.com/?lssId=68d4d422ed6bb699",
    source: "piaoxingqiu"
  },
  {
    platform: "fenwandao",
    url: "https://app.livelab.com.cn/show/987654?from=share",
    source: "fenwandao"
  },
  {
    platform: "ticketmaster",
    url: "https://www.ticketmaster.com/example-tour-los-angeles-california-09-19-2026/event/0D0060EABACB3E23?CAMEFROM=share",
    source: "ticketmaster"
  },
  {
    platform: "dice",
    url: "https://dice.fm/event/7dm3wp-dj-ty-segall-19th-feb-sid-the-cat-auditorium-south-pasadena-tickets?lng=en-US",
    source: "dice"
  },
  {
    platform: "axs",
    url: "https://www.axs.com/events/1018298/le-sserafim-tickets?skin=cryptoarena",
    source: "axs"
  }
];

const PUBLIC_PAGE_CASES = PLATFORM_CASES.filter(({ platform }) => platform !== "maoyan");

const JSON_LD_HTML = `<!doctype html>
<html>
<head>
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "MusicEvent",
  "name": "LE SSERAFIM PUREFLOW",
  "startDate": "2026-09-16T19:00:00-07:00",
  "endDate": "2026-09-16T21:30:00-07:00",
  "image": ["https://example.com/cover.jpg"],
  "location": {
    "@type": "Place",
    "name": "Crypto.com Arena",
    "address": {
      "@type": "PostalAddress",
      "streetAddress": "1111 S Figueroa St",
      "addressLocality": "Los Angeles",
      "addressRegion": "CA"
    }
  },
  "performer": [
    {"@type": "MusicGroup", "name": "LE SSERAFIM", "image": "https://example.com/artist.jpg"}
  ],
  "offers": {"@type": "Offer", "lowPrice": 80, "highPrice": 240, "priceCurrency": "USD"}
}
</script>
</head>
<body></body>
</html>`;

describe("additional ticket platform detection", () => {
  for (const { platform, url } of PLATFORM_CASES) {
    it(`detects ${platform}`, () => {
      assert.equal(detectPlatform(url), platform);
      assert.equal(normalizeUrl(url).platform, platform);
    });
  }

  it("extracts stable event IDs where the public URL exposes one", () => {
    assert.equal(normalizeUrl(PLATFORM_CASES[0].url).eventId, "316942");
    assert.equal(normalizeUrl(PLATFORM_CASES[3].url).eventId, "0D0060EABACB3E23");
    assert.equal(normalizeUrl(PLATFORM_CASES[5].url).eventId, "1018298");
  });

  it("keeps a Ticket Planet share token while dropping unrelated tracking", () => {
    const normalized = normalizeUrl(PLATFORM_CASES[1].url);
    assert.equal(normalized.shareToken, "68d4d422ed6bb699");
    assert.equal(normalized.canonicalUrl, "https://e.piaoxingqiu.com/?lssId=68d4d422ed6bb699");
  });

  it("rejects lookalike domains for every newly supported platform", () => {
    const spoofed = [
      "https://show.maoyan.com.evil.example/qqw#/detail/316942",
      "https://piaoxingqiu.com.evil.example/?lssId=x",
      "https://livelab.com.cn.evil.example/show/1",
      "https://ticketmaster.com.evil.example/event/ABC",
      "https://dice.fm.evil.example/event/test",
      "https://axs.com.evil.example/events/1/test"
    ];

    for (const url of spoofed) {
      assert.throws(
        () => detectPlatform(url),
        (error) => error instanceof UnsupportedPlatformError
      );
    }
  });
});

describe("public event page parser", () => {
  it("maps schema.org Event JSON-LD into the BeforeShow draft contract", () => {
    const draft = parsePublicEventPage(JSON_LD_HTML, { source: "ticketmaster" });

    assert.equal(draft.name, "LE SSERAFIM PUREFLOW");
    assert.equal(draft.city, "Los Angeles");
    assert.equal(draft.date, "2026-09-16");
    assert.equal(draft.startTime, "19:00");
    assert.equal(draft.endDate, "2026-09-16");
    assert.equal(draft.endTime, "21:30");
    assert.equal(draft.venueName, "Crypto.com Arena");
    assert.match(draft.venueAddr, /1111 S Figueroa St/);
    assert.equal(draft.artist, "LE SSERAFIM");
    assert.equal(draft.coverImageURL, "https://example.com/cover.jpg");
    assert.deepEqual(draft.artistAvatarURLs, ["https://example.com/artist.jpg"]);
    assert.equal(draft.priceRange, "USD 80-240");
    assert.equal(draft.source, "ticketmaster");
  });

  it("parses ISO 8601 dates with hyphen separators", () => {
    const html = `<script type="application/ld+json">
      {"@type":"MusicEvent","name":"ISO event","startDate":"2026-09-16T19:00:00-07:00"}
    </script>`;

    const draft = parsePublicEventPage(html, { source: "ticketmaster" });

    assert.equal(draft.date, "2026-09-16");
    assert.equal(draft.startTime, "19:00");
  });

  it("falls back to embedded JSON used by app-oriented ticket pages", () => {
    const html = `
      <script type="application/json">
      {
        "activityName": "测试巡回演唱会",
        "showTime": "2026.08.22 周六 19:30",
        "cityName": "杭州",
        "venueName": "杭州奥体中心体育馆",
        "venueAddress": "杭州市萧山区",
        "artists": [{"name": "测试艺人", "avatar": "https://example.com/a.jpg"}],
        "coverImageURL": "https://example.com/c.jpg",
        "price": "380-1280"
      }
      </script>`;

    const draft = parsePublicEventPage(html, { source: "piaoxingqiu" });
    assert.equal(draft.name, "测试巡回演唱会");
    assert.equal(draft.date, "2026-08-22");
    assert.equal(draft.startTime, "19:30");
    assert.equal(draft.city, "杭州");
    assert.equal(draft.venueName, "杭州奥体中心体育馆");
    assert.equal(draft.artist, "测试艺人");
    assert.equal(draft.source, "piaoxingqiu");
  });

  it("rejects invalid dates and times in structured event data", () => {
    const html = `<script type="application/ld+json">
      ${JSON.stringify({
        "@type": "MusicEvent",
        name: "Malformed event",
        startDate: "2026-02-31T24:60:00+08:00"
      })}
    </script>`;

    assert.throws(
      () => parsePublicEventPage(html, { source: "ticketmaster" }),
      /missing a name or date/
    );
  });
});

describe("additional platform dispatch", () => {
  it("parses Maoyan through the performance adapter", async () => {
    const fetch = async () => ({
      ok: true,
      status: 200,
      json: async () => ({
        code: 0,
        data: {
          performanceId: 316942,
          name: "猫眼测试现场",
          shopName: "测试场馆",
          address: "测试地址",
          posterUrl: "https://example.com/maoyan.jpg",
          showTimeRange: "2026.09.16 19:00",
          cityName: "上海",
          lowestPrice: "380"
        }
      })
    });

    const draft = await parseShowLink(PLATFORM_CASES[0].url, { fetch });
    assert.equal(draft.source, "maoyan");
    assert.equal(draft.date, "2026-09-16");
    assert.equal(draft.name, "猫眼测试现场");
  });

  for (const { platform, url, source } of PUBLIC_PAGE_CASES.filter(({ platform }) => platform !== "ticketmaster")) {
    it(`parses ${platform} through the public-page adapter`, async () => {
      let requestedUrl;
      const fetch = async (requestUrl) => {
        requestedUrl = requestUrl;
        return {
          ok: true,
          status: 200,
          url: requestUrl,
          text: async () => JSON_LD_HTML
        };
      };

      const draft = await parseShowLink(url, { fetch });
      assert.equal(draft.source, source);
      assert.equal(draft.date, "2026-09-16");
      assert.equal(draft.name, "LE SSERAFIM PUREFLOW");
      assert.ok(requestedUrl.startsWith("https://"));
    });
  }
});
