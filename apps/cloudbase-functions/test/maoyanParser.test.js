import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  fetchMaoyanPerformance,
  parseMaoyanPerformance
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
});
