import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { AppAuthError, assertAppAuthenticated } from "../src/auth/appAuth.js";
import { loadModelProviderConfig } from "../src/config/modelProviders.js";
import { main } from "../src/functions/generate/index.js";
import { containsSensitiveLogField, createTechnicalLog } from "../src/logging/technicalLog.js";

describe("CloudBase backend foundation", () => {
  it("uses Doubao as primary provider and Qwen as fallback without exposing credentials", () => {
    const config = loadModelProviderConfig({
      DOUBAO_API_KEY: "secret-doubao",
      QWEN_API_KEY: "secret-qwen"
    });

    assert.equal(config.primary.name, "doubao");
    assert.equal(config.primary.apiKeyEnv, "DOUBAO_API_KEY");
    assert.equal(config.fallback.name, "qwen");
    assert.equal(config.fallback.apiKeyEnv, "QWEN_API_KEY");
    assert.deepEqual(JSON.stringify(config).includes("secret-"), false);
  });

  it("authenticates app instances without requiring BeforeShow accounts", () => {
    const auth = assertAppAuthenticated(
      {
        appInstanceId: "device-installation-id",
        appSignature: "signed-app-proof"
      },
      {}
    );

    assert.equal(auth.accountless, true);
    assert.throws(
      () => assertAppAuthenticated({}, {}),
      (error) => error instanceof AppAuthError && error.code === "APP_AUTH_REQUIRED"
    );
  });

  it("keeps technical logs free of raw prompts, outputs and show details", () => {
    const log = createTechnicalLog({
      event: "generation.provider.failed",
      featureType: "candidateSongs",
      provider: "doubao",
      success: false,
      errorCode: "INVALID_PROVIDER_RESPONSE",
      durationMs: 248,
      prompt: "raw prompt",
      rawOutput: "raw output",
      showName: "不该进入日志的现场"
    }, new Date("2026-06-15T04:00:00.000Z"));

    assert.equal(log.featureType, "candidateSongs");
    assert.equal(log.provider, "doubao");
    assert.equal(containsSensitiveLogField(log), false);
    assert.equal(JSON.stringify(log).includes("raw prompt"), false);
    assert.equal(JSON.stringify(log).includes("不该进入日志"), false);
  });

  it("calls real provider clients and falls back without leaking secrets or raw output", async () => {
    const calls = [];
    const fetch = async (url, options) => {
      calls.push({ url, body: JSON.parse(options.body), authorization: options.headers.Authorization });
      const isDoubao = url.includes("volces");
      return {
        ok: true,
        status: 200,
        async text() {
          return JSON.stringify({
            choices: [{
              message: {
                content: JSON.stringify(isDoubao
                  ? {
                    type: "candidateSongs",
                    items: [{ songName: "Song", artist: "Artist", lyrics: "forbidden" }]
                  }
                  : {
                    type: "candidateSongs",
                    items: [{ songName: "Song", artist: "Artist" }]
                  })
              }
            }]
          });
        }
      };
    };

    const result = await main({
      appInstanceId: "app-instance",
      appSignature: "signature",
      body: {
        type: "candidateSongs",
        requestId: "req-entrypoint",
        show: {
          name: "测试现场",
          date: "2026-07-01",
          type: "concert"
        },
        limits: {
          maxSongs: 12
        }
      }
    }, {}, {
      env: {
        DOUBAO_API_KEY: "secret-doubao",
        QWEN_API_KEY: "secret-qwen"
      },
      fetch
    });

    assert.equal(result.ok, true);
    assert.equal(result.request.type, "candidateSongs");
    assert.equal(result.provider.name, "qwen");
    assert.equal(result.provider.usedFallback, true);
    assert.deepEqual(result.providers.map((provider) => provider.name), ["doubao", "qwen"]);
    assert.deepEqual(result.response.items, [{ songName: "Song", artist: "Artist", tier: "mid" }]);
    assert.match(calls[0].body.messages[0].content, /tier.*high\|mid\|guest\|encore/);
    assert.match(calls[0].body.messages[0].content, /hint/);
    assert.equal(calls.length, 2);
    assert.equal(JSON.stringify(result).includes("secret-"), false);
    assert.equal(JSON.stringify(result).includes("lyrics"), false);
    assert.equal(containsSensitiveLogField(result.log), false);
  });

  it("stops after primary when Doubao returns a valid response (ADR-0008 short-circuit)", async () => {
    const calls = [];
    const fetch = async (url, options) => {
      calls.push(url);
      return {
        ok: true,
        status: 200,
        async text() {
          return JSON.stringify({
            choices: [{
              message: {
                content: JSON.stringify({
                  type: "candidateSongs",
                  items: [{ songName: "Song", artist: "Artist" }]
                })
              }
            }]
          });
        }
      };
    };

    const result = await main({
      appInstanceId: "app-instance",
      appSignature: "signature",
      body: {
        type: "candidateSongs",
        requestId: "req-primary-only",
        show: {
          name: "测试现场",
          date: "2026-07-01",
          type: "concert"
        },
        limits: { maxSongs: 12 }
      }
    }, {}, {
      env: {
        DOUBAO_API_KEY: "secret-doubao",
        QWEN_API_KEY: "secret-qwen"
      },
      fetch
    });

    assert.equal(result.ok, true);
    assert.equal(result.provider.name, "doubao");
    assert.equal(result.provider.usedFallback, false);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].includes("volces"), true);
  });

  it("accepts HTTP string bodies from the iOS client", async () => {
    const fetch = async () => ({
      ok: true,
      status: 200,
      async text() {
        return JSON.stringify({
          choices: [{
            message: {
              content: JSON.stringify({
                type: "candidateSongs",
                items: [{ songName: "Song", artist: "Artist" }]
              })
            }
          }]
        });
      }
    });

    const result = await main({
      body: JSON.stringify({
        appInstanceId: "app-instance",
        appSignature: "signature",
        type: "candidateSongs",
        requestId: "req-http-body",
        locale: "zh-CN",
        show: {
          name: "测试现场",
          date: "2026-07-01",
          type: "concert"
        },
        limits: {
          maxSongs: 12
        }
      })
    }, {}, {
      env: {
        DOUBAO_API_KEY: "secret-doubao"
      },
      fetch
    });

    assert.equal(result.ok, true);
    assert.equal(result.request.requestId, "req-http-body");
    assert.deepEqual(result.response.items, [{ songName: "Song", artist: "Artist", tier: "mid" }]);
  });
});
