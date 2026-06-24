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
    assert.equal(result.draft.type, "concert");
    assert.equal(result.auth.accountless, true);
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
