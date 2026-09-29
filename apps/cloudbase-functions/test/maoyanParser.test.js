import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  fetchMaoyanPerformance,
  parseMaoyanPerformance,
  parseMaoyanDetailHtml
} from "../src/functions/parseShowLink/maoyanParser.js";

describe("Maoyan performance adapter", () => {
  it("fetches the public performance endpoint using the extracted performance ID", async () => {
    let requestedUrl;
    const fetch = async (url) => {
      requestedUrl = url;
      return {
        ok: true,
        status: 200,
        json: async () => ({
          code: 0,
          data: {
            performanceId: 381177,
            name: "MIKA NAKASHIMA ASIA TOUR 2025 in SHENZHEN",
            shopName: "深圳国际会展中心20号馆",
            address: "广东省深圳市宝安区",
            posterUrl: "https://example.com/maoyan.jpg",
            showTimeRange: "2025.03.28 周五 19:30",
            cityName: "深圳",
            lowestPrice: "380"
          }
        })
      };
    };

    const detail = await fetchMaoyanPerformance({ performanceId: "381177", fetch });
    assert.equal(detail.performanceId, 381177);
    assert.match(requestedUrl, /\/performance\/381177/);
    assert.match(requestedUrl, /performanceId=381177/);
  });

  it("maps Maoyan performance data into the BeforeShow draft contract", () => {
    const draft = parseMaoyanPerformance({
      performanceId: 381177,
      name: "MIKA NAKASHIMA ASIA TOUR 2025 in SHENZHEN",
      shopName: "深圳国际会展中心20号馆",
      address: "广东省深圳市宝安区",
      posterUrl: "https://example.com/maoyan.jpg",
      showTimeRange: "2025.03.28 周五 19:30",
      cityName: "深圳",
      lowestPrice: "380"
    });

    assert.equal(draft.name, "MIKA NAKASHIMA ASIA TOUR 2025 in SHENZHEN");
    assert.equal(draft.city, "深圳");
    assert.equal(draft.date, "2025-03-28");
    assert.equal(draft.startTime, "19:30");
    assert.equal(draft.venueName, "深圳国际会展中心20号馆");
    assert.equal(draft.venueAddr, "广东省深圳市宝安区");
    assert.equal(draft.coverImageURL, "https://example.com/maoyan.jpg");
    assert.equal(draft.priceRange, "380");
    assert.equal(draft.source, "maoyan");
  });

  it("rejects an API response without performance data", async () => {
    const fetch = async () => ({
      ok: true,
      status: 200,
      json: async () => ({ code: 1, msg: "not found", data: null })
    });

    await assert.rejects(
      fetchMaoyanPerformance({ performanceId: "381177", fetch }),
      /Maoyan API error/
    );
  });

  it("drops malformed dates and clocks instead of normalizing them", () => {
    const draft = parseMaoyanPerformance({
      name: "Malformed",
      showTimeRange: "2026.02.31 24:60",
      cityName: "上海"
    });

    assert.equal(draft.date, "");
    assert.equal(draft.startTime, "");
  });

  it("prefers priceRange over lowestPrice when available", () => {
    const draft = parseMaoyanPerformance({
      name: "Test Concert",
      showTimeRange: "2026.10.06 18:30",
      cityName: "北京",
      lowestPrice: 398,
      priceRange: "398-1198"
    });

    assert.equal(draft.priceRange, "398-1198");
  });

  it("extracts structured detail from legacy Next.js HTML", () => {
    const html = `<!doctype html><html><head><title>Test</title></head><body>
      <script>
        __NEXT_DATA__ = {"props":{"pageProps":{"detail":{
          "performanceId": 503522,
          "name": "孟庭苇《孟里花落知多少·花开如初》演唱会-北京站·收官站",
          "shopName": "国家体育馆",
          "address": "天辰东路9号",
          "posterUrl": "https://example.com/poster.jpg",
          "showTimeRange": "2026.10.6 18:30 周二",
          "cityName": "北京",
          "priceRange": "398-1198",
          "lowestPrice": 398
        }}}}
        module={}
      </script>
    </body></html>`;

    const draft = parseMaoyanDetailHtml(html);
    assert.ok(draft);
    assert.equal(draft.name, "孟庭苇《孟里花落知多少·花开如初》演唱会-北京站·收官站");
    assert.equal(draft.city, "北京");
    assert.equal(draft.date, "2026-10-06");
    assert.equal(draft.startTime, "18:30");
    assert.equal(draft.venueName, "国家体育馆");
    assert.equal(draft.venueAddr, "天辰东路9号");
    assert.equal(draft.coverImageURL, "https://example.com/poster.jpg");
    assert.equal(draft.priceRange, "398-1198");
    assert.equal(draft.source, "maoyan");
  });

  it("extracts structured detail from modern Next.js script tag", () => {
    const html = `<!doctype html><html><head>
      <script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"detail":{
        "name": "现代 Next.js 演出",
        "shopName": "梅赛德斯-奔驰文化中心",
        "address": "世博大道1200号",
        "posterUrl": "https://example.com/modern.jpg",
        "showTimeRange": "2026.11.15 19:30 周日",
        "cityName": "上海",
        "lowestPrice": "280"
      }}}}</script>
    </head><body></body></html>`;

    const draft = parseMaoyanDetailHtml(html);
    assert.ok(draft);
    assert.equal(draft.name, "现代 Next.js 演出");
    assert.equal(draft.city, "上海");
    assert.equal(draft.date, "2026-11-15");
    assert.equal(draft.startTime, "19:30");
    assert.equal(draft.venueName, "梅赛德斯-奔驰文化中心");
    assert.equal(draft.coverImageURL, "https://example.com/modern.jpg");
    assert.equal(draft.priceRange, "280");
  });
});
