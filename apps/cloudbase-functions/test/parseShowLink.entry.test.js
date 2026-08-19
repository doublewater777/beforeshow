import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { main } from "../src/functions/parseShowLink/entry.js";

describe("parseShowLink entry", () => {
  it("returns error when URL is missing", async () => {
    const result = await main({
      appInstanceId: "test",
      appSignature: "signature"
    }, {}, {});

    assert.equal(result.ok, false);
    assert.equal(result.error.code, "URL_REQUIRED");
  });

  it("returns parsed draft for supported link", async () => {
    const result = await main({
      appInstanceId: "test",
      appSignature: "signature",
      body: {
        url: "https://m.damai.cn/shows/item.html?itemId=1057554781223"
      }
    }, {}, {
      fetch: globalThis.fetch
    });

    assert.equal(result.ok, true);
    assert.equal(result.draft.source, "damai");
    assert.equal(result.auth.accountless, true);
  });

  it("returns NOT_A_SHOW for Damai merchandise links", async () => {
    const merchandisePayload = {
      ret: ["SUCCESS::调用成功"],
      data: {
        item: {
          itemName: "薛之谦-万兽之王巡回演唱会-官方荧光棒",
          showTime: "2026年8月7日-12月31日",
          showTimeCustom: "true"
        },
        venue: {
          venueName: "演出场馆地址待定",
          venueAddr: "薛之谦万兽之王巡回演唱会"
        }
      }
    };
    const stubFetch = async (url) => {
      if (String(url).includes(`sign=${"a".repeat(32)}`)) {
        return {
          headers: { get: () => "_m_h5_tk=abc123_1; Path=/; _m_h5_tk_enc=def456; Path=/" }
        };
      }
      return { ok: true, text: async () => JSON.stringify(merchandisePayload) };
    };

    const result = await main({
      appInstanceId: "test",
      appSignature: "signature",
      body: {
        url: "https://m.damai.cn/shows/item.html?itemId=1065385649255"
      }
    }, {}, {
      fetch: stubFetch
    });

    assert.equal(result.ok, false);
    assert.equal(result.error.code, "NOT_A_SHOW");
  });

  it("returns unsupported error for unknown platform", async () => {
    const result = await main({
      appInstanceId: "test",
      appSignature: "signature",
      body: {
        url: "https://example.com/show/123"
      }
    }, {}, {});

    assert.equal(result.ok, false);
    assert.equal(result.error.code, "UNSUPPORTED_PLATFORM");
  });

  it("accepts HTTP string bodies from the iOS client", async () => {
    const result = await main({
      body: JSON.stringify({
        appInstanceId: "test",
        appSignature: "signature",
        url: "https://example.com/show/123"
      })
    }, {}, {});

    assert.equal(result.ok, false);
    assert.equal(result.auth.accountless, true);
    assert.equal(result.error.code, "UNSUPPORTED_PLATFORM");
  });
});
