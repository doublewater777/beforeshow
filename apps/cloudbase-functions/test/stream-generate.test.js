import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  createCandidateSongsItemExtractor,
  formatSseEvent,
  parseOpenAIStreamChunk
} from "../src/providers/streamJsonItems.js";
import { generateSseFrames } from "../src/functions/generate/generateStream.js";
import { GENERATION_TYPES } from "../src/contracts/generationContracts.js";

describe("streamJsonItems", () => {
  it("emits complete items as the items array streams in", () => {
    const extractor = createCandidateSongsItemExtractor();
    assert.deepEqual(extractor.push('{"type":"candidateSongs","items":['), []);
    assert.deepEqual(
      extractor.push('{"songName":"春野","artist":"DOUDOU","tier":"high","hint":"近巡必唱"}'),
      [{ songName: "春野", artist: "DOUDOU", tier: "high", hint: "近巡必唱" }]
    );
    assert.deepEqual(extractor.push(","), []);
    const second = extractor.push('{"songName":"U&I","artist":"刘雨昕","tier":"mid","hint":"热歌候选"}');
    assert.equal(second.length, 1);
    assert.equal(second[0].songName, "U&I");
    assert.equal(extractor.items.length, 2);
  });

  it("does not promote extracted items when the final JSON is truncated", () => {
    const extractor = createCandidateSongsItemExtractor();
    extractor.push('{"type":"candidateSongs","items":[');
    extractor.push('{"songName":"残缺","artist":"艺人","tier":"mid","hint":"候选"}');

    assert.equal(extractor.items.length, 1);
    assert.equal(extractor.finalObject(), null);
  });

  it("parses OpenAI stream chunks and done markers", () => {
    assert.deepEqual(
      parseOpenAIStreamChunk('data: {"choices":[{"delta":{"content":"{\\"type\\""}}]}'),
      { kind: "delta", text: '{"type"' }
    );
    assert.deepEqual(parseOpenAIStreamChunk("data: [DONE]"), { kind: "done" });
    assert.deepEqual(parseOpenAIStreamChunk(": keep-alive"), { kind: "ignore" });
  });

  it("formats SSE frames", () => {
    assert.equal(
      formatSseEvent("item", { item: { songName: "A", artist: "B" } }),
      'event: item\ndata: {"item":{"songName":"A","artist":"B"}}\n\n'
    );
  });
});

describe("generateSseFrames", () => {
  it("streams item events then done for candidateSongs", async () => {
    const request = {
      type: GENERATION_TYPES.candidateSongs,
      requestId: "req-stream-1",
      locale: "zh-CN",
      show: {
        name: "绿洲音乐节",
        date: "2026-06-27",
        type: "musicFestival",
        artists: ["刘雨昕", "DOUDOU"]
      },
      limits: { maxSongs: 10 }
    };

    async function* streamProvider() {
      yield {
        kind: "item",
        item: { songName: "U&I", artist: "刘雨昕", tier: "high", hint: "近巡必唱" }
      };
      yield {
        kind: "item",
        item: { songName: "春野", artist: "DOUDOU", tier: "mid", hint: "热歌候选" }
      };
      yield {
        kind: "done",
        durationMs: 12,
        response: {
          type: "candidateSongs",
          items: [
            { songName: "U&I", artist: "刘雨昕", tier: "high", hint: "近巡必唱" },
            { songName: "春野", artist: "DOUDOU", tier: "mid", hint: "热歌候选" }
          ]
        }
      };
    }

    const frames = [];
    for await (const frame of generateSseFrames(request, {
      providers: [{ name: "mock", model: "m", apiKey: "k", apiKeyEnv: "K", baseUrl: "https://example.com" }],
      streamProvider
    })) {
      frames.push(frame);
    }

    assert.ok(frames.some((frame) => frame.startsWith("event: meta")));
    assert.ok(frames.some((frame) => frame.startsWith("event: item")));
    assert.ok(frames.some((frame) => frame.startsWith("event: done")));
    assert.equal(frames.filter((frame) => frame.startsWith("event: item")).length, 2);
    assert.ok(frames.at(-1).includes("\"ok\":true"));
    // Items must come only after provider stream completes (buffered until validated).
    const firstItem = frames.findIndex((frame) => frame.startsWith("event: item"));
    const doneIndex = frames.findIndex((frame) => frame.startsWith("event: done"));
    assert.ok(firstItem >= 0 && doneIndex > firstItem);
  });

  it("does not emit failed provider items when fallback provider succeeds", async () => {
    const request = {
      type: GENERATION_TYPES.candidateSongs,
      requestId: "req-fallback-1",
      locale: "zh-CN",
      show: {
        name: "绿洲音乐节",
        date: "2026-06-27",
        type: "musicFestival",
        artists: ["刘雨昕", "DOUDOU"]
      },
      limits: { maxSongs: 10 }
    };

    let call = 0;
    async function* streamProvider() {
      call += 1;
      if (call === 1) {
        yield {
          kind: "item",
          item: { songName: "A-only", artist: "ProviderA", tier: "high", hint: "无效A" }
        };
        throw new Error("provider A failed after item");
      }
      yield {
        kind: "item",
        item: { songName: "B-song", artist: "ProviderB", tier: "high", hint: "近巡必唱" }
      };
      yield {
        kind: "done",
        durationMs: 8,
        response: {
          type: "candidateSongs",
          items: [
            { songName: "B-song", artist: "ProviderB", tier: "high", hint: "近巡必唱" }
          ]
        }
      };
    }

    const frames = [];
    for await (const frame of generateSseFrames(request, {
      providers: [
        { name: "provider-a", model: "m", apiKey: "k", apiKeyEnv: "K", baseUrl: "https://a.example" },
        { name: "provider-b", model: "m", apiKey: "k", apiKeyEnv: "K", baseUrl: "https://b.example" }
      ],
      streamProvider
    })) {
      frames.push(frame);
    }

    const itemFrames = frames.filter((frame) => frame.startsWith("event: item"));
    assert.equal(itemFrames.length, 1);
    assert.ok(itemFrames[0].includes("B-song"));
    assert.ok(!itemFrames[0].includes("A-only"));
    assert.ok(frames.some((frame) => frame.startsWith("event: done")));
    assert.ok(!frames.some((frame) => frame.startsWith("event: error")));
  });

  it("emits only final validated items when streamed items differ", async () => {
    const request = {
      type: GENERATION_TYPES.candidateSongs,
      requestId: "req-corrected-final",
      locale: "zh-CN",
      show: {
        name: "测试现场",
        date: "2026-07-20",
        type: "concert",
        artists: ["艺人"]
      },
      limits: { maxSongs: 12 }
    };

    async function* streamProvider() {
      yield {
        kind: "item",
        item: { songName: "模型中途草稿", artist: "艺人", tier: "bogus", hint: "草稿" }
      };
      yield {
        kind: "done",
        durationMs: 3,
        response: {
          type: "candidateSongs",
          items: [{ songName: "最终曲目", artist: "艺人", tier: "high", hint: "近巡必唱" }]
        }
      };
    }

    const frames = [];
    for await (const frame of generateSseFrames(request, {
      providers: [{ name: "mock", model: "m", apiKey: "k", apiKeyEnv: "K", baseUrl: "https://example.com" }],
      streamProvider
    })) {
      frames.push(frame);
    }

    const itemFrames = frames.filter((frame) => frame.startsWith("event: item"));
    assert.equal(itemFrames.length, 1);
    assert.ok(itemFrames[0].includes("最终曲目"));
    assert.ok(!itemFrames[0].includes("模型中途草稿"));
    assert.ok(!itemFrames[0].includes("bogus"));
  });

  it("emits error without done when all providers fail", async () => {
    const request = {
      type: GENERATION_TYPES.candidateSongs,
      requestId: "req-all-fail",
      locale: "zh-CN",
      show: {
        name: "绿洲音乐节",
        date: "2026-06-27",
        type: "musicFestival",
        artists: ["刘雨昕"]
      },
      limits: { maxSongs: 10 }
    };

    async function* streamProvider() {
      yield {
        kind: "item",
        item: { songName: "Ghost", artist: "X", tier: "mid", hint: "无效" }
      };
      throw new Error("boom");
    }

    async function callProvider() {
      throw new Error("non-stream also failed");
    }

    const frames = [];
    for await (const frame of generateSseFrames(request, {
      providers: [
        { name: "a", model: "m", apiKey: "k", apiKeyEnv: "K", baseUrl: "https://a.example" },
        { name: "b", model: "m", apiKey: "k", apiKeyEnv: "K", baseUrl: "https://b.example" }
      ],
      streamProvider,
      callProvider
    })) {
      frames.push(frame);
    }

    assert.ok(frames.some((frame) => frame.startsWith("event: error")));
    assert.ok(!frames.some((frame) => frame.startsWith("event: done")));
    assert.ok(!frames.some((frame) => frame.startsWith("event: item")));
  });
});
