import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  GENERATION_TYPES,
  ContractError,
  selectValidProviderResponse,
  validateGenerationRequest,
  validateGenerationResponse
} from "../src/contracts/generationContracts.js";

describe("generation contracts", () => {
  it("accepts a minimal candidate songs request and defaults a missing tier", () => {
    const request = validateGenerationRequest({
      type: GENERATION_TYPES.candidateSongs,
      requestId: "req-candidate-1",
      locale: "zh-CN",
      show: {
        name: "落日飞车 北京站",
        date: "2026-07-01",
        city: "北京",
        venueName: "疆进酒",
        type: "concert",
        artists: ["落日飞车"]
      },
      limits: {
        maxSongs: 24
      }
    });

    const response = validateGenerationResponse(GENERATION_TYPES.candidateSongs, {
      type: GENERATION_TYPES.candidateSongs,
      items: [
        { songName: "Vanilla Villa", artist: "落日飞车" },
        { songName: "My Jinji", artist: "落日飞车" }
      ]
    });

    assert.equal(request.show.type, "concert");
    assert.deepEqual(response.items[0], {
      songName: "Vanilla Villa",
      artist: "落日飞车",
      tier: "mid"
    });
  });

  it("accepts four song tiers, optional hints, and legacy confidence", () => {
    const withTiers = validateGenerationResponse(GENERATION_TYPES.candidateSongs, {
      type: GENERATION_TYPES.candidateSongs,
      items: [
        { songName: "A", artist: "Artist", tier: "high", hint: "这轮巡演主题曲" },
        { songName: "B", artist: "Artist", tier: "mid" },
        { songName: "C", artist: "Artist", tier: "guest", hint: "给北京场的彩蛋" },
        { songName: "D", artist: "Artist", tier: "encore" },
        { songName: "E", artist: "Artist" },
        { songName: "F", artist: "Artist", confidence: "high" }
      ]
    });

    assert.deepEqual(withTiers.items.map((item) => item.tier), ["high", "mid", "guest", "encore", "mid", "high"]);
    assert.equal(withTiers.items[0].hint, "这轮巡演主题曲");
    assert.equal(withTiers.items[1].hint, undefined);
  });

  it("rejects candidate song lyrics, URLs, numeric tiers, invalid tiers and prose", () => {
    assert.throws(
      () => validateGenerationResponse(GENERATION_TYPES.candidateSongs, {
        type: GENERATION_TYPES.candidateSongs,
        items: [{
          songName: "Song",
          artist: "Artist",
          lyrics: "not allowed"
        }]
      }),
      errorWithCode("UNSUPPORTED_RESPONSE_FIELD")
    );

    assert.throws(
      () => validateGenerationResponse(GENERATION_TYPES.candidateSongs, {
        type: GENERATION_TYPES.candidateSongs,
        items: [{
          songName: "Song",
          artist: "Artist",
          recommendationReason: "not allowed"
        }]
      }),
      errorWithCode("UNSUPPORTED_RESPONSE_FIELD")
    );

    assert.throws(
      () => validateGenerationResponse(GENERATION_TYPES.candidateSongs, {
        type: GENERATION_TYPES.candidateSongs,
        items: [{
          songName: "Song",
          artist: "Artist",
          tier: 0
        }]
      }),
      errorWithCode("INVALID_SONG_TIER")
    );

    assert.throws(
      () => validateGenerationResponse(GENERATION_TYPES.candidateSongs, {
        type: GENERATION_TYPES.candidateSongs,
        items: [{
          songName: "Song",
          artist: "Artist",
          coverUrl: "https://example.com/song.jpg"
        }]
      }),
      errorWithCode("UNSUPPORTED_RESPONSE_FIELD")
    );

    assert.throws(
      () => validateGenerationResponse(GENERATION_TYPES.candidateSongs, {
        type: GENERATION_TYPES.candidateSongs,
        items: [{
          songName: "Song",
          artist: "Artist",
          tier: "low"
        }]
      }),
      errorWithCode("INVALID_SONG_TIER")
    );

    assert.throws(
      () => validateGenerationResponse(GENERATION_TYPES.candidateSongs, "Song - Artist"),
      errorWithCode("EXPECTED_OBJECT")
    );
  });

  it("requires only relevant round-trip draft request fields", () => {
    const request = validateGenerationRequest({
      type: GENERATION_TYPES.roundTripDraft,
      requestId: "req-trip-1",
      show: {
        name: "Livehouse 夜场",
        date: "2026-07-02",
        city: "上海",
        venueName: "育音堂",
        type: "livehouse"
      },
      direction: "outbound",
      userPlaces: {
        origin: "人民广场"
      },
      constraints: {
        arrivalBy: "19:30"
      }
    });

    assert.equal(request.direction, "outbound");
    assert.throws(
      () => validateGenerationRequest({
        ...request,
        rawPrompt: "please plan everything"
      }),
      errorWithCode("UNSUPPORTED_FIELD")
    );
  });

  it("accepts structured round-trip draft responses", () => {
    const response = validateGenerationResponse(GENERATION_TYPES.roundTripDraft, {
      type: GENERATION_TYPES.roundTripDraft,
      direction: "return",
      summary: "先确认末班车，再保留打车备选。",
      steps: [
        { title: "散场后", detail: "从场馆东侧出口离开。" }
      ],
      evidence: [
        { title: "地铁运营公告", url: "https://example.com/metro" }
      ]
    });

    assert.equal(response.steps.length, 1);
    assert.equal(response.evidence[0].title, "地铁运营公告");
  });

  it("rejects round-trip drafts without reliable evidence", () => {
    assert.throws(
      () => validateGenerationResponse(GENERATION_TYPES.roundTripDraft, {
        type: GENERATION_TYPES.roundTripDraft,
        direction: "outbound",
        summary: "提前出门，留出排队时间。",
        steps: [
          { title: "出发前", detail: "确认目的地。" }
        ]
      }),
      errorWithCode("EXPECTED_ARRAY")
    );

    assert.throws(
      () => validateGenerationResponse(GENERATION_TYPES.roundTripDraft, {
        type: GENERATION_TYPES.roundTripDraft,
        direction: "outbound",
        summary: "提前出门，留出排队时间。",
        steps: [
          { title: "出发前", detail: "确认目的地。" }
        ],
        evidence: []
      }),
      errorWithCode("ARRAY_TOO_SHORT")
    );
  });

  it("keeps return draft generation independent from outbound fields", () => {
    const request = validateGenerationRequest({
      type: GENERATION_TYPES.roundTripDraft,
      requestId: "req-return-1",
      show: {
        name: "Livehouse 夜场",
        date: "2026-07-02",
        city: "上海",
        venueName: "育音堂",
        type: "livehouse"
      },
      direction: "return",
      userPlaces: {
        hotel: "陕西南路附近酒店"
      },
      constraints: {
        departAfter: "22:30"
      }
    });

    assert.equal(request.direction, "return");
    assert.deepEqual(request.userPlaces, { hotel: "陕西南路附近酒店" });
  });

  it("falls back to Qwen when Doubao response violates the contract", () => {
    const selected = selectValidProviderResponse(GENERATION_TYPES.candidateSongs, [
      {
        provider: "doubao",
        response: {
          type: GENERATION_TYPES.candidateSongs,
          items: [{
            songName: "Song",
            artist: "Artist",
            lyrics: "not allowed"
          }]
        }
      },
      {
        provider: "qwen",
        response: {
          type: GENERATION_TYPES.candidateSongs,
          items: [{
            songName: "Song",
            artist: "Artist"
          }]
        }
      }
    ]);

    assert.equal(selected.provider, "qwen");
    assert.equal(selected.usedFallback, true);
  });

  it("rejects missing required fields", () => {
    assert.throws(
      () => validateGenerationRequest({
        type: GENERATION_TYPES.candidateSongs,
        requestId: "req-missing"
      }),
      errorWithCode("EXPECTED_OBJECT")
    );
  });
});

function errorWithCode(code) {
  return (error) => error instanceof ContractError && error.code === code;
}
