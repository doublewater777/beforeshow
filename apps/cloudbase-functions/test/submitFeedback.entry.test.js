import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { main } from "../src/functions/submitFeedback/entry.js";

const validAuth = {
  appInstanceId: "test-instance",
  appSignature: "beforeshow-app-signature-v1"
};

describe("submitFeedback entry", () => {
  it("rejects an invalid app signature before rate limiting or writing", async () => {
    let rateLimitCalls = 0;
    let writeCount = 0;

    const result = await main({
      appInstanceId: "test-instance",
      appSignature: "wrong-signature",
      message: "hello"
    }, {}, {
      consumeRateLimit: async () => {
        rateLimitCalls += 1;
        return true;
      },
      writeFeedback: async () => {
        writeCount += 1;
      }
    });

    assert.equal(result.ok, false);
    assert.equal(result.error.code, "APP_AUTH_INVALID");
    assert.equal(rateLimitCalls, 0);
    assert.equal(writeCount, 0);
  });

  it("rejects an empty message without consuming rate limit", async () => {
    let rateLimitCalls = 0;

    const result = await main({
      ...validAuth,
      message: "   "
    }, {}, {
      consumeRateLimit: async () => {
        rateLimitCalls += 1;
        return true;
      }
    });

    assert.equal(result.ok, false);
    assert.equal(result.error.code, "MESSAGE_REQUIRED");
    assert.equal(rateLimitCalls, 0);
  });

  it("rejects messages over the size limit without consuming rate limit", async () => {
    let rateLimitCalls = 0;

    const result = await main({
      ...validAuth,
      message: "x".repeat(2001)
    }, {}, {
      consumeRateLimit: async () => {
        rateLimitCalls += 1;
        return true;
      }
    });

    assert.equal(result.ok, false);
    assert.equal(result.error.code, "MESSAGE_TOO_LONG");
    assert.equal(rateLimitCalls, 0);
  });

  it("rejects a rate-limited request without writing", async () => {
    let writeCount = 0;

    const result = await main({
      ...validAuth,
      message: "hello"
    }, {}, {
      consumeRateLimit: async ({ appInstanceId }) => {
        assert.equal(appInstanceId, "test-instance");
        return false;
      },
      writeFeedback: async () => {
        writeCount += 1;
      }
    });

    assert.equal(result.ok, false);
    assert.equal(result.error.code, "RATE_LIMITED");
    assert.equal(writeCount, 0);
  });

  it("fails closed when rate limiting is unavailable", async () => {
    let writeCount = 0;

    const result = await main({
      ...validAuth,
      message: "hello"
    }, {}, {
      consumeRateLimit: async () => {
        throw new Error("rate limiter unavailable");
      },
      writeFeedback: async () => {
        writeCount += 1;
      }
    });

    assert.equal(result.ok, false);
    assert.equal(result.error.code, "RATE_LIMIT_UNAVAILABLE");
    assert.equal(writeCount, 0);
  });

  it("stores only the feedback message and minimal diagnostics", async () => {
    let stored;
    const now = new Date("2026-09-27T10:00:00.000Z");

    const result = await main({
      ...validAuth,
      message: "  希望这里更顺手  ",
      appVersion: "1.0",
      osVersion: "iOS 26.0",
      showName: "must not be stored"
    }, {}, {
      randomUUID: () => "feedback-id",
      now: () => now,
      consumeRateLimit: async () => true,
      writeFeedback: async (record) => {
        stored = record;
      }
    });

    assert.deepEqual(result, { ok: true, feedbackId: "feedback-id" });
    assert.deepEqual(stored, {
      feedbackId: "feedback-id",
      message: "希望这里更顺手",
      appVersion: "1.0",
      osVersion: "iOS 26.0",
      submittedAt: "2026-09-27T10:00:00.000Z"
    });
    assert.equal("appInstanceId" in stored, false);
    assert.equal("appSignature" in stored, false);
    assert.equal("showName" in stored, false);
  });
});
