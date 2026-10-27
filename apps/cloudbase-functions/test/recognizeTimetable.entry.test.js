import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { main } from "../src/functions/recognizeTimetable/entry.js";
import { parseExchangeDocument } from "../src/functions/recognizeTimetable/document.js";
import { parseImages } from "../src/functions/recognizeTimetable/images.js";

const validAuth = {
  appInstanceId: "test-instance",
  appSignature: "beforeshow-app-signature-v1"
};

/** Minimal valid 1x1 JPEG */
const TINY_JPEG_BASE64 =
  "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAn/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCwAA8A/9k=";

const sampleDocument = {
  version: 1,
  timeZone: null,
  days: [{
    date: "2026-10-17",
    stages: [{
      name: "Can",
      performances: [{ artist: "TEST", start: "13:00", end: "14:00" }]
    }]
  }]
};

function allowRateLimit() {
  return {
    consumeRateLimit: async () => true
  };
}

describe("recognizeTimetable document helpers", () => {
  it("normalizes END/TBA ends to null and accepts fenced JSON", () => {
    const result = parseExchangeDocument(`\`\`\`json
{"version":1,"timeZone":null,"days":[{"date":"2026-10-16","stages":[{"name":"Can","performances":[{"artist":"A","start":"20:55","end":"END"},{"artist":"B","start":"21:00","end":"TBA"}]}]}]}
\`\`\``);

    assert.equal(result.ok, true);
    assert.equal(result.document.days[0].stages[0].performances[0].end, null);
    assert.equal(result.document.days[0].stages[0].performances[1].end, null);
  });

  it("repairs unclosed brackets and trailing commas", () => {
    const unclosed = `{"version":1,"timeZone":null,"days":[{"date":"2026-10-16","stages":[{"name":"Main","performances":[{"artist":"A","start":"20:00","end":"21:00"}]`;
    const result = parseExchangeDocument(unclosed);
    assert.equal(result.ok, true);
    assert.equal(result.document.days[0].stages[0].performances[0].artist, "A");
  });

  it("unnests days accidentally placed in stages", () => {
    const nested = JSON.stringify({
      version: 1,
      timeZone: null,
      days: [
        {
          date: "10-31",
          stages: [
            { name: "Main", performances: [{ artist: "A", start: "15:00", end: "16:00" }] },
            {
              date: "11-01",
              stages: [{ name: "Main", performances: [{ artist: "B", start: "16:00", end: "17:00" }] }]
            }
          ]
        }
      ]
    });
    const result = parseExchangeDocument(nested);
    assert.equal(result.ok, true);
    assert.equal(result.document.days.length, 2);
    assert.equal(result.document.days[0].date, "10-31");
    assert.equal(result.document.days[1].date, "11-01");
  });

  it("rejects unsupported version", () => {
    const result = parseExchangeDocument(JSON.stringify({ version: 2, days: [] }));
    assert.equal(result.ok, false);
    assert.equal(result.code, "UNSUPPORTED_VERSION");
  });
});

describe("recognizeTimetable image helpers", () => {
  it("accepts a single imageBase64 payload", () => {
    const result = parseImages({ imageBase64: TINY_JPEG_BASE64, mimeType: "image/jpeg" });
    assert.equal(result.ok, true);
    assert.equal(result.images.length, 1);
    assert.equal(result.images[0].mimeType, "image/jpeg");
  });

  it("rejects more than three images", () => {
    const result = parseImages({
      images: [
        { base64: TINY_JPEG_BASE64, mimeType: "image/jpeg" },
        { base64: TINY_JPEG_BASE64, mimeType: "image/jpeg" },
        { base64: TINY_JPEG_BASE64, mimeType: "image/jpeg" },
        { base64: TINY_JPEG_BASE64, mimeType: "image/jpeg" }
      ]
    });
    assert.equal(result.ok, false);
    assert.equal(result.code, "TOO_MANY_IMAGES");
  });
});

describe("recognizeTimetable entry", () => {
  it("rejects an invalid app signature before rate limiting or calling the model", async () => {
    let rateLimitCalls = 0;
    let modelCalls = 0;

    const result = await main({
      appInstanceId: "test-instance",
      appSignature: "wrong-signature",
      imageBase64: TINY_JPEG_BASE64
    }, {}, {
      consumeRateLimit: async () => {
        rateLimitCalls += 1;
        return true;
      },
      callModel: async () => {
        modelCalls += 1;
        return { content: JSON.stringify(sampleDocument), usage: null, model: "qwen3.7-flash" };
      }
    });

    assert.equal(result.ok, false);
    assert.equal(result.error.code, "APP_AUTH_INVALID");
    assert.equal(rateLimitCalls, 0);
    assert.equal(modelCalls, 0);
  });

  it("rejects missing images without consuming rate limit", async () => {
    let rateLimitCalls = 0;

    const result = await main({
      ...validAuth
    }, {}, {
      consumeRateLimit: async () => {
        rateLimitCalls += 1;
        return true;
      }
    });

    assert.equal(result.ok, false);
    assert.equal(result.error.code, "IMAGE_REQUIRED");
    assert.equal(rateLimitCalls, 0);
  });

  it("rejects a rate-limited request without calling the model", async () => {
    let modelCalls = 0;

    const result = await main({
      ...validAuth,
      imageBase64: TINY_JPEG_BASE64
    }, {}, {
      consumeRateLimit: async ({ appInstanceId }) => {
        assert.equal(appInstanceId, "test-instance");
        return false;
      },
      callModel: async () => {
        modelCalls += 1;
        return { content: "{}" };
      }
    });

    assert.equal(result.ok, false);
    assert.equal(result.error.code, "RATE_LIMITED");
    assert.equal(modelCalls, 0);
  });

  it("returns a normalized document from a successful model call", async () => {
    let seenPromptParts;

    const result = await main({
      ...validAuth,
      imageBase64: TINY_JPEG_BASE64,
      mimeType: "image/jpeg"
    }, {}, {
      ...allowRateLimit(),
      callModel: async ({ promptContent }) => {
        seenPromptParts = promptContent;
        return {
          content: JSON.stringify({
            version: 1,
            timeZone: null,
            days: [{
              date: "2026-10-18",
              stages: [{
                name: "CanWave",
                performances: [{ artist: "刘鸿林", start: "20:25", end: "END" }]
              }]
            }]
          }),
          usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 },
          model: "qwen3.7-flash"
        };
      }
    });

    assert.equal(result.ok, true);
    assert.equal(result.document.days[0].stages[0].performances[0].end, null);
    assert.equal(result.document.days[0].stages[0].performances[0].artist, "刘鸿林");
    assert.equal(result.model, "qwen3.7-flash");
    assert.deepEqual(result.usage, {
      promptTokens: 100,
      completionTokens: 50,
      totalTokens: 150
    });
    assert.equal(seenPromptParts[0].type, "image_url");
    assert.equal(seenPromptParts[1].type, "text");
    assert.match(seenPromptParts[1].text, /END \/ TBA/);
  });

  it("maps model transport failures to MODEL_FAILED", async () => {
    const result = await main({
      ...validAuth,
      imageBase64: TINY_JPEG_BASE64
    }, {}, {
      ...allowRateLimit(),
      callModel: async () => {
        const error = new Error("upstream 429");
        error.code = "MODEL_FAILED";
        throw error;
      }
    });

    assert.equal(result.ok, false);
    assert.equal(result.error.code, "MODEL_FAILED");
  });

  it("maps missing API key to MODEL_UNAVAILABLE", async () => {
    const result = await main({
      ...validAuth,
      imageBase64: TINY_JPEG_BASE64
    }, {}, {
      ...allowRateLimit(),
      callModel: async () => {
        const error = new Error("DASHSCOPE_API_KEY is not configured.");
        error.code = "MODEL_UNAVAILABLE";
        throw error;
      }
    });

    assert.equal(result.ok, false);
    assert.equal(result.error.code, "MODEL_UNAVAILABLE");
  });

  it("rejects unparseable model JSON after a successful call", async () => {
    const result = await main({
      ...validAuth,
      imageBase64: TINY_JPEG_BASE64
    }, {}, {
      ...allowRateLimit(),
      callModel: async () => ({
        content: "sorry I cannot help",
        usage: null,
        model: "qwen3.7-flash"
      })
    });

    assert.equal(result.ok, false);
    assert.equal(result.error.code, "INVALID_MODEL_OUTPUT");
  });
});
