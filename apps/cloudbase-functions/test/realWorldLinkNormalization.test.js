import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { normalizeUrl } from "../src/functions/parseShowLink/platformDetector.js";

describe("real-world domestic ticket share URLs", () => {
  it("extracts Maoyan performance ID from the qqw hash-route share URL", () => {
    const normalized = normalizeUrl(
      "https://show.maoyan.com/qqw?nonce=574a3351686368637548454253394c4c35316e3541773d3d#/detail/381177"
    );

    assert.equal(normalized.platform, "maoyan");
    assert.equal(normalized.eventId, "381177");
    assert.equal(normalized.canonicalUrl, "https://show.maoyan.com/qqw#/detail/381177");
  });

  it("extracts Ticket Planet show ID from the mobile content share URL", () => {
    const normalized = normalizeUrl(
      "https://m.piaoxingqiu.com/content/6791eae92f989f000189f6c4?src=preview&source=FROM_BACKEND&showId=6791eae92f989f000189f6c4"
    );

    assert.equal(normalized.platform, "piaoxingqiu");
    assert.equal(normalized.eventId, "6791eae92f989f000189f6c4");
    assert.equal(
      normalized.canonicalUrl,
      "https://m.piaoxingqiu.com/content/6791eae92f989f000189f6c4?showId=6791eae92f989f000189f6c4"
    );
  });

  it("extracts Ticket Planet show ID from the supplied e-domain content URL", () => {
    const showId = "6a58b3fc6f908d000199294d";
    const normalized = normalizeUrl(
      `https://e.piaoxingqiu.com/content/${showId}?showId=${showId}`
    );

    assert.equal(normalized.platform, "piaoxingqiu");
    assert.equal(normalized.eventId, showId);
    assert.equal(
      normalized.canonicalUrl,
      `https://m.piaoxingqiu.com/content/${showId}?showId=${showId}`
    );
  });

  it("extracts Fenwandao project ID from a mobile buy-ticket share URL", () => {
    const normalized = normalizeUrl(
      "https://mobile.livelab.com.cn/hppreview/pages/buyTickets/step1?channel=weibo&id=271&type=1"
    );

    assert.equal(normalized.platform, "fenwandao");
    assert.equal(normalized.eventId, "271");
    assert.equal(
      normalized.canonicalUrl,
      "https://mobile.livelab.com.cn/hppreview/pages/buyTickets/step1?id=271&type=1"
    );
  });

  it("accepts Fenwandao project_id and projectId aliases", () => {
    for (const key of ["project_id", "projectId"]) {
      const normalized = normalizeUrl(
        `https://mobile.livelab.com.cn/hppreview/pages/buyTickets/step1?${key}=271&type=1`
      );

      assert.equal(normalized.platform, "fenwandao");
      assert.equal(normalized.eventId, "271");
      assert.equal(
        normalized.canonicalUrl,
        "https://mobile.livelab.com.cn/hppreview/pages/buyTickets/step1?id=271&type=1"
      );
    }
  });
});
