import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { main } from "../src/functions/listFeedback/entry.js";

const adminToken = "operator-secret";

describe("listFeedback entry", () => {
  it("fails closed when the admin token is not configured", async () => {
    const result = await main({
      headers: { authorization: "Bearer anything" }
    }, {}, {
      adminToken: ""
    });

    assert.equal(result.ok, false);
    assert.equal(result.error.code, "ADMIN_NOT_CONFIGURED");
  });

  it("rejects a wrong admin token without reading feedback", async () => {
    let readCount = 0;
    const result = await main({
      headers: { authorization: "Bearer wrong-secret" }
    }, {}, {
      adminToken,
      readFeedback: async () => {
        readCount += 1;
        return [];
      }
    });

    assert.equal(result.ok, false);
    assert.equal(result.error.code, "ADMIN_UNAUTHORIZED");
    assert.equal(readCount, 0);
  });

  it("returns recent feedback and strips unexpected database fields", async () => {
    let requestedLimit = 0;
    const result = await main({
      headers: { authorization: `Bearer ${adminToken}` },
      query: { limit: "25" }
    }, {}, {
      adminToken,
      readFeedback: async ({ limit }) => {
        requestedLimit = limit;
        return [{
          feedbackId: "feedback-1",
          message: "希望这里更顺手",
          appVersion: "1.0",
          osVersion: "iOS 26.0",
          submittedAt: "2026-09-27T10:00:00.000Z",
          _id: "database-id",
          appInstanceId: "must-not-leak"
        }];
      }
    });

    assert.equal(requestedLimit, 25);
    assert.deepEqual(result, {
      ok: true,
      feedback: [{
        feedbackId: "feedback-1",
        message: "希望这里更顺手",
        appVersion: "1.0",
        osVersion: "iOS 26.0",
        submittedAt: "2026-09-27T10:00:00.000Z"
      }]
    });
  });

  it("defaults invalid limits and caps large limits", async () => {
    const limits = [];

    await main({
      headers: { authorization: `Bearer ${adminToken}` },
      query: { limit: "invalid" }
    }, {}, {
      adminToken,
      readFeedback: async ({ limit }) => {
        limits.push(limit);
        return [];
      }
    });

    await main({
      headers: { authorization: `Bearer ${adminToken}` },
      query: { limit: "999" }
    }, {}, {
      adminToken,
      readFeedback: async ({ limit }) => {
        limits.push(limit);
        return [];
      }
    });

    assert.deepEqual(limits, [50, 100]);
  });
});
