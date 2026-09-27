import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { main } from "../src/functions/submitFeedback/entry.js";

describe("submitFeedback entry", () => {
  it("rejects an empty message", async () => {
    let writeCount = 0;

    const result = await main({
      appInstanceId: "test-instance",
      appSignature: "test-signature",
      message: "   "
    }, {}, {
      writeFeedback: async () => {
        writeCount += 1;
      }
    });

    assert.equal(result.ok, false);
    assert.equal(result.error.code, "MESSAGE_REQUIRED");
    assert.equal(writeCount, 0);
  });

  it("stores only the feedback message and minimal diagnostics", async () => {
    let stored;
    const now = new Date("2026-09-27T10:00:00.000Z");

    const result = await main({
      appInstanceId: "private-instance",
      appSignature: "private-signature",
      message: "  希望这里更顺手  ",
      appVersion: "1.0",
      osVersion: "iOS 26.0",
      showName: "must not be stored"
    }, {}, {
      randomUUID: () => "feedback-id",
      now: () => now,
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

  it("rejects messages over the size limit", async () => {
    const result = await main({
      appInstanceId: "test-instance",
      appSignature: "test-signature",
      message: "x".repeat(2001)
    });

    assert.equal(result.ok, false);
    assert.equal(result.error.code, "MESSAGE_TOO_LONG");
  });
});
