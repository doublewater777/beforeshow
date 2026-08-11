import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { parseShowLink } from "../src/functions/parseShowLink/index.js";
import {
  buildPiaoxingqiuStaticUrl,
  fetchAndParsePiaoxingqiu,
  parsePiaoxingqiuStatic
} from "../src/functions/parseShowLink/piaoxingqiuParser.js";

const SHOW_ID = "6a58b3fc6f908d000199294d";
const CONTENT_URL =
  `https://e.piaoxingqiu.com/content/${SHOW_ID}?showId=${SHOW_ID}`;

const STATIC_RESPONSE = {
  data: {
    rsCode: 200,
    basicInfo: {
      showName: "【广州】杨丞琳《房间里的大象》巡回演唱会-广州站",
      posterUrl: "https://example.com/poster.jpg",
      venueName: "宝能广州国际体育演艺中心",
      venueAddress: "广东省广州市黄埔区大塱村开创大道2666号",
      cityName: "广州市",
      showDate: "2026年08月29日 19:00",
      minOriginalPriceInfo: { yuanNum: "380", centNum: "" },
      maxOriginalPriceInfo: { yuanNum: "1380", centNum: "" }
    },
    descInfo: {
      observationInstructions: [
        { key: "MAIN_ACTOR", value: "杨丞琳" }
      ]
    }
  }
};

describe("piaoxingqiu static API parser", () => {
  it("maps the static response to the BeforeShow draft contract", () => {
    const draft = parsePiaoxingqiuStatic(STATIC_RESPONSE);

    assert.deepEqual(draft, {
      name: "【广州】杨丞琳《房间里的大象》巡回演唱会-广州站",
      city: "广州",
      date: "2026-08-29",
      startTime: "19:00",
      venueName: "宝能广州国际体育演艺中心",
      venueAddr: "广东省广州市黄埔区大塱村开创大道2666号",
      artist: "杨丞琳",
      coverImageURL: "https://example.com/poster.jpg",
      artistAvatarURLs: [],
      priceRange: "380 - 1380",
      source: "piaoxingqiu"
    });
  });

  it("builds the public static endpoint without forwarding tracking parameters", () => {
    const url = new URL(buildPiaoxingqiuStaticUrl({ showId: SHOW_ID }));

    assert.equal(
      url.pathname,
      `/cyy_gatewayapi/show/pub/v5/show/${SHOW_ID}/static`
    );
    assert.equal(url.searchParams.get("currency"), "CNY");
    assert.equal(url.searchParams.get("lang"), "zh");
    assert.equal(url.searchParams.get("terminalSrc"), "WEB");
    assert.equal(url.searchParams.get("utcOffset"), "480");
    assert.equal(url.searchParams.get("ver"), "4.64.11");
    assert.equal(url.searchParams.get("src"), "WEB");
    assert.equal(url.searchParams.get("source"), "FROM_QUICK_ORDER");
    assert.equal(url.searchParams.has("lssId"), false);
  });

  it("uses the injected fetch and sends JSON request headers", async () => {
    let requestedUrl;
    let requestedOptions;
    const fetch = async (url, options) => {
      requestedUrl = url;
      requestedOptions = options;
      return { ok: true, status: 200, json: async () => STATIC_RESPONSE };
    };

    const draft = await fetchAndParsePiaoxingqiu({
      eventId: SHOW_ID,
      canonicalUrl: CONTENT_URL,
      fetch
    });

    assert.equal(draft.name, STATIC_RESPONSE.data.basicInfo.showName);
    assert.match(requestedUrl, new RegExp(`/show/${SHOW_ID}/static\\?`));
    assert.equal(requestedOptions.headers.Accept, "application/json, text/plain, */*");
    assert.equal(requestedOptions.headers.Origin, "https://e.piaoxingqiu.com");
    assert.equal(requestedOptions.headers.Referer, CONTENT_URL);
  });

  it("rejects an API response without usable show data", async () => {
    await assert.rejects(
      () => fetchAndParsePiaoxingqiu({
        eventId: SHOW_ID,
        fetch: async () => ({
          ok: true,
          status: 200,
          json: async () => ({ data: { rsCode: 500 } })
        })
      }),
      /Piaoxingqiu API error/
    );

    assert.throws(
      () => parsePiaoxingqiuStatic({ data: {} }),
      /missing basicInfo/
    );
  });

  it("routes a content URL to the static adapter", async () => {
    let requestedUrl;
    const fetch = async (url) => {
      requestedUrl = url;
      return { ok: true, status: 200, json: async () => STATIC_RESPONSE };
    };

    const draft = await parseShowLink(CONTENT_URL, { fetch });

    assert.equal(draft.source, "piaoxingqiu");
    assert.equal(draft.date, "2026-08-29");
    assert.match(requestedUrl, new RegExp(`/show/${SHOW_ID}/static\\?`));
  });

  it("falls back to the canonical page when the static API fails", async () => {
    let requests = 0;
    const html = `<script type="application/ld+json">${JSON.stringify({
      "@type": "MusicEvent",
      name: "页面回退现场",
      startDate: "2026-09-16T19:00:00-07:00",
      location: { "@type": "Place", name: "Fallback Arena" }
    })}</script>`;

    const draft = await parseShowLink(CONTENT_URL, {
      fetch: async (url) => {
        requests += 1;
        if (requests === 1) return { ok: false, status: 503 };
        return { ok: true, status: 200, text: async () => html };
      }
    });

    assert.equal(requests, 2);
    assert.equal(draft.name, "页面回退现场");
    assert.equal(draft.startDateTime, "2026-09-16T19:00:00-07:00");
  });

  it("keeps a single price when the endpoints are equal", () => {
    const payload = structuredClone(STATIC_RESPONSE);
    payload.data.basicInfo.maxOriginalPriceInfo = { yuanNum: "380", centNum: "" };

    assert.equal(parsePiaoxingqiuStatic(payload).priceRange, "380");
  });
});
